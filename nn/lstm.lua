local _, addonTbl = ...
local lstm = {}
local matrix = addonTbl.matrix
local activation = addonTbl.activation
local lruCache = addonTbl.lru

function lstm:SetWeights(kernelWeights, recurrentWeights, bias)
	-- Kernel weights: weights that scale the input features of each time step
	-- Shape of m*n where m is the number of input features, and n is 4 * number of output units
	-- Column values in IFCO order (input, forget, cell state, output)
	-- Each transformation's weights are consecutive, e.g. iiifffcccooo if there are 3 output units
	self.kernelWeights = matrix(kernelWeights)

	-- Recurrent weights: weights that scale the output from the previous time step (h_t-1)
	-- Shape of o*n where m is the number of output units, and n is 4 * number of output units
	-- Column values in IFCO order (input, forget, cell state, output)
	-- Each transformation's weights are consecutive, e.g. iiifffcccooo if there are 3 output units
	self.recurrentWeights = matrix(recurrentWeights)

	-- Bias: bias added to the linear transformation
	-- Matrix of size n*1 where n is 4 * number of output units
	-- Values in IFCO order (input, forget, cell state, output)
	-- Each transformation's values are consecutive, e.g. iiifffcccooo if there are 3 output units
	self.bias = matrix(bias)
	
	-- Shape of the model is determined by the dimensions of the weights
	self.m = matrix.rows(self.kernelWeights) -- num of input features
	self.o = matrix.columns(self.kernelWeights) / 4 -- num of output units	
	
	local m = self.m
	local o = self.o
	local sliceWeights = function(pos)
		-- pos: column position to start slicing the weight matrices
		-- Using the IFCO ordering, input weights have position 0, forget weights position 1, etc.

		-- submatrix inputs: i1, j1, i2, j2
		local recurr = matrix.transpose(matrix.subm(self.recurrentWeights, 1, o*pos+1, o, o*(pos+1)))
		local kern = matrix.transpose(matrix.subm(self.kernelWeights, 1, o*pos+1, m, o*(pos+1)))
		return matrix.concath(recurr, kern)
	end

	self.wInput = sliceWeights(0)
	self.wForget = sliceWeights(1)
	self.wCell = sliceWeights(2)
	self.wOutput = sliceWeights(3)

	self.bInput = matrix.transpose(matrix.subm(self.bias, 1, 1, 1, o))
	self.bForget = matrix.transpose(matrix.subm(self.bias, 1, o+1, 1, o*2))
	self.bCell = matrix.transpose(matrix.subm(self.bias, 1, o*2+1, 1, o*3))
	self.bOutput = matrix.transpose(matrix.subm(self.bias, 1, o*3+1, 1, o*4))
end

function lstm:SetState(cInitial, hInitial)
	-- Set cell and output states to given values
	-- If arguments are nil, default values to 0
	if cInitial then
		self.cPrev = matrix(cInitial)
	else
		self.cPrev = matrix:new(self.o, 1, 0)
	end
	if hInitial then
		self.hPrev = matrix(hInitial)
	else
		self.hPrev = matrix:new(self.o, 1, 0)
	end
	
	self.zeroedState = not (cInitial or hInitial)
end

function lstm:ForwardPass(x)
	local xCurr = matrix.transpose(matrix({x}))
	local cPrev = self.cPrev
	local hPrev = self.hPrev
	
	local hx = matrix.concatv(hPrev, xCurr)

	local inputGate = activation.sigmoid((self.wInput * hx) + self.bInput)
	local forgetGate = activation.sigmoid((self.wForget * hx) + self.bForget)
	local cTilde = activation.tanh((self.wCell * hx) + self.bCell)
	local outputGate = activation.sigmoid((self.wOutput * hx) + self.bOutput)

	local cCurr = matrix.hadamard(forgetGate, cPrev) + matrix.hadamard(inputGate, cTilde)
	local hCurr = matrix.hadamard(outputGate, activation.tanh(cCurr))
	self.cPrev = cCurr
	self.hPrev = hCurr
	
	return hCurr, cCurr
end

function lstm:Predict(inputs, reset)
	-- inputs: an integer-indexed table where each value is a time step
	-- Each time step should be a row vector (i.e. integer-indexed table) of length m, where m is the number of input features
	-- reset: boolean for whether to reset initial state to zero
	if reset then
		self:SetState()
	end
	
	local finalOutput = {{}}
	for _, x in ipairs(inputs) do
		-- For the first forward pass of a prediction (i.e. the first token, when states are at zero), use cached results if available
		if self.zeroedState then
			local xStr = table.concat(x, ",")
			local cachedResult = self.zeroedCache:get(xStr)
			if cachedResult then
				self.cPrev = cachedResult.c
				self.hPrev = cachedResult.h
				finalOutput = cachedResult.h
			else
				finalOutput, _ = self:ForwardPass(x)
				cachedResult = {["c"] = self.cPrev, ["h"] = self.hPrev}
				self.zeroedCache:set(xStr, cachedResult)
			end
			self.zeroedState = false
		else
			finalOutput, _ = self:ForwardPass(x)
		end
	end
	
	-- Return output as a plain table, removing the matrix metatable
	return setmetatable(finalOutput, nil)
end

function lstm:new(kernelWeights, recurrentWeights, bias, cInitial, hInitial)
	layer = {}
	setmetatable(layer, self)
	self.__index = self
	
	layer:SetWeights(kernelWeights, recurrentWeights, bias) -- Also sets the shape of the layer
	layer:SetState(cInitial, hInitial)
	layer.zeroedCache = lruCache.new(500)
	
	return layer
end

addonTbl.lstm = lstm