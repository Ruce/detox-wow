local _, addonTbl = ...

Detox = LibStub("AceAddon-3.0"):NewAddon("Detox", "AceConsole-3.0", "AceHook-3.0")

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local config = addonTbl.config
local classifier = addonTbl.classifier
local history = addonTbl.history
local util = addonTbl.util

local isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)

local detoxPrimaryColorStr = "|cff6DF551"
local detoxSecondaryColorStr = "|cFF5BCFBB"
local detoxChatHiddenMessage = "(Detox) Toxic message hidden - click to show"
local detoxChatThrottledMessage = "(Detox) Throttle Mode: Blocking sender temporarily..."
local detoxToxicThresholdBaseline = 0.97
local detoxToxicStrictMultiplier = 2.0
local detoxToxicStrictFactor = 0.02 -- Will be scaled up by StrictMultiplier
local detoxToxicStrangerFactor = 0.02
local detoxToxicThrottleFactor = 0.05

local detoxProtectCriticalTime = 120
local detoxProtectHighTime = 600
local detoxProtectDeathFactor = 0.04
local detoxProtectCriticalFactor = 0.06
local detoxProtectHighFactor = 0.05

local detoxHiddenChats = {}
local detoxSenderHistory = {}
local detoxPrevChatLine = {}

-- Local implementation of AceConsole's Print function with custom formatting
local function Print(message, frame)
	local stamp = detoxPrimaryColorStr.."|Hdetox:options|h[Detox]|h|r"
	local printMessage = stamp.." "..tostring(message)
	
	if frame and type(frame) == "table" and frame.AddMessage then
		frame:AddMessage(printMessage)
	else
		DEFAULT_CHAT_FRAME:AddMessage(printMessage)
	end
end

local function RecreateChat(chat)
	local message = chat.message
	local timestampStr = date("%X", chat.timestamp)
	-- If chat is a Bnet whisper, senderGuid may be invalid
	if chat.event == "CHAT_MSG_BN_WHISPER" then
		return string.format("%s %s said: %s", timestampStr, chat.sender, message)
	else
		local locClass, engClass, locRace, engRace, gender, name, realm = GetPlayerInfoByGUID(chat.senderGuid)
		local _, _, _, classColorHex = GetClassColor(engClass)
		local nameStr = string.format("|c%s%s|r", classColorHex, name)
		return string.format("%s %s said: %s", timestampStr, nameStr, message)
	end
end

local bnetFriendsCache = {}
local function GetBnetTag(Kstring)
	if bnetFriendsCache[Kstring] then return bnetFriendsCache[Kstring] end
	
	local totalNumFriends = BNGetNumFriends()
	for i = 1, totalNumFriends do
		local accountName = nil
		local battleTag = nil
		if isRetail then
			local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
			accountName = accountInfo.accountName
			battleTag = accountInfo.battleTag
		else
			_, accountName, battleTag = BNGetFriendInfo(i)
		end
		bnetFriendsCache[accountName] = battleTag
		if accountName == Kstring then
			return battleTag
		end
	end
	
	return nil
end

local function IsTrustedSender(senderName, senderGuid)
	-- Check if message sender is the player (self) or whitelisted
	if senderGuid then
		if isRetail then
			if IsPlayerGuid(senderGuid) or 
			(Detox.db.profile.whitelistFriends and C_FriendList.IsFriend(senderGuid)) or
			(Detox.db.profile.whitelistGuild and IsGuildMember(senderGuid)) or
			(Detox.db.profile.whitelistBnet and C_BattleNet.GetAccountInfoByGUID(senderGuid) and C_BattleNet.GetAccountInfoByGUID(senderGuid)['isFriend']) then
				return true
			end
		else -- Classic
			if C_AccountInfo.IsGUIDRelatedToLocalAccount(senderGuid) or
			(Detox.db.profile.whitelistFriends and C_FriendList.IsFriend(senderGuid)) or
			(Detox.db.profile.whitelistGuild and IsGuildMember(senderGuid)) then
				return true
			end
			
			-- Bnet friend info is returned only if the friend is online (does not work if they appear offline)
			if Detox.db.profile.whitelistBnet then
				local BNGameAccountInfo = {BNGetGameAccountInfoByGUID(senderGuid)}
				local bNetIDAccount = BNGameAccountInfo[17]
				if bNetIDAccount and BNIsFriend(bNetIDAccount) then
					return true
				end
			end
		end
	end
	
	if senderName then
		local hyphen = senderName:find('-') -- Find the hyphen for separating realm name from character name
		if config:IsWhitelisted(senderName) or
		(hyphen and config:IsWhitelisted(senderName:sub(1, hyphen - 1))) then
			return true
		end
	end
	return false
