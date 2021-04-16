local _, addonTbl = ...
local history = {}
local config = addonTbl.config
local tinsert = table.insert

local FRIEND_MINIMUM_CONTACT_DAYS = 3
local FRIEND_CONTACT_DAYS_SCALING = 12
local FRIEND_RECENT_DAYS = 60
local FRIEND_MINIMUM_WHISPERS = 20
local FRIEND_WHISPERS_SCALING = 100

local THROTTLE_THRESHOLD_SECONDS = 15
local THROTTLE_COOLDOWN_SECONDS = 30

local playerHistDefaults = {
	['firstContact'] = nil,
	['lastContact'] = nil,
	['contactDays'] = {},
	['totalMessages'] = 0,
	['toxicMessages'] = 0,
	['whisperMessages'] = 0,
	['prevMessageTime'] = 0,
	['prevToxicMessageTime'] = 0,
	['blockedTill'] = 0
}

history.PLAYER_STATUS_CLEAN = 1
history.PLAYER_STATUS_RISK = 2
history.PLAYER_STATUS_THROTTLED = 3

local function initializePlayerHist(playerHist)
	-- Initialize default values for playerHist properties
	-- Can be used to populate new properties onto existing playerHist, when new features are added
	for k, v in pairs(playerHistDefaults) do
		if playerHist[k] == nil then
			if type(v) == 'table' then
				playerHist[k] = {unpack(v)}
			else
				playerHist[k] = v
			end
		end
	end
end

local function newPlayerHist()
	local playerHist = {}
	initializePlayerHist(playerHist)
	return playerHist
end

local function updatePlayerHistSchema(prevSchema, playerDb)
	local needsUpdate = false
	for prop, _ in pairs(playerHistDefaults) do
		if prevSchema[prop] == nil then
			needsUpdate = true
			break
		end
	end
	
	if needsUpdate then
		for player, hist in pairs(playerDb) do
			initializePlayerHist(hist)
		end
	end
end

local function recentContactDays(contactDays, recent)
	-- `contactDays` from playerHist is an integer-indexed table with timestamps as values
	-- `recent` is the number of days that is considered recent
	local days = 0
	local currTime = time()
	for _, v in ipairs(contactDays) do
		if currTime - v < recent * 86400 then days = days + 1 end
	end
	return days
end

function history.newChannelHist()
	local channelHist = {}
	for channel, _ in pairs(config.chatTypes) do
		channelHist[channel] = { ['totalMessages'] = 0, ['toxicMessages'] = 0 }
	end
	return channelHist
end

function history.playerHistSchema()
	local schema = {}
	for prop, _ in pairs(playerHistDefaults) do
		schema[prop] = true
	end
	return schema
end

function history:GetPlayerHist(playerId)
	if self.playerDb[playerId] == nil then
		-- Create new playerHist
		self.playerDb[playerId] = newPlayerHist()
	end
	return self.playerDb[playerId]
end

function history:GetPlayerStatus(playerId, currTime)
	local playerHist = self:GetPlayerHist(playerId)
	if playerHist.blockedTill >= currTime then
		return history.PLAYER_STATUS_THROTTLED
	elseif currTime - playerHist.prevToxicMessageTime < THROTTLE_THRESHOLD_SECONDS then
		return history.PLAYER_STATUS_RISK
	else
		return history.PLAYER_STATUS_CLEAN
	end
end

function history:GetPlayerFriendFactor(playerId)
	-- Friend factor: number between 0 and 1 where 0 is never interacted with, and 1 is very friendly
	local playerHist = self:GetPlayerHist(playerId)
	
	local contactDays = recentContactDays(playerHist.contactDays, FRIEND_RECENT_DAYS)
	local daysFactor = math.max(contactDays - FRIEND_MINIMUM_CONTACT_DAYS, 0) / FRIEND_CONTACT_DAYS_SCALING
	local messagesFactor = math.max(playerHist.whisperMessages - FRIEND_MINIMUM_WHISPERS, 0) / FRIEND_WHISPERS_SCALING
	local friendFactor = math.tanh(math.max(daysFactor, messagesFactor))
	return friendFactor
end

function history:GetToxicMessageCount()
	local total = 0
	for _, playerHist in pairs(self.playerDb) do
		total = total + playerHist.toxicMessages
	end
	return total
end

function history:GetUniqueSendersBlocked()
	local total = 0
	for _, playerHist in pairs(self.playerDb) do
		if playerHist.toxicMessages > 0 then total = total + 1 end
	end
	return total
end

function history:GetChannelStat(channel)
	return self.channelHist[channel].toxicMessages
end

function history:UpdateWithNewMessage(playerId, messageTime, toxic, channel)
	local playerHist = self:GetPlayerHist(playerId)
	
	if playerHist.lastContact then
		local prevContactDate = date("%x", playerHist.lastContact)
		if prevContactDate ~= date("%x", messageTime) then
			tinsert(playerHist.contactDays, messageTime)
		end
	else
		tinsert(playerHist.contactDays, messageTime)
	end
	
	if playerHist.firstContact == nil then playerHist.firstContact = messageTime end
	playerHist.lastContact = messageTime
	playerHist.prevMessageTime = messageTime
	playerHist.totalMessages = playerHist.totalMessages + 1
	self.channelHist[channel].totalMessages = self.channelHist[channel].totalMessages + 1
	if channel == 'whisper' or channel == 'bnet' then playerHist.whisperMessages = playerHist.whisperMessages + 1 end
	
	if toxic then
		local playerStatus = self:GetPlayerStatus(playerId, messageTime)
		if playerStatus == history.PLAYER_STATUS_RISK or playerStatus == history.PLAYER_STATUS_THROTTLED then
			playerHist.blockedTill = messageTime + THROTTLE_COOLDOWN_SECONDS
		end
		
		playerHist.prevToxicMessageTime = messageTime
		playerHist.toxicMessages = playerHist.toxicMessages + 1
		self.channelHist[channel].toxicMessages = self.channelHist[channel].toxicMessages + 1
	end
end

function history:PrintPlayerStats(playerId)
	local playerHist = self.playerDb[playerId]
	if playerHist then
		print('['..tostring(playerId)..'] Last contact: '..tostring(playerHist.lastContact)..'; Contact days: '..tostring(#playerHist.contactDays)..'; Total messages: '..tostring(playerHist.totalMessages)..'; Toxic messages: '..tostring(playerHist.toxicMessages)..'; Whispers: '..tostring(playerHist.whisperMessages))
	else
		print('Player not found')
	end
end

function history:ResetPlayerStats(playerId)
	self.playerDb[playerId] = newPlayerHist()
end

function history:new(playerDb, prevPlayerHistSchema, channelHist)
	local newHistory = {}
	setmetatable(newHistory, self)
	self.__index = self
	
	updatePlayerHistSchema(prevPlayerHistSchema, playerDb)
	newHistory.playerDb = playerDb
	newHistory.channelHist = channelHist
	
	return newHistory
end

addonTbl.history = history