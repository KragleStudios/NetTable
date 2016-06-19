-- iterate over a netdoc object
ndoc.ipairs = function(tbl)
	return ipairs(proxiesToReals[tbl])
end
ndoc.pairs = function(tbl)
	return pairs(proxiesToReals[tbl])
end

local _tableIdCounter = 0
local idToTable = {}
local tableToId = {}
local proxiesToReals = {}

ndoc.getTableId = function(table)
	return tableToId[table]
end

-- utility to create a new networked table instance with a unique id
ndoc.createTable = function(copy)
	local proxy = {}
	local real = {}

	_tableIdCounter = _tableIdCounter + 1
	local id = _tableIdCounter
	idToTable[id] = proxy
	tableToId[proxy] = id
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