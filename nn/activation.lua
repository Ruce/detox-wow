local _, addonTbl = ...
local activation = {}
local matrix = addonTbl.matrix

function activation.sigmoid(mtx)
	return matrix.replace(mtx, function(x) return 1 / (1 + math.exp(-x)) end)
end

function activation.tanh(mtx)
	return matrix.replace(mtx, function(x) return math.tanh(x) end)
end

addonTbl.activation = activation