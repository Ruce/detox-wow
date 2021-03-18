local _, addonTbl = ...
local classifier = {}
local dense = addonTbl.dense
local lstm = addonTbl.lstm
local lruCache = addonTbl.lru
local data = addonTbl.data

local tinsert = table.insert
local tremove = table.remove

local function known(words, dictionary, minLength)
	local knownWords = {}
	local minLength = minLength or 0
	for _, word in ipairs(words) do
		if string.len(word) > minLength and dictionary[word] then
			tinsert(knownWords, word)
		end
	end
	return knownWords
end

-- Split a word into two, returning all possible combinations
-- E.g. the -> { {"", "the"}, {"t", "he"}, {"th", "e"}, {"the", ""} }
local function split(word)
	local t = {}
	local n = string.len(word)
	for i = 1, n+1 do
		tinsert(t, {string.sub(word, 0, i-1), string.sub(word, i)})
	end
	return t
end

-- Check if both parts of split are known words, i.e. missing space between words
-- E.g. helloworld -> { "hello", "world" }
local function separates(splits, dictionary, minLength)
	local t = {}
	for _, v in ipairs(splits) do
		local left = v[1]
		local right = v[2]
		if right and right ~= "" then
			local leftKnown = known({left}, dictionary, minLength)
			local rightKnown = known({right}, dictionary, minLength)
			if #leftKnown == 1 and #rightKnown == 1 then
				tinsert(t, left)
				tinsert(t, right)
			end
		end
	end
	return t
end

-- Delete a character from the word; typo had an extra letter, e.g. helllo
-- Output: word -> { ord, wrd, wod, wor }
local function deletes(splits)
	local t = {}
	for _, v in ipairs(splits) do
		local left = v[1]
		local right = v[2]
		if right and right ~= "" then
			tinsert(t, left..string.sub(right, 2))
		end
	end
	return t	
end

-- Swap two adjacent characters, e.g. hlelo
-- Output: word -> { owrd, wrod, wodr }
local function transposes(splits)
	local t = {}
	for _, v in ipairs(splits) do
		local left = v[1]
		local right = v[2]
		if right and string.len(right) > 1 then
			tinsert(t, left..string.sub(right, 2, 2)..string.sub(right, 1, 1)..string.sub(right, 3))
		end
	end
	return t
end

-- A character replaced by another character that is nearby on a keyboard, e.g. helli
-- Output: word -> { qord, eord, wird, wprd, woed, wotd, wors, worf } on a QWERTY keyboard
-- characterMap should be a table with characters as keys, and for each key the value is a table of nearby characters
local function replaces(splits, characterMap)
	local t = {}
	for _, v in ipairs(splits) do
		local left = v[1]
		local right = v[2]
		if right and right ~= "" then
			local c = string.sub(right, 1, 1)
			for _, r in ipairs(characterMap[c]) do
				tinsert(t, left..r..string.sub(right, 2))
			end
		end
	end
	return t
end

-- Insert a character into the word; typo had a missing letter, e.g. helo
-- Output: word -> { waord, woard, worad, worda, ... }
-- validCharacters should be a table of characters for insertion
local function inserts(splits, validCharacters)
	local t = {}
	for _, v in ipairs(splits) do
		local left = v[1]
		local right = v[2]
		for _, c in pairs(validCharacters) do
			tinsert(t, left..c..right)
		end
	end
	return t
end

-- Inserts values from table2 into table1 by modifying table1 (not cloned)
-- Both tables must be integer-indexed
local function insertToTable(table1, table2)
	for _, v in ipairs(table2) do
		tinsert(table1, v)
	end
	return table1
end

-- Returns a new table with duplicates in table1 removed
local function deduplicate(table1)
	local t = {}
	local deduplicated = {}
	for i, v in ipairs(table1) do
		if not t[v] then
			t[v] = true
			tinsert(deduplicated, v)
		end
	end
	return deduplicated
end

-- Remove formatting from text such as colours and hyperlinks
local function removeFormatting(message)
	local cleanMessage = string.gsub(message, "|c%x%x%x%x%x%x%x%x(.-)|r", "%1")
	cleanMessage = string.gsub(cleanMessage, "|H.-|h(.-)|h", "%1")
	return cleanMessage
