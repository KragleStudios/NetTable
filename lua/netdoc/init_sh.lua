require 'ra'

print "loading netdoc by thelastpenguin"

ndoc = {}


-- ----------------------------------------
-- INPUT RESTRICTIONS
-- ----------------------------------------
ndoc._allowedKeyTypes = {
	['table'] = false,
	['string'] = true,
	['Entity'] = true,
	['Player'] = true,
	['Vehicle'] = true,
	['boolean'] = true,
	['number'] = true
}

ndoc._allowedValueTypes = {
	['table'] = true,
	['string'] = true,
	['Entity'] = true,
	['Player'] = true,
	['Vehicle'] = true,
	['boolean'] = true,
	['number'] = true
}

-- ----------------------------------------
-- INPUT RESTRICTIONS
-- ----------------------------------------
include 'net_utils_sh.lua'

-- localizations post includes
local net_Start, net_Send = net.Start, net.Send 
local net_readKey, net_writeKey = ndoc.net_readKey, ndoc.net_writeKey
local net_readValue, net_writeValue = ndoc.net_readValue, ndoc.net_writeValue

-- ----------------------------------------
-- NDOC REAL
-- ----------------------------------------
local _proxyToId
local _idToProxy

if SERVER then
	local _allowedKeyTypes = ndoc._allowedKeyTypes
	local _allowedValueTypes = ndoc._allowedValueTypes

	util.AddNetworkString('ndoc.t.setKV')
	util.AddNetworkString('ndoc.t.sync')

	-- the server component of netdoc 
	local _tableUidNext = 0
	_idToProxy = setmetatable({}, {_mode = 'v'})
	_proxyToId = setmetatable({}, {_mode = 'k'})
	local _proxyToReal = setmetatable({}, {_mode = 'k'})
	local _originalToProxy = setmetatable({}, {_mode = 'v'})


	function ndoc.tableGetId(proxy)
		return _proxyToId[proxy]
	end

	function ndoc.tableWithId(id)
		return _idToProxy[id]
	end

	function ndoc.createTable(parent)
		if _originalToProxy[parent] then
			print "returning mapping!"
			local old = _originalToProxy[parent]

			for k, v in pairs(parent) do
				if v ~= parent and v ~= old[k] then
					old[k] = v
				end
			end					

			return _proxyToId[old]
		end

		local real = {}
		local proxy = {} 
		local tid = _tableUidNext
		_tableUidNext = _tableUidNext + 1

		_idToProxy[tid] = proxy
		_proxyToId[proxy] = tid
		_proxyToReal[proxy] = real 

		setmetatable(proxy, {
				__index = real,
				__newindex = function(self, k, v)
					local tk, tv = type(k), type(v)
					if not _allowedKeyTypes[tk] then error("[ndoc] key type " .. tk .. " not supported by ndoc.") end 
					if not _allowedValueTypes[tv] then error("[ndoc] value type " .. tv .. " not supported by ndoc.") end

					print(tostring(tid) .. ' : ' .. tostring(k) .. ' = ' .. tostring(v))

					if tv == 'table' then
						print("setting table as value: " .. tostring(v))
						v = _idToProxy[ndoc.createTable(v)]
					end

					net_Start 'ndoc.t.setKV'
					net_WriteUInt(tid, 12)
					net_writeKey(k)
					net_writeValue(v)
					net_Send(all_players)

					real[k] = v

				end
			})

		if parent then
			print("original to proxy: " .. tostring(parent))
			_originalToProxy[parent] = proxy

			-- TODO: add optimization for onboarding arrays
			for k,v in pairs(parent) do
				proxy[k] = v
			end
		end

		return tid
	end

	ndoc.bigtable = ndoc.tableWithId(ndoc.createTable()) -- table with id: 0
else 
	-- CLIENT
	_idToProxy = setmetatable({}, {_mode = 'v'})
	_proxyToId = setmetatable({}, {_mode = 'k'})
	local _proxyToReal = setmetatable({}, {_mode = 'k'})

	function ndoc.tableWithId(id)
		local proxy = _idToProxy[id]
		if proxy then return proxy end
		
		local real = {}
		proxy = {}
		setmetatable(proxy, {
				__index = real,
				__newindex = function()
					error 'attempt to assign in client copy of table - not yet supported'
				end
			})

		_proxyToReal[proxy] = real
		_idToProxy[id] = proxy
		_proxyToId[proxy] = id

		return proxy
	end
	local _tableWithId = ndoc.tableWithId

	net.Receive('ndoc.t.setKV', function()
		local tid = net_ReadUInt(12)
		local k = net_readKey()
		local v = net_readValue()
		print(tostring(tid) .. ' : ' .. tostring(k) .. ' = ' .. tostring(v))
		_proxyToReal[_tableWithId(tid)][k] = v
	end)

	ndoc.bigtable = ndoc.tableWithId(0) -- table from id: 0
end

-- ----------------------------------------
-- NDOC ON BOARDING
-- ----------------------------------------
if CLIENT then
	timer.Create('ndoc.waitForSelf', 1, 0, function()
		if not IsValid(LocalPlayer()) then return end
		timer.Destroy('ndoc.waitForSelf')

		-- request the string table sync
		net_Start 'ndoc.st.cl.requestSync'
		net.SendToServer()

		net.Receive('ndoc.st.syncNetStrings', function()
			ndoc._receiveStringTable()

			-- now that the string table has sync'd request that the entire table should sync
			net.Start 'ndoc.t.cl.requestSync'
			
			net.SendToServer()
		end)
	end)



-- general strategy
--[[
 - whenever a table gets added you create a table as a proxy for it
 - if the same table gets added twice the same proxy is used and possibly updated (todo add updating for the proxy and propper diffing)
 - batch sync keys and values when onboarding 
]]

if SERVER then

	local datastructure = {}
	datastructure[1] = datastructure
	datastructure[2] = "hello world"
	ndoc.bigtable.test = datastructure

end