end

local chatBubbleOptions = {}
local chatBubbleListener = CreateFrame("Frame", "DetoxChatBubbleListener", WorldFrame)
chatBubbleListener:SetFrameStrata("TOOLTIP")
chatBubbleListener:SetScript("OnUpdate", function(self, elapsed)
	self:Stop()
end)

chatBubbleOptions['enabled'] = GetCVar("chatBubbles")
chatBubbleOptions['partyEnabled'] = GetCVar("chatBubblesParty")
chatBubbleOptions['reset'] = true

function chatBubbleListener:Start()
	-- Record user-defined setting for chat bubble display so it can be reverted afterwards
	if chatBubbleOptions['reset'] then
		-- Only save the user setting if it has been reset by the Stop() function
		-- To prevent simultaneous Start() function calls from overwriting the saved setting
		chatBubbleOptions['enabled'] = GetCVar("chatBubbles")
		chatBubbleOptions['partyEnabled'] = GetCVar("chatBubblesParty")
		chatBubbleOptions['reset'] = false
	end
	
	-- Disable chat bubble for a toxic message
	SetCVar("chatBubbles", 0)
	SetCVar("chatBubblesParty", 0)
	self:Show()
end

function chatBubbleListener:Stop()
	self:Hide()
	-- Reset chat bubble display option to user-defined setting
	SetCVar("chatBubbles", chatBubbleOptions['enabled'])
	SetCVar("chatBubblesParty", chatBubbleOptions['partyEnabled'])
	chatBubbleOptions['reset'] = true
end

local deathHistory = {}

local function OnCombatEvent(self, event)
	local timestamp, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName = CombatLogGetCurrentEventInfo()
	if subevent == "UNIT_DIED" then
		local unitType = strsplit("-", destGUID)
		if unitType == "Player" then
			if UnitInParty(destName) or UnitInRaid(destName) then
				-- UnitInParty/Raid returns nil if player is not in a party
				-- i.e. this does not check if the player died when by themself
				-- We only want to trigger protect mode when in a group with other players
				-- But still check if the player who died is in party/raid for PVP situations
				local deathEvent = { ['timestamp'] = timestamp }
				
				-- Record the group members who witnessed the death
				local groupMembers = {}
				for i = 1, GetNumGroupMembers() do
					local groupMemberName = GetRaidRosterInfo(i)
					local groupMemberGUID = UnitGUID(groupMemberName)
					groupMembers[groupMemberGUID] = true
				end
				deathEvent['groupMembers'] = groupMembers
				table.insert(deathHistory, deathEvent)
			end
		end
	end
end

local combatListener = CreateFrame("Frame", "CombatListener", WorldFrame)
combatListener:SetFrameStrata("TOOLTIP")
combatListener:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
combatListener:SetScript("OnEvent", OnCombatEvent)

local function GetProtectFactor(currTime, senderGuid)
	-- Calculate the protection offered to player based on the sender of message
	-- Only protect against senders who witnessed recent deaths
	if senderGuid == nil or senderGuid == '' then return 0 end
	
	local recentDeathsCritical = 0
	local recentDeathsHigh = 0
	local mostRecentDeath = 0
	local maxGroupMembers = 1
	for _, deathEvent in ipairs(deathHistory) do
		if deathEvent.groupMembers[senderGuid] then
			local timestamp = deathEvent.timestamp
			if timestamp > mostRecentDeath then mostRecentDeath = timestamp end
			if currTime - timestamp <= detoxProtectCriticalTime then recentDeathsCritical = recentDeathsCritical + 1 end
			if currTime - timestamp <= detoxProtectHighTime then
				recentDeathsHigh = recentDeathsHigh + 1
				local numGroupMembers = util.TableLength(deathEvent.groupMembers)
				if numGroupMembers > maxGroupMembers then maxGroupMembers = numGroupMembers end
			end
		end
	end
	
	if mostRecentDeath == 0 then return 0 end
	
	local deathFractionCritical = recentDeathsCritical / maxGroupMembers
	local deathFractionHigh = recentDeathsHigh / maxGroupMembers
	local protectFactor = detoxProtectDeathFactor * math.min(recentDeathsCritical, 1) +
		detoxProtectCriticalFactor * math.tanh(deathFractionCritical) +
		detoxProtectHighFactor * math.tanh(deathFractionHigh)
	
	return protectFactor
end

