local tinsert = table.insert
local tremove = table.remove

local function known(words, dictionary)
	local knownWords = {}
	for _, word in ipairs(words) do
		local result = dictionary[word]
		if result then
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
local function separates(splits, dictionary)
	local t = {}
	for _, v in ipairs(splits) do
		local left = v[1]
		local right = v[2]
		if right and right ~= "" then
			local leftKnown = known({left}, dictionary)
			local rightKnown = known({right}, dictionary)
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

function Detox:Classify(message)
	local dictionary = Detox.Dictionary
	local validCharacters = Detox.EnglishCharacters
	local characterMap = Detox.QwertyMap
	local separators = Detox.Separators
	
	local cleanMessage = removeFormatting(message)
	cleanMessage = string.lower(cleanMessage)
	local tokens = self:Tokenise(cleanMessage, validCharacters, separators)
	local toxic = false
	for _, token in pairs(tokens) do
		if string.len(token) > 2 then
			local knownWords = self:SpellCheck(token, dictionary, validCharacters, characterMap)
			for _, word in ipairs(knownWords) do
				if dictionary[word][1] > 0.5 then
					toxic = true
					return toxic
				end
			end
		end
	end
	
	return toxic
end

function Detox:SpellCheck(word, dictionary, validCharacters, characterMap)
	-- Inspired by http://norvig.com/spell-correct.html
	local knownWord = known({word}, dictionary)
	if #knownWord == 1 then
		return knownWord
	else
		local splitCharacters = split(word)
		local deletedWords = known(deletes(splitCharacters), dictionary)
		local transposedWords = known(transposes(splitCharacters), dictionary)
		local replacedWords = known(replaces(splitCharacters, characterMap), dictionary)
		local insertedWords = known(inserts(splitCharacters, validCharacters), dictionary)
		local separatedWords = separates(splitCharacters, dictionary)
		
		local possibleWords = {}
		insertToTable(possibleWords, deletedWords)
		insertToTable(possibleWords, transposedWords)
		insertToTable(possibleWords, replacedWords)
		insertToTable(possibleWords, insertedWords)
		insertToTable(possibleWords, separatedWords)
		
		return deduplicate(possibleWords)
	end
end

function Detox:Tokenise(message, validCharacters, separators)
	local tokens = {}
	local curtok = '' -- Current token
	local L = string.len(message)
	for i = 1, L do
		local c = string.sub(message, i, i)
		-- Reached a separator, save current token if it isn't blank
		if separators[c] then
			-- Do not combine with above if statement. In case of overlap between separator and validCharacter table, this order of operation prioritises separators.
			if curtok ~= '' then
				tinsert(tokens, curtok)
				curtok = ''
			end
		-- Not a separator character, append to token if it is a valid character
		elseif validCharacters[c] then
			curtok = curtok..c
		end
	end
	if curtok ~= '' then
		tinsert(tokens, curtok)
	end
	return tokens
end