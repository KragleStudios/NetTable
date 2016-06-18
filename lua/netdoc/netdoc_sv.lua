-- iterate over a netdoc object
ndoc.ipairs = function(tbl)
	return ipairs(proxiesToReals[tbl])
end
ndoc.pairs = function(tbl)
	return pairs(proxiesToReals[tbl])
end


util.AddNetworkString('ndoc.t.ctor') -- table definition
util.AddNetworkString('ndoc.t.dtor') -- table destructor

-- utility for managing auto incrementing id pools
local _stringIdCounter = 0
local stringToId = setmetatable({}, {
		__index = function(self, key)
			rawset(self, key, _stringIdCounter)
			_stringIdCounter = _stringIdCounter + 1
			return self[key]
		end
	})

local _tableIdCounter = 0
local idToTable = {}
local tableToId = setmetatable({}, {
		__index = function(self, key)
			local _tableIdCounter = _tableIdCounter + 1
			tableToId[key] = _tableIdCounter
			idToTable[_tableIdCounter] = key
			return _tableIdCounter
		end
	})
local proxiesToReals = {}

-- utility to create a new networked table instance with a unique id
ndoc.createTable = function(copy)
	local proxy = {}
	local real = {}

	local id = tableToId[proxy]
	proxiesToReals[proxy] = real

	setmetatable(proxy, {
			__index = real
			__newindex = function(self, key, value)
				-- deleting values is a specialish case
				if value == nil then
					if type(real[k]) == 'table' then
						ndoc.destroyTable[id]
					end
				end

				local tk, tv = type(key), type(value)
				if tk == 'table' then error("ndoc can not have type(key) == table") end
				if tv == 'table' then
					real[key] = ndoc.createTable(value)
				end

				real[key] = value
			end
		})

	for k,v in ipairs(copy) do
		proxy[k] = v
	end
end

-- destroy table with the given id
ndoc.destroyTable = function(id)
	local proxy = idToTable[id]

	local deleteHelper = function(proxy)
		-- get the id
		local id = tableToId[proxy]
		idsDestroyed[#idsDestroyed + 1] = id

		-- recursive
		for k,v in pairs(proxiesToReals[proxy]) do
			if type(v) == 'table' then
				deleteHelper(v)
			end
		end

		-- clear lookup mappings
		idToTable[id] = nil
		tableToId[proxy] = nil
		proxiesToReals[proxy] = nil
	end

	deleteHelper(proxy)

	net.Start('ndoc.t.dtor')
		net.WriteUInt(id, 32)
	net.Send(player.GetAll())
end