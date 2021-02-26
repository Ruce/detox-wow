local _, addonTbl = ...

local AceGUI = LibStub("AceGUI-3.0")
local config = {}

config.chatTypes = {
	["say"] = {
		name = "Say",
		default = true,
		events = { "CHAT_MSG_SAY" } },
	["yell"] = {
		name = "Yell",
		default = true,
		events = { "CHAT_MSG_YELL" } },
	["guild"] = {
		name = "Guild",
		default = false,
		events = { "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER" } },
	["whisper"] = {
		name = "Whisper",
		default = true,
		events = { "CHAT_MSG_WHISPER" } },
	["bnet"] = {
		name = "Battle.net",
		default = false,
		events = { "CHAT_MSG_BN_WHISPER" } },
	["party"] = {
		name = "Party",
		default = true,
		events = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" } },
	["raid"] = {
		name = "Raid",
		default = true,
		events = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" } }, -- Does not include CHAT_MSG_RAID_WARNING
	["instance"] = {
		name = "Instance",
		default = true,
		events = { "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" } },
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
					name = "Display Options",
					type = "group",
					order = 1,
					inline = true,
					args = {
						showNotification = {
							name = "Show Notifications",
							desc = "If disabled, you will not be notified of hidden toxic messages. Use at your own risk!",
							type = "toggle",
							set = function(info, val) Detox.db.profile.showNotification = val end,
							get = function(info) return Detox.db.profile.showNotification end
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
							name = "\nAdd specific players to whitelist (must include realm name, e.g. PlayerName-Realm)",
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
		if name == player.name then
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
	whitelistEditbox:SetLabel("Whitelist (PlayerName-Realm):")
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

addonTbl.config = config