end

function classifier:SpellCheck(word)
	local dictionary = self.dictionary
	local validCharacters = self.validCharacters
	local characterMap = self.characterMap
	
	-- For short words, don't offer alternative words as there can be too many false positives
	local minLength = 2
	
	-- Inspired by http://norvig.com/spell-correct.html
	local knownWord = known({word}, dictionary, 0)
	if #knownWord == 1 then
		return {}
	elseif string.len(word) > minLength then
		local splitCharacters = split(word)
		local deletedWords = known(deletes(splitCharacters), dictionary, minLength)
		local transposedWords = known(transposes(splitCharacters), dictionary, minLength)
		local replacedWords = known(replaces(splitCharacters, characterMap), dictionary, minLength)
		local insertedWords = known(inserts(splitCharacters, validCharacters), dictionary, minLength)
		local separatedWords = separates(splitCharacters, dictionary, minLength)
		
		local possibleWords = {}
		insertToTable(possibleWords, deletedWords)
		insertToTable(possibleWords, transposedWords)
		insertToTable(possibleWords, replacedWords)
		insertToTable(possibleWords, insertedWords)
		insertToTable(possibleWords, separatedWords)
		
		return deduplicate(possibleWords)
	end
	return nil
end

function classifier:Tokenise(message)
	local tokens = {}
	local curtok = '' -- Current token
	local L = string.len(message)
	for i = 1, L do
		local c = string.sub(message, i, i)
		-- Reached a separator, save current token if it isn't blank
		if self.separators[c] then
			-- Do not combine with above if statement. In case of overlap between separator and validCharacter table, this order of operation prioritises separators.
			if curtok ~= '' then
				tinsert(tokens, curtok)
				curtok = ''
			end
		-- Not a separator character, append to token if it is a valid character
		elseif self.validCharacters[c] then
			curtok = curtok..c
		end
	end
	if curtok ~= '' then
		tinsert(tokens, curtok)
	end
	return tokens
end

