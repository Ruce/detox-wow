local _, addonTbl = ...

BINDING_HEADER_DETOX = "Detox"
BINDING_NAME_DETOX_SHOW_MESSAGES = "Show Detox Messages"

local AceGUI = LibStub("AceGUI-3.0")
local config = {}

config.chatTypes = {
	["say"] = {
		name = "Say",
		default = true,
		order = 70,
		events = { "CHAT_MSG_SAY" } },
	["yell"] = {
		name = "Yell",
		default = true,
		order = 90,
		events = { "CHAT_MSG_YELL" } },
	["guild"] = {
		name = "Guild",
		default = false,
		order = 30,
		events = { "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER" } },
	["whisper"] = {
		name = "Whisper",
		default = true,
		order = 80,
		events = { "CHAT_MSG_WHISPER" } },
	["bnet"] = {
		name = "Battle.net",
		default = false,
		order = 10,
		events = { "CHAT_MSG_BN_WHISPER" } },
	["party"] = {
		name = "Party",
		default = true,
		order = 50,
		events = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" } },
	["raid"] = {
		name = "Raid",
		default = true,
		order = 60,
		events = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" } }, -- Does not include CHAT_MSG_RAID_WARNING
	["instance"] = {
		name = "Instance",
		default = true,
		order = 40,
		events = { "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" } },
	["emote"] = {
		name = "Emote",
		default = true,
		order = 20,
		events = { "CHAT_MSG_EMOTE" } }
}

-- "Inverted" table where events are the keys, and keys from chatTypes table are values
-- For convenience and performance in looking up events
config.chatTypesEvents = {}
for k,v in pairs(config.chatTypes) do
	for _, event in ipairs(v.events) do
		config.chatTypesEvents[event] = k
	end
end

config.chatTypesOptions = function()
	local t = {}
	for k,v in pairs(config.chatTypes) do
		t[k] = v.name
	end
	return t
end

config.profileDefaults = function()
	local t = {}
	-- Default chat types to filter
	for k,v in pairs(config.chatTypes) do
		t[k] = v.default
	end
	t["showNotification"] = true
	t["throttleMode"] = true
	t["whitelist"] = {}
	t["whitelistFriends"] = true
	t["whitelistGuild"] = true
	t["whitelistBnet"] = true
	return t
end

config.detoxOptions = {
	type = "group",
	childGroups = "tab",
	args = {
		generalGroup = {
			name = "General",
			type = "group",
			args = {
				displayOptions = {
					name = "Main Options",
					type = "group",
					order = 1,
					inline = true,
					args = {
						showNotification = {
							name = "Show Notifications",
							desc = "If disabled, you will not be notified of hidden toxic messages. Use at your own risk!",
							type = "toggle",
							order = 10,
							set = function(info, val) Detox.db.profile.showNotification = val end,
							get = function(info) return Detox.db.profile.showNotification end
						},
						throttleMode = {
							name = "Throttle Mode",
							desc = "Temporarily block sender after multiple toxic messages",
							type = "toggle",
							order = 20,
							set = function(info, val) Detox.db.profile.throttleMode = val end,
							get = function(info) return Detox.db.profile.throttleMode end
						},
						strictFilter = {
							name = "Strict Filter",
							desc = "A strict filter blocks more messages",
							type = "toggle",
							order = 30,
							set = function(info, val) Detox.db.global.strictFilter = val end,
							get = function(info) return Detox.db.global.strictFilter end
						}
					}
				},
				chatTypesUser = {
					name = "Chat Channels",
					desc = "Filter messages on this channel",
					type = "multiselect",
					order = 10,
					values = config.chatTypesOptions(),
					set = function(info, key, val) Detox.db.profile[key] = val end,
					get = function(info, key) return Detox.db.profile[key] end
				},
				whitelistOptions = {
					name = "Whitelist Players",
					type = "group",
					inline = true,
					args = {
						whitelistDescription = {
							name = "Messages from whitelisted players will never be filtered",
							type = "description",
							order = 0
						},
						whitelistFriends = {
							name = "Friends",
							desc = "Whitelist all friends",
							type = "toggle",
							order = 10,
							set = function(info, val) Detox.db.profile.whitelistFriends = val end,
							get = function(info) return Detox.db.profile.whitelistFriends end
						},
						whitelistBnet = {
							name = "Battle.net Friends",
							desc = "Whitelist all BattleTag friends",
							type = "toggle",
							order = 15,
							set = function(info, val) Detox.db.profile.whitelistBnet = val end,
							get = function(info) return Detox.db.profile.whitelistBnet end
						},
						whitelistGuild = {
							name = "Guild Members",
							desc = "Whitelist all guild members",
							type = "toggle",
							order = 20,
							set = function(info, val) Detox.db.profile.whitelistGuild = val end,
							get = function(info) return Detox.db.profile.whitelistGuild end
						},
						whitelistPlayersDescription = {
							name = "\nAdd specific players to whitelist",
							type = "description",
							order = 50
						},
						whitelistPlayers = {
							name = "Open Whitelist",
							desc = "Whitelist named players",
							type = "execute",
							order = 60,
							func = function() config:ShowWhitelistFrame() end
						}
					}
				}
			}
		},
		enable = {
			name = "Enable Detox",
			desc = "Enable/disable message filtering",
			type = "toggle",
			order = -1,
			set = function(info, val) if val then Detox:OnEnable() else Detox:OnDisable() end end,
			get = function(info) return Detox.enabled end
		}
	}
}

function config.GetStatsTable()
	local statsTab = {
		name = "Stats",
		type = "group",
		args = {
			overallHeader = {
				name = "Overall",
				type = "header",
				order = 0
			},
			blockedMessages = {
				name = function() return "Total toxic messages blocked: "..NORMAL_FONT_COLOR_CODE..tostring(Detox.history:GetToxicMessageCount())..FONT_COLOR_CODE_CLOSE end,
				type = "description",
				fontSize = "medium",
				order = 10
			},
			uniquePlayers = {
				name = function() return "Unique senders of toxic messages: "..NORMAL_FONT_COLOR_CODE..tostring(Detox.history:GetUniqueSendersBlocked())..FONT_COLOR_CODE_CLOSE end,
				type = "description",
				fontSize = "medium",
				order = 20
			},
			lineBreak = {
				name = " ",
				type = "description",
				order = 25
			},
			channelHeader = {
				name = "Messages Blocked Per Channel",
				type = "header",
				order = 30
			}
		}
	}
	
	local baseChannelOrder = 40
	for channel, channelDetails in pairs(config.chatTypes) do
		statsTab.args[channel] = {
				name = function() return channelDetails.name..": "..NORMAL_FONT_COLOR_CODE..tostring(Detox.history:GetChannelStat(channel))..FONT_COLOR_CODE_CLOSE end,
				type = "description",
				fontSize = "medium",
				order = baseChannelOrder + channelDetails.order
			}
	end
	
	return statsTab
end

function config:AddToWhitelist(name)
	table.insert(self.whitelist, { name = name })
	if self.whitelistFrame then
		self.whitelistFrame:update()
	end
end

function config:RemoveFromWhitelist(index)
	table.remove(self.whitelist, index)
	if self.whitelistFrame then
		self.whitelistFrame:update()
	end
end

function config:IsWhitelisted(name)
	for _, player in ipairs(self.whitelist) do
		if string.lower(name) == string.lower(player.name) then
			return true
		end
	end
	return false
end

config.WhitelistWindowOpened = false
function config:ShowWhitelistFrame()
	if config.WhitelistWindowOpened then
		return nil
	end

	local frame = AceGUI:Create("Frame")
	frame:SetTitle("Detox Whitelist")
	frame:SetWidth(400)
	frame:SetHeight(600)
	frame:SetCallback("OnClose", function(widget) config:ReleaseWhitelistFrame(); AceGUI:Release(widget); config.WhitelistWindowOpened = false end)
	frame:SetLayout("Flow")
	
	local whitelistEditbox = AceGUI:Create("EditBox")
	whitelistEditbox:SetLabel("Whitelist (CharacterName):")
	whitelistEditbox:SetRelativeWidth(0.78)
	whitelistEditbox:SetCallback("OnEnterPressed", function(widget, event, text) self:AddToWhitelist(text); widget:SetText("") end)
	frame:AddChild(whitelistEditbox)
	
	local whitelistAddButton = AceGUI:Create("Button")
	whitelistAddButton:SetText("Add")
	whitelistAddButton:SetRelativeWidth(0.2)
	whitelistAddButton:SetCallback("OnClick", function() self:AddToWhitelist(whitelistEditbox:GetText()); whitelistEditbox:SetText("") end)
	frame:AddChild(whitelistAddButton)
	
	local listFrame = AceGUI:Create("InlineGroup")
	listFrame:SetFullHeight(true)
	listFrame:SetFullWidth(true)
	frame:AddChild(listFrame)
	
	local wlframe = self:CreateWhitelistFrame(listFrame.content)
	self.WhitelistWindowOpened = true
end

-- Singleton whitelist frame
config.whitelistFrame = nil
function config:CreateWhitelistFrame(parentFrame)
	if self.whitelistFrame then
		self.whitelistFrame:SetParent(nil)
		self.whitelistFrame:SetParent(parentFrame)
		self.whitelistFrame:SetSize(parentFrame:GetWidth(), parentFrame:GetHeight())
	else		
		self.whitelistFrame = CreateFrame("ScrollFrame", nil, parentFrame, "DetoxWhitelistScrollTemplate")
		self.whitelistFrame.scrollBar.doNotHide = true
		self.whitelistFrame:SetSize(parentFrame:GetWidth(), parentFrame:GetHeight())
		
		self.whitelistFrame.update = function (scrollFrame)
			local buttons = HybridScrollFrame_GetButtons(scrollFrame)
			local offset = HybridScrollFrame_GetOffset(scrollFrame)
			
			for buttonIndex = 1, #buttons do
				local button = buttons[buttonIndex]
				local playerIndex = buttonIndex + offset
				
				if playerIndex <= #self.whitelist then
					local player = self.whitelist[playerIndex]
					button:SetID(playerIndex)
					button.Text:SetText(player.name or "")
					button:SetWidth(scrollFrame.scrollChild:GetWidth())
					button.DeleteButton:SetScript("OnClick", function()
						self:RemoveFromWhitelist(playerIndex)
					end)
					button:Show()
				else
					button:Hide()
				end
			end
			
			local totalHeight = #self.whitelist * scrollFrame.buttonHeight
			local shownHeight = scrollFrame:GetHeight()
			HybridScrollFrame_Update(scrollFrame, totalHeight, shownHeight)
		end
		
		HybridScrollFrame_CreateButtons(self.whitelistFrame, "DetoxWhitelistButtonTemplate")
	end
	self.whitelistFrame:ClearAllPoints()
	self.whitelistFrame:SetPoint("TOPLEFT", 0, 0)
	self.whitelistFrame:SetPoint("BOTTOMRIGHT", -20, 3)
	self.whitelistFrame:Show()
	self.whitelistFrame:update()
	return self.whitelistFrame
end

-- As WoW frames cannot be deleted, AceGUI widgets are recycled into a pool and reused
-- config.whitelistFrame needs to be manually detached and hidden so it does not appear in another AceGUI widget
function config:ReleaseWhitelistFrame()
	if self.whitelistFrame then
		self.whitelistFrame:SetParent(nil)
		self.whitelistFrame:Hide()
	end
end

local function OnClickFilterPreference(button)
	Detox.db.global.introWindowShown = true
	Detox.db.global.strictFilter = button.strict
	button.window:Hide()
end

function config:ShowIntroWindow()
	local window = AceGUI:Create("Window")
	window:SetWidth(340)
	window:SetHeight(188)
	window:EnableResize(false)
	window:SetTitle("Detox")
	window:SetLayout("Flow")
	window:SetPoint("CENTER",UIParent,"CENTER",0,-200)
	
	local topHeading = AceGUI:Create("Heading")
	topHeading:SetRelativeWidth(1)
	window:AddChild(topHeading)
	
	local introductionLabel = AceGUI:Create("Label")
	introductionLabel:SetRelativeWidth(1)
	introductionLabel:SetFontObject(GameFontHighlight)
	introductionLabel:SetJustifyH("CENTER")
	introductionLabel:SetText("Welcome to Detox, your shield against toxic chat.")
	window:AddChild(introductionLabel)
	
	local chooseLabel = AceGUI:Create("Label")
	chooseLabel:SetRelativeWidth(.99)
	chooseLabel:SetFontObject(GameFontHighlight)
	chooseLabel:SetJustifyH("CENTER")
	chooseLabel:SetText("Choose your preferred level of toxicity filtering - a strict filter blocks more messages:")
	window:AddChild(chooseLabel)
	
	local lenientButton = AceGUI:Create("Button")
	lenientButton:SetText("Lenient Filter")
	lenientButton:SetRelativeWidth(0.5)
	lenientButton.strict = false
	lenientButton.window = window
	lenientButton:SetCallback("OnClick", function(button) OnClickFilterPreference(button) end)
	window:AddChild(lenientButton)
	
	local strictButton = AceGUI:Create("Button")
	strictButton:SetText("Strict Filter")
	strictButton:SetRelativeWidth(0.5)
	strictButton.strict = true
	strictButton.window = window
	strictButton:SetCallback("OnClick", function(button) OnClickFilterPreference(button) end)
	window:AddChild(strictButton)
	
	local bottomHeading = AceGUI:Create("Heading")
	bottomHeading:SetRelativeWidth(1)
	window:AddChild(bottomHeading)
	
	local bottomLabel = AceGUI:Create("Label")
	bottomLabel:SetJustifyH("CENTER")
	bottomLabel:SetText("This setting can be changed in the options menu (/detox)")
	bottomLabel:SetRelativeWidth(1)
	window:AddChild(bottomLabel)
end

addonTbl.config = config