function Detox:InitializeDb()
	if self.db.global.strictFilter == nil then
		self.db.global.strictFilter = false
	end
	
	local profileDefaults = config.profileDefaults()
	for k, v in pairs(profileDefaults) do
		if self.db.profile[k] == nil then
			self.db.profile[k] = v
		end
	end
end

function Detox:OnInitialize()
	self.enabled = true
	
	self.db = LibStub("AceDB-3.0"):New("DetoxDB", { profile = config.profileDefaults() }, true)
	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
	config.detoxOptions.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db, true)
	
	if self.db.global.playerDb == nil then self.db.global.playerDb = {} end
	if self.db.global.channelHist == nil then self.db.global.channelHist = history.newChannelHist() end
	local prevPlayerHistSchema = self.db.global.playerHistSchema or {}
	self.history = history:new(self.db.global.playerDb, prevPlayerHistSchema, self.db.global.channelHist)
	self.db.global.playerHistSchema = history.playerHistSchema()
	config.detoxOptions.args.statsTab = config.GetStatsTable()
	
	AceConfig:RegisterOptionsTable("Detox", config.detoxOptions)
	AceConfigDialog:AddToBlizOptions("Detox")
	
	self.classifier = classifier:new()
	self:RawHook("ChatFrame_OnHyperlinkShow", true)
	
	-- Initialize DB values
	-- This is needed even though some values are already set in the default profile
	-- Because existing profiles will not have new variables when upgrading the addon
	self:InitializeDb()
	self:RefreshConfig()
	
	if not self.db.global.introWindowShown then
		config:ShowIntroWindow()
	end
end

function Detox:OnEnable()
	self:RawHook("ChatFrame_MessageEventHandler", true)
	self.enabled = true
	Print("Message filter enabled (/detox for options)")
	
	-- Set default show message keybind to CTRL-G if it isn't in use
	if GetBindingAction("CTRL-G") == '' then
		SetBinding("CTRL-G", "DETOX_SHOW_MESSAGES")
		if isRetail then
			SaveBindings(GetCurrentBindingSet())
		else
			AttemptToSaveBindings(GetCurrentBindingSet())
		end
	end
end

function Detox:OnDisable()
	self:Unhook("ChatFrame_MessageEventHandler")
	self.enabled = false
	Print('Pausing message filtering...')
end

function Detox:RefreshConfig()
	config.whitelist = self.db.profile.whitelist or {}
	if config.whitelistFrame then
		config.whitelistFrame:update()
	end
end

function Detox:ShowHiddenChats()
	local sortedIds = {}
	for id, chat in pairs(detoxHiddenChats) do
		if not chat.shown then
			table.insert(sortedIds, id)
		end
	end
	table.sort(sortedIds)
	
	for _, id in ipairs(sortedIds) do
		local chat = detoxHiddenChats[id]
		Print(RecreateChat(chat), SELECTED_CHAT_FRAME)
		chat.shown = true
		detoxHiddenChats[id] = chat
	end
end

Detox:RegisterChatCommand("detox", "SlashProcessorFunc")
Detox:RegisterChatCommand("dtx", "SlashProcessorFunc")

function Detox:SlashProcessorFunc(input)
	if input == '' then
		AceConfigDialog:Open("Detox")
	end
	
	local command = Detox:GetArgs(input)
	
	if command == 'help' then
		Print("Options:", SELECTED_CHAT_FRAME)
		Print("/detox - bring up settings menu", SELECTED_CHAT_FRAME)
		Print("/detox show - display filtered chats", SELECTED_CHAT_FRAME)
	end
	
	if command == 'show' then
		self:ShowHiddenChats()
	end

	if command == 'wipeAllHistory' then
		self.db.global.playerDb = {}
		self.history = history:new(self.db.global.playerDb, self.db.global.playerHistSchema, self.db.global.channelHist)
	end
	
	if command == 'listAllHistory' then
		for k, v in pairs(self.db.global.playerDb) do
			self.history:PrintPlayerStats(k)
		end
	end
end

