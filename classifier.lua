local _, addonTbl = ...
local classifier = {}
local dense = addonTbl.dense
local lstm = addonTbl.lstm
local lruCache = addonTbl.lru
local data = addonTbl.data

local tinsert = table.insert
local tremove = table.remove

-- Count the number of values in a table; the # function only (sort of) works for integer-indexed tables
local function tableLength(table1)
	local counter = 0
	for _,_ in pairs(table1) do
		counter = counter + 1
	end
	return counter
end

local function shallowCopy(table1)
	local t = {}
	for k,v in pairs(table1) do
		t[k] = v
	end
	return t
end

local function known(words, dictionary, minLength)
	local knownWords = {}
	local minLength = minLength or 0
	for _, word in ipairs(words) do
		if string.len(word) >= minLength then
			local wordIndex = dictionary[word]
			if wordIndex then
				local suggestion = { ['word'] = word, ['index'] = wordIndex }
				tinsert(knownWords, suggestion)
			end
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
-- Returns list of word pairs: {  { ['word'] = {'par', 'ents'}, ['index'] = {20, 80} }, { ['word'] = {'pare', 'nts'}, ['index'] = {35, 99} }  }
local function separates(splits, dictionary, minLength)
	local t = {}
	for _, v in ipairs(splits) do
		local left = v[1]
		local right = v[2]
		if right and right ~= "" then
			local leftKnown = known({left}, dictionary, minLength)
			local rightKnown = known({right}, dictionary, minLength)
			if #leftKnown == 1 and #rightKnown == 1 then
				local suggestion = {
					['word'] = { leftKnown[1].word, rightKnown[1].word},
					['index'] = { leftKnown[1].index, rightKnown[1].index}
				}
				tinsert(t, suggestion)
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
local function deduplicateWords(table1)
	local t = {}
	local deduplicated = {}
	for i, v in ipairs(table1) do
		if not t[v.word] then
			t[v.word] = true
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
	-- Check if the word is in the dictionary, if not suggest alternative words
	-- Inspired by http://norvig.com/spell-correct.html
	-- Returns e.g. { {['word']='hello', ['index']=25}, {['word']='jello', ['index']=75} }
	-- Where index is the rank of the word's frequency/commonness; 0 = does not have embedding (UNK/OOV)
	local dictionary = self.dictionary
	local validCharacters = self.validCharacters
	local characterMap = self.characterMap
	
	-- For short words, don't offer alternative words as there can be too many false positives
	local minLength = 3
	
	local knownWord = known({word}, dictionary, 0)
	if #knownWord == 1 then
		return {}
	elseif string.len(word) >= minLength then
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
		possibleWords = deduplicateWords(possibleWords)
		insertToTable(possibleWords, separatedWords)
		
		return possibleWords
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

function classifier:GetEmbeddings(tokens)
	-- Store word embeddings for original tokens as well as alternative tokens suggested by SpellCheck
	-- E.g. "wordA wordB wordC wordD" vs "wordA alternativeB1 wordC wordD" vs "wordA alternativeB2 wordC wordD" vs "wordA wordB alternativeC1 wordD"
	local embeddings = self.embeddings
	local unk = self.unk
	local blank = self.blank
	
	local originalTokensEmbeddings = { ['rank'] = 0 }
	local alternativeTokensEmbeddings = {}
	for _, token in ipairs(tokens) do
		local tokenEmbedding = embeddings[token] or unk
		for _, line in ipairs(alternativeTokensEmbeddings) do
			tinsert(line, tokenEmbedding)
		end
		
		-- Run spellCheck against tokens to see if it is a known word, and if not get suggested alternative words
		local knownWords = self:SpellCheck(token)
		if knownWords then
			for _, suggestion in ipairs(knownWords) do
				local word = suggestion.word
				local index = suggestion.index
				local origCopy = shallowCopy(originalTokensEmbeddings)
				if type(word) == "table" then
					-- Handle word pairs
					for i, splitWord in ipairs(word) do
						local wordEmbedding = embeddings[splitWord] or unk
						origCopy.rank = origCopy.rank + index[i]
						tinsert(origCopy, wordEmbedding)
					end
					tinsert(alternativeTokensEmbeddings, origCopy)
				else
					-- Index represents how common the word is; 0 = does not have embedding (UNK/OOV)
					-- If the alternative word is OOV, it does not need to be added to the list since the original token is also OOV
					if index > 0 then
						local wordEmbedding = embeddings[word] or unk
						origCopy.rank = origCopy.rank + index
						tinsert(origCopy, wordEmbedding)
						tinsert(alternativeTokensEmbeddings, origCopy)
					end
				end
			end
		end
		
		tinsert(originalTokensEmbeddings, tokenEmbedding)
	end
	
	originalTokensEmbeddings.rank = -1
	tinsert(alternativeTokensEmbeddings, originalTokensEmbeddings)
	
	return alternativeTokensEmbeddings
end

function classifier:Classify(message, toxicThreshold)
	local cleanMessage = removeFormatting(message)
	cleanMessage = string.lower(cleanMessage)
	
	local tokens = self:Tokenise(cleanMessage)
	if #tokens == 0 then return false end
	local tokensStr = table.concat(tokens, " ")
	
	-- Check if message result is in cache
	local cachedResult = self.classifyCache:get(tokensStr)
	if cachedResult then
		if cachedResult.score >= toxicThreshold then
			return true
		elseif cachedResult.threshold >= toxicThreshold or not cachedResult.terminatedEarly then
			-- Due to early termination of the classifier when threshold is exceeded, the cached result is not necessarily the maximum score
			-- If the previous threshold used for the cached result is lower than current threshold, the score needs to be recalculated
			return false
		end
	end
	
	-- Run SpellCheck to find alternative suggestions for misspelt words
	-- Get word embeddings tokens and other possible alternative words
	local allTokenCombinations = self:GetEmbeddings(tokens)
	table.sort(allTokenCombinations, function(t1, t2) return t1.rank < t2.rank end)
	
	if not self.lstmLayer then self.lstmLayer = lstm:new(data.Weights.LSTM.Kernel, data.Weights.LSTM.Recurrent, data.Weights.LSTM.Bias) end
	if not self.denseLayer then self.denseLayer = dense:new(data.Weights.Output.Kernel, data.Weights.Output.Bias) end
	-- Limit number of forward passes on LSTM layer to reduce processing time
	-- Future update: Provide option to user for "enhanced mode" for more powerful computers
	local maxScore = 0
	local currPasses = 0
	local cacheResult = { ['score'] = maxScore, ['threshold'] = toxicThreshold, ['terminatedEarly'] = false }
	for i, phrase in ipairs(allTokenCombinations) do
		local lstmOutput = self.lstmLayer:Predict(phrase, true)
		local score = self.denseLayer:Predict(lstmOutput)[1][1]
		if score > maxScore then maxScore = score; cacheResult.score = maxScore end
		if score >= toxicThreshold then
			cacheResult.terminatedEarly = i ~= #allTokenCombinations
			self.classifyCache:set(tokensStr, cacheResult)
			return true
		end
		currPasses = currPasses + #phrase
		if currPasses >= self.maxPasses then break end
	end
	self.classifyCache:set(tokensStr, cacheResult)
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
	classifier.classifyCache = lruCache.new(100)
	
	return newClassifier
end

addonTbl.classifier = classifier