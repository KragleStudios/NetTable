if SERVER then AddCSLuaFile() end

require 'ra'

ndoc = {}


-- ----------------------------------------
-- LOGGING
-- ----------------------------------------
ndoc.print = function(...)
	MsgC(Color(255, 255, 255), '[nDoc] ')
	print(...)
end

ndoc.print("loading ndoc by thelastpenguin")

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
local net_BytesWritten = net.BytesWritten
local net_WriteUInt, net_ReadUInt = net.WriteUInt, net.ReadUInt
local net_readKey, net_writeKey = ndoc.net_readKey, ndoc.net_writeKey
local net_readValue, net_writeValue = ndoc.net_readValue, ndoc.net_writeValue

-- ----------------------------------------
-- NDOC REAL
-- ----------------------------------------
if SERVER then
	local _allowedKeyTypes = ndoc._allowedKeyTypes
	local _allowedValueTypes = ndoc._allowedValueTypes

	util.AddNetworkString('ndoc.t.setKV')
	util.AddNetworkString('ndoc.t.sync')
	util.AddNetworkString('ndoc.t.cl.requestSync')

	-- the server component of netdoc 
	local _tableUidNext = 0
	local _idToProxy = setmetatable({}, {_mode = 'v'})
	local _proxyToId = setmetatable({}, {_mode = 'k'})
	local _proxyToReal = setmetatable({}, {_mode = 'k'})
	local _originalToProxy = setmetatable({}, {_mode = 'v'})

	function ndoc.ipairs(proxy)
		return ipairs(_proxyToReal[proxy])
	end

	function ndoc.pairs(proxy)
		return pairs(_proxyToReal[proxy])
	end

	function ndoc.tableGetId(proxy)
		return _proxyToId[proxy]
	end

	function ndoc.tableWithId(id)
		return _idToProxy[id]
	end

	function ndoc.createTable(parent)
		if _originalToProxy[parent] then
			local old = _originalToProxy[parent]

			for k, v in pairs(parent) do
				if v ~= parent and v ~= old[k] then
					old[k] = v
				end
			end					

			return old
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

					ndoc.print(tostring(tid) .. ' : ' .. tostring(k) .. ' = ' .. tostring(v))

					if tv == 'table' then
						ndoc.print("setting table as value: " .. tostring(v))
						v = ndoc.createTable(v)
					end

					net_Start 'ndoc.t.setKV'
					net_WriteUInt(tid, 12)
					net_writeKey(k)
					net_writeValue(v)
					net_Send(ndoc.all_players)

					real[k] = v

				end
			})

		if parent then
			ndoc.print("original to proxy: " .. tostring(parent))
			_originalToProxy[parent] = proxy

			-- TODO: add optimization for onboarding arrays
			for k,v in pairs(parent) do
				proxy[k] = v
			end
		end

		return proxy
	end

	ndoc._syncTable = function(proxy, pl)
		local tid = _proxyToId[proxy]
		net_Start 'ndoc.t.sync'
		net_WriteUInt(tid, 12)
		for k, v in ndoc.pairs(proxy) do
			if net_BytesWritten() > 32768 then
				net_WriteUInt(0, 4) -- TYPE_NIL
				net_Send(pl or net.all_players)
				
				net_Start 'ndoc.t.sync'
				net_WriteUInt(tid, 12)
			end
		end
		net_WriteUInt(0, 4)
		net_Send(pl or net.all_players)
	end

	net.Receive('ndoc.t.cl.requestSync', function(pl)
		for k,v in pairs(_idToProxy) do
			ndoc._syncTable(v, pl)
		end
	end)

	ndoc.bigtable = ndoc.createTable() -- table with id: 0
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

		ndoc.print(tostring(tid) .. ' : ' .. tostring(k) .. ' = ' .. tostring(v))

		_proxyToReal[_tableWithId(tid)][k] = v
	end)

	net.Receive('ndoc.t.sync', function()
		local tid = net_ReadUInt(12)
		local t = ndoc.tableWithId(tid)
		local real = _proxyToReal[t] 

		for i = 1, kvPairCount do 
			local k, v = net_readKey(), net_readValue()
			if k == nil then break end
			real[k] = v
		end
	end)

	ndoc.bigtable = ndoc.tableWithId(0) -- table from id: 0
end

-- ----------------------------------------
-- NDOC ON BOARDING
-- ----------------------------------------
if CLIENT then
	hook.Add('ndoc.ReadyForOnboarding', 'ndoc.onboard', function()

		net.Start 'ndoc.t.cl.requestSync'

	end)
end


if SERVER then

	local datastructure = {}
	datastructure[1] = datastructure
	datastructure[2] = "hello world"
	ndoc.bigtable.test = datastructure

end