function Detox:ParseMessage(chatFrame, event, ...)
	local args = {...}
	local message = args[1]
	local sender = args[2]
	local senderGuid = args[12]
	local chatLineID = args[11]
	local outputMessage = message
	
	if self.enabled and message then
		local senderId = senderGuid
		if (senderGuid == nil or senderGuid == '' or senderGuid == 0) and sender then
			if string.sub(sender, 1, 2) == "|K" then -- BNet Kstring
				senderId = GetBnetTag(sender)
			else
				senderId = sender
			end
		end
	
		-- Check if the event was already processed, i.e. when a chat is presented by multiple chatFrames
		if detoxPrevChatLine['chatLineID'] == chatLineID then
			if detoxPrevChatLine['blocked'] then
				return nil
			else
				return self.hooks["ChatFrame_MessageEventHandler"](chatFrame, event, detoxPrevChatLine['message'], select(2, ...))
			end
		end
		
		-- Get the key of the chatTypes table for this particular event (e.g. 'say') and check if the channel filter is enabled
		local chatKey = config.chatTypesEvents[event]
		if self.db.profile[chatKey] and not IsTrustedSender(sender, senderGuid) then
			detoxPrevChatLine = { ['chatLineID'] = chatLineID, ['blocked'] = false, ['message'] = message }
			
			local currTime = time()
			local senderStatus = self.history:GetPlayerStatus(senderId, currTime)
			-- Block sender if throttle mode is on and multiple toxic messages were received
			local senderThrottled = self.db.profile.throttleMode and senderStatus == history.PLAYER_STATUS_THROTTLED
			local throttleFactor = (senderThrottled and detoxToxicThrottleFactor) or 0
			local protectFactor = GetProtectFactor(currTime, senderGuid)
			local friendFactor = self.history:GetPlayerFriendFactor(senderId)
			local thresholdPenalty = (detoxToxicStrangerFactor + throttleFactor + protectFactor) * (1 - friendFactor)
			-- strictFactor does not get scaled by friendFactor
			if self.db.global.strictFilter then thresholdPenalty = (thresholdPenalty + detoxToxicStrictFactor) * detoxToxicStrictMultiplier end
			local toxicityThreshold = detoxToxicThresholdBaseline - thresholdPenalty
			
			-- Determine if message is toxic with the calculated toxicityThreshold
			local toxic = self.classifier:Classify(message, toxicityThreshold)
			
			-- Hide chat by modifying message and turning off chat bubble
			if toxic or senderThrottled then
				detoxHiddenChats[chatLineID] = {
					message = message,
					sender = sender,
					senderGuid = senderGuid,
					timestamp = currTime,
					event = event,
					shown = false
				}
				
				-- Turn off chat bubbles before the toxic message is broadcasted
				-- After the next frame update, chatBubbleListener will reset chat bubbles to previous setting
				chatBubbleListener:Start()
				
				local hyperlink = "detox:show:" .. tostring(chatLineID)
				if senderStatus == history.PLAYER_STATUS_RISK and self.db.profile.throttleMode then
					outputMessage = string.format("%s|H%s|h%s|h", detoxSecondaryColorStr, hyperlink, detoxChatThrottledMessage)
				else
					outputMessage = string.format("%s|H%s|h%s|h", detoxSecondaryColorStr, hyperlink, detoxChatHiddenMessage)
				end
				detoxPrevChatLine['message'] = outputMessage
			end
			
			-- Update history with chat message details
			self.history:UpdateWithNewMessage(senderId, currTime, toxic, chatKey)
			
			-- Should the end user be notified of the hidden chat?
			if senderThrottled or not self.db.profile.showNotification then
				detoxPrevChatLine['blocked'] = true
				return nil
			else
				return self.hooks["ChatFrame_MessageEventHandler"](chatFrame, event, outputMessage, select(2, ...))
			end
		end
	end
	return self.hooks["ChatFrame_MessageEventHandler"](chatFrame, event, ...)
end

function Detox:ChatFrame_MessageEventHandler(this, event, ...)
	local status, result = pcall(self.ParseMessage, self, this, event, ...)
	if status then
		return result
	end
	
	-- pcall to ParseMessage errored, passthrough event without any changes
	return self.hooks["ChatFrame_MessageEventHandler"](this, event, ...)
end

function Detox:ChatFrame_OnHyperlinkShow(this, link, text, button)
	local linkTable = {}
	for str in string.gmatch(link, "[^:]+") do
		table.insert(linkTable, str)
	end

	local linkType = linkTable[1]
	if linkType ~= 'detox' then
		return self.hooks["ChatFrame_OnHyperlinkShow"](this, link, text, button)
	end

	local linkAction = linkTable[2]
	if linkAction == 'show' then
		local linkID = linkTable[3]
		if button == 'LeftButton' then
			local chat = detoxHiddenChats[tonumber(linkID)]
			Print(RecreateChat(chat), this)
			
			-- Mark chat as having been shown
			chat.shown = true
			detoxHiddenChats[tonumber(linkID)] = chat
		--elseif button == 'RightButton' then
		end
	elseif linkAction == 'options' then
		AceConfigDialog:Open("Detox")
	end
end
