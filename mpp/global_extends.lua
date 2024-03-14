math.phi = 1.618033988749894

---Filters out a list
---@param t any
---@param func any
function table.filter(t, func)
	local new = {}
	for k, v in ipairs(t) do
		if func(v) then new[#new+1] = v end
	end
	return new
end

function table.map(t, func)
	local new = {}
	for k, v in pairs(t) do
		new[k] = func(v)
	end
	return new
end

function table.mapkey(t, func)
	local new = {}
	for k, v in pairs(t) do
		new[func(v)] = v
	end
	return new
end

function math.divmod(a, b)
	return math.floor(a / b), a % b
end
