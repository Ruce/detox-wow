local _, addonTbl = ...

Detox = LibStub("AceAddon-3.0"):NewAddon("Detox", "AceConsole-3.0", "AceHook-3.0")

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceGUI = LibStub("AceGUI-3.0")

local config = addonTbl.config

local detoxPrimaryColorStr = "|cff6DF551"
local detoxSecondaryColorStr = "|cFF5BCFBB"
local detoxChatHiddenMessage = "(Detox) Toxic message hidden - click to show"
local detoxHiddenChats = {}

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

local function IsTrustedSender(senderName, senderGuid)
	-- Check if message sender is the player (self) or whitelisted
	if senderGuid then
		if IsPlayerGuid(senderGuid) or 
		(Detox.db.profile.whitelistFriends and C_FriendList.IsFriend(senderGuid)) or
		(Detox.db.profile.whitelistGuild and IsGuildMember(senderGuid)) or
		(Detox.db.profile.whitelistBnet and C_BattleNet.GetAccountInfoByGUID(senderGuid)['isFriend']) then
			return true
		end
	end
	
	if senderName then
		if config:IsWhitelisted(senderName) then
			return true
		end
	end
	return false
end

local chatBubbleEnabled = C_CVar.GetCVar("chatBubbles")
local chatBubblePartyEnabled = C_CVar.GetCVar("chatBubblesParty")
local chatBubbleOptionReset = true

local chatBubbleListener = CreateFrame("Frame", "DetoxChatBubbleListener", WorldFrame)
chatBubbleListener:SetFrameStrata("TOOLTIP")

function chatBubbleListener:Start()
	-- Record user-defined setting for chat bubble display so it can be reverted afterwards
	if chatBubbleOptionReset then
		-- Only save the user setting if it has been reset by the Stop() function
		-- To prevent simultaneous Start() function calls from overwriting the saved setting
		chatBubbleEnabled = C_CVar.GetCVar("chatBubbles")
		chatBubblePartyEnabled = C_CVar.GetCVar("chatBubblesParty")
		chatBubbleOptionReset = false
	end
	
	-- Disable chat bubble for a toxic message
	C_CVar.SetCVar("chatBubbles", 0)
	C_CVar.SetCVar("chatBubblesParty", 0)
	self:Show()
end

function chatBubbleListener:Stop()
	self:Hide()
	-- Reset chat bubble display option to user-defined setting
	C_CVar.SetCVar("chatBubbles", chatBubbleEnabled)
	C_CVar.SetCVar("chatBubblesParty", chatBubblePartyEnabled)
	chatBubbleOptionReset = true
end

chatBubbleListener:SetScript("OnUpdate", function(self, elapsed)
	self:Stop()
end)

function Detox:OnInitialize()
	self.enabled = true
	
	self.db = LibStub("AceDB-3.0"):New("DetoxDB", { profile = config.profileDefaults() })
	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
	config.detoxOptions.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db, true)
	
	AceConfig:RegisterOptionsTable("Detox", config.detoxOptions)
	AceConfigDialog:AddToBlizOptions("Detox")
	
	self:RawHook("ChatFrame_OnHyperlinkShow", true)
	
	if self.db.global.blockedCount == nil then
		self.db.global.blockedCount = 0
	end
	
	self:RefreshConfig()
end

function Detox:OnEnable()
	self:RawHook("ChatFrame_MessageEventHandler", true)
	self.enabled = true
	Print("Message filter enabled (/detox for options)")
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
		for k, chat in pairs(detoxHiddenChats) do
			if not chat.shown then
				Print(RecreateChat(chat), SELECTED_CHAT_FRAME)
				chat.shown = true
				detoxHiddenChats[k] = chat
			end
		end
	end
end

function Detox:ChatFrame_MessageEventHandler(this, event, ...)
	local args = {...}
	local message = args[1]
	local sender = args[2]
	local senderGuid = args[12]
	local chatLineID = args[11]
	
	if Detox.enabled then
		-- Get the key of the chatTypes table for this particular event (e.g. 'say') and check if the channel filter is enabled
		local chatKey = config.chatTypesEvents[event]
		if self.db.profile[chatKey] and not IsTrustedSender(sender, senderGuid) then
			if message and self:Classify(message) then
				self.db.global.blockedCount = self.db.global.blockedCount + 1
				detoxHiddenChats[chatLineID] = {
					message = message,
					sender = sender,
					senderGuid = senderGuid,
					timestamp = time(),
					event = event,
					shown = false
				}
				
				-- Turn off chat bubbles before the toxic message is broadcasted
				-- After the next frame update, chatBubbleListener will reset chat bubbles to previous setting
				chatBubbleListener:Start()
				
				-- Notify of a toxic message (if enabled by user)
				if self.db.profile.showNotification then
					local hyperlink = "detox:show:" .. tostring(chatLineID)
					local modifiedMessage = string.format("%s|H%s|h%s|h", detoxSecondaryColorStr, hyperlink, detoxChatHiddenMessage)
					return self.hooks["ChatFrame_MessageEventHandler"](this, event, modifiedMessage, select(2, ...))
				else
					return nil
				end
			end
		end
	end
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
