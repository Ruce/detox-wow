local _, addonTbl = ...
local dense = {}
local matrix = addonTbl.matrix
local activation = addonTbl.activation

function dense:SetWeights(kernelWeights, bias)
	-- Shape of m*n where m is the number of input features, and n is the number of units (outputs)
	self.kernelWeights = matrix(kernelWeights)
	self.wT = matrix.transpose(self.kernelWeights)
	
	-- Matrix of n*1 where n is the number of units (outputs)
	self.bias = matrix(bias)
end

function dense:Predict(input)
	local x = matrix(input)
	local wT = self.wT
	local b = self.bias
	
	local y = activation.sigmoid((wT * x) + b)
	return setmetatable(y, nil)
end

function dense:new(kernelWeights, bias)
	layer = {}
	setmetatable(layer, self)
	self.__index = self
	
	layer:SetWeights(kernelWeights, bias) -- Also sets the shape of the layer
	
	return layer
end

addonTbl.dense = dense