function classifier:ProcessTokens(tokens)
	-- Run spellCheck against tokens to see if it is a known word, and if not get suggested alternative words
	-- Calculate the maximum number of alternative words to try predicting, based on the self.maxPasses limit
	-- Returns a list of tables with keys `token`, `knownWords`, and `alternativeWords`
	local processedTokens = {}
	if #tokens == 0 then return {} end
	
	local numAlternativeWords = 0
	local bins = 0
	for _, token in ipairs(tokens) do
		local knownWords = self:SpellCheck(token)
		if knownWords and #knownWords > 0 then
			numAlternativeWords = numAlternativeWords + #knownWords
			bins = bins + 1
		end
		local t = { ['token'] = token, ['knownWords'] = knownWords, ['alternativeWords'] = {} }
		tinsert(processedTokens, t)
	end
	
	local maxAlternatives = math.floor(self.maxPasses / #tokens) - 1
	if numAlternativeWords <= maxAlternatives then
		for _, pToken in ipairs(processedTokens) do
			pToken['alternativeWords'] = pToken['knownWords']
		end
	else
		-- Recursively allocate "budget" of maxAlternatives evenly between the tokens
		local remainder = maxAlternatives
		local depth = 0
		while remainder > 0 and bins > 0 do
			local k = math.floor(remainder / bins)
			if k <= 0 then -- Cannot evenly divide up rest of the remainder
				local counter = 0
				for _, pToken in ipairs(processedTokens) do
					if pToken['knownWords'][depth + 1] then
						tinsert(pToken['alternativeWords'], pToken['knownWords'][depth + 1])
						remainder = remainder - 1
						if remainder <= 0 then break end
					end
				end
				remainder = 0
			else
				for _, pToken in ipairs(processedTokens) do
					if #pToken['knownWords'] > depth then
						for i = depth + 1, depth + k do
							if pToken['knownWords'][i] then
								tinsert(pToken['alternativeWords'], pToken['knownWords'][i])
								remainder = remainder - 1
							end
						end
						if #pToken['alternativeWords'] == #pToken['knownWords'] then bins = bins - 1 end
					end
				end
				depth = depth + k
			end
		end
	end
	
	return processedTokens
end

function classifier:Classify(message)
	local embeddings = self.embeddings
	local unk = self.unk
	local blank = self.blank
	
	local cleanMessage = removeFormatting(message)
	cleanMessage = string.lower(cleanMessage)
	
	local tokens = self:Tokenise(cleanMessage)
	if #tokens == 0 then return false end
	local tokensStr = table.concat(tokens, " ")
	
	-- Check if message result is in cache
	local cachedResult = self.classifyCache:get(tokensStr)
	if cachedResult then
		return cachedResult >= self.toxicThreshold
	end
	
	-- Limit number of forward passes on LSTM layer to reduce processing time
	-- Future update: Provide option to user for "enhanced mode" for more powerful computers
	local processedTokens = self:ProcessTokens(tokens)
	
	-- Keep track of word embeddings for original tokens as well as alternative tokens suggested by SpellCheck
	-- Only allow up to one misspelt word in order to minimise number of possible combinations
	-- E.g. "wordA wordB wordC wordD" vs "wordA alternativeB1 wordC wordD" vs "wordA alternativeB2 wordC wordD" vs "wordA wordB alternativeC1 wordD"
	local originalTokensEmbeddings = {}
	local alternativeTokensEmbeddings = {}
	
	for _, pToken in ipairs(processedTokens) do
		local token = pToken.token
		local tokenEmbedding = embeddings[token] or unk
		for _, line in ipairs(alternativeTokensEmbeddings) do
			tinsert(line, tokenEmbedding)
		end
		
		-- Multiple suggestions from SpellCheck may be UNK (i.e. OOV) and not have a word embedding
		-- Therefore only add UNK once to the list of possible alternative sentences
		for _, word in ipairs(pToken.alternativeWords) do		
			local wordEmbedding = embeddings[word] or unk
			-- Since the original token is not a known word, it is OOV and therefore will be added as UNK to the list
			-- As such there is no need for alternative tokens that are also UNK to be added to the list
			if wordEmbedding ~= unk then
				-- (Shallow) copy the originalTokensEmbeddings table and insert into alternativeTokensEmbeddings
				origCopy = {unpack(originalTokensEmbeddings)}
				tinsert(origCopy, wordEmbedding)
				tinsert(alternativeTokensEmbeddings, origCopy)
			end
		end
		
		tinsert(originalTokensEmbeddings, tokenEmbedding)
	end
	
	if not self.lstmLayer then self.lstmLayer = lstm:new(data.Weights.LSTM.Kernel, data.Weights.LSTM.Recurrent, data.Weights.LSTM.Bias) end
	if not self.denseLayer then self.denseLayer = dense:new(data.Weights.Output.Kernel, data.Weights.Output.Bias) end
	
	local maxScore = 0
	tinsert(alternativeTokensEmbeddings, originalTokensEmbeddings)
	for _, phrase in ipairs(alternativeTokensEmbeddings) do
		local lstmOutput = self.lstmLayer:Predict(phrase, true)
		local score = self.denseLayer:Predict(lstmOutput)[1][1]
		if score > maxScore then maxScore = score end		
		if score >= self.toxicThreshold then
			self.classifyCache:set(tokensStr, maxScore)
			return true
		end
	end
	
	self.classifyCache:set(tokensStr, maxScore)
	return false
end

function classifier:new()
	newClassifier = {}
	setmetatable(newClassifier, self)
	self.__index = self
	
	classifier.dictionary = data.Dictionary
	classifier.validCharacters = data.EnglishCharacters
	classifier.characterMap = data.QwertyMap
	classifier.separators = data.Separators
	classifier.embeddings = data.Embeddings
	classifier.unk = data.Unk
	classifier.blank = data.BlankEmbedding
	classifier.toxicThreshold = 0.99
	classifier.maxPasses = 512
	classifier.classifyCache = lruCache.new(5)
	
	return newClassifier
end

addonTbl.classifier = classifier