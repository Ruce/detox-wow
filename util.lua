local _, addonTbl = ...
local util = {}

-- Count the number of values in a table; the # function only (sort of) works for integer-indexed tables
function util.TableLength(table1)
	local counter = 0
	for _,_ in pairs(table1) do
		counter = counter + 1
	end
	return counter
end

function util.ShallowCopyTable(table1)
	local t = {}
	for k,v in pairs(table1) do
		t[k] = v
	end
	return t
end

addonTbl.util = util