if ndoc._synctable_loaded then return end 
ndoc._synctable_loaded = true

if SERVER then AddCSLuaFile() end

include 'net_flex_sh.lua'
include 'net_stringtable_sh.lua'

local type = type 
local select = select 
local net_Start, net_Send = net.Start, net.Send 
local net_BytesWritten = net.BytesWritten
local net_WriteUInt, net_ReadUInt = net.WriteUInt, net.ReadUInt
local net_readKey, net_writeKey = ndoc.net_readKey, ndoc.net_writeKey
local net_readValue, net_writeValue = ndoc.net_readValue, ndoc.net_writeValue
local table = table 

local _allowedKeyTypes = ndoc._allowedKeyTypes
local _allowedValueTypes = ndoc._allowedValueTypes

local _stringToId = ndoc._stringToId

--
-- PATH HOOKING
--
local stack_stores = {}
stack_stores[0] = function() return function(...) return ... end end
local function store_stack(...)
	local c = select('#', ...)
	if stack_stores[c] then return stack_stores[c](...) end

	local vars = {} for i = 1, c do vars[i] = 'v'..i end
	local vars_def = table.concat(vars, ', ')

	-- read the code it's safe
	RunString(string.format([[
		_G.__STACK_STORE = function(...)
			local %s = ...
			return function(...)
				return %s, ...
			end
		end
	]], vars_def, vars_def))

	stack_stores[c] = _G.__STACK_STORE
	_G.__STACK_STORE = nil
	return stack_stores[c](...)
end
ndoc.store_stack = store_stack

local function stack_dropfirst(a, ...)
	return ...
end
local function stack_onlyone(a)
	return a 
end

local kWILDCARD = {}
local table_to_inter_hooks = setmetatable({}, {__mode = 'k'})
local table_to_call_hooks = setmetatable({}, {__mode = 'k'})

local function nextHookObj(hookObj, wildKey)
	return stack_onlyone(hookObj.keyStack()), {
		pathStr = hookObj.pathStr,
		fn = hookObj.fn,
		keyStack = store_stack(stack_dropfirst(hookObj.keyStack())),
		argStack = wildKey ~= nil and store_stack(hookObj.argStack(wildKey)) or hookObj.argStack,
		type = hookObj.type
	}
end

local function makeTablePathValid(table, key, ...)
	if key == nil then return end
	if not table[key] then table[key] = {} end 
	makeTablePathValid(table[key], ...)
end

local function addHook(toTable, onKey, hookObj)
	print('onPath: ' .. hookObj.pathStr .. 'toTable: ', toTable, 'onKey: ', onKey, ' keyStack: ', hookObj.keyStack())
	if select("#", hookObj.keyStack()) == 0 then -- its done so just add it to the call hooks list for this table node
		print('reached empty stack! no more keys, this is a leaf!')
		-- it gets added to table_to_call_hooks
		makeTablePathValid(table_to_call_hooks, hookObj.type, toTable, onKey)

		local fn = hookObj.fn
		local argStack = hookObj.argStack
		table.insert(table_to_call_hooks[hookObj.type][toTable][onKey], function(...)
			fn(argStack(...))
		end)
	else
		-- it gets added to the table_inter_hooks instead :o
		makeTablePathValid(table_to_inter_hooks, toTable, onKey)
		table.insert(table_to_inter_hooks[toTable][onKey], hookObj)

		if onKey == kWILDCARD then
			for k,v in ndoc.pairs(toTable) do
				if type(v) == 'table' then
					addHook(v, nextHookObj(hookObj, k))
				end
			end
		elseif type(toTable[onKey]) == 'table' then
			addHook(toTable[onKey], nextHookObj(hookObj))
		end
	end
end

local function propogateHooksFromParentToChild(parent, key, child)
	if not table_to_inter_hooks[parent] then return end
	print("propogateHooksFromParentToChild(" .. tostring(parent) .. ", " .. tostring(key) .. ", " .. tostring(child) .. ")")

	local function addHookHelper(hook, onKey)
		addHook(
				child,
				nextHookObj(hook, onKey)
			)
	end	

	if table_to_inter_hooks[parent][key] then
		for k, hook in ipairs(table_to_inter_hooks[parent][kWILDCARD]) do
			addHookHelper(hook)
		end
	end

	if table_to_inter_hooks[parent][kWILDCARD] then
		for k, hook in ipairs(table_to_inter_hooks[parent][kWILDCARD]) do
			addHookHelper(hook, key)
		end
	end

end

function ndoc.compilePath(path)
	local segments = string.Explode('.', path, false)

	for k,v in ipairs(segments) do
		if v == '?' then segments[k] = kWILDCARD end
	end

	return store_stack(unpack(segments))
end

function ndoc.addHook(path, type, fn)
	print("ndoc.addHook(" .. tostring(path)..", " .. tostring(type) .. ", " ..tostring(fn) .. ")")
	local cpath = ndoc.compilePath(path)
	addHook(ndoc.table, stack_onlyone(cpath()), {
			pathStr = path,
			type = type,
			keyStack = store_stack(stack_dropfirst(cpath())),
			argStack = function(...) return ... end,
			fn = fn
		})
end

local function callHook(proxy, type, key, value)
	print("callHook(" .. tostring(proxy) .. ", " .. tostring(type) .. ", " .. tostring(key) .. ", " .. tostring(value) .. ")")
	PrintTable(table_to_call_hooks)
	if table_to_call_hooks[type] and table_to_call_hooks[type][proxy] then
		local hookIndex = table_to_call_hooks[type][proxy]
		if hookIndex[key] then
			for k,v in ipairs(hookIndex[key]) do
				v(value)
			end
		end
		if hookIndex[kWILDCARD] then
			for k,v in ipairs(hookIndex[kWILDCARD]) do
				v(key, value)
			end
		end
	end
end

--
-- SYNCING TABLES
-- 

if SERVER then 
	util.AddNetworkString('ndoc.t.setKV')
	util.AddNetworkString('ndoc.t.sync')
	util.AddNetworkString('ndoc.t.cl.requestFullSync')

	local _tableUidNext = 0
	local function nextUid()
		local tid = _tableUidNext
		_tableUidNext = _tableUidNext + 1
		return tid
	end

	local _idToProxy = setmetatable({}, {_mode = 'v'})
	local _proxyToId = setmetatable({}, {_mode = 'k'})
	local _proxyToReal = setmetatable({}, {_mode = 'k'})
	local _originalToProxy = setmetatable({}, {_mode = 'v'})


	function ndoc.ipairs(tbl)
		return ipairs(_proxyToReal[tbl])
	end

	function ndoc.pairs(tbl)
		return pairs(_proxyToReal[tbl])
	end

	function ndoc.getTableId(proxy)
		return _proxyToId[proxy] or _proxyToId[_originalToProxy[proxy]]
	end

	function ndoc.getTableById(id)
		return _idToProxy[id]
	end

	function ndoc.createTable(parent, key, inherits)
		local path
		if parent then
			path = store_stack(parent.__path(key))
		else
			path = store_stack(key)
		end

		local real = {}
		local proxy = {
			__key = key,
			__path = path,
			__hooks = {}
		}

		local tid = nextUid()
		
		_idToProxy[tid] = proxy
		_proxyToId[proxy] = tid
		_proxyToReal[proxy] = real

		setmetatable(proxy, {
				__index = real,
				__newindex = function(self, k, v)
					local tk, tv = type(k), type(v)
					if not _allowedKeyTypes[tk] then error("[ndoc] key type " .. tk .. " not supported by ndoc.") end 
					if not _allowedValueTypes[tv] then error("[ndoc] value type " .. tv .. " not supported by ndoc.") end

					if tv == 'table' then
						-- ndoc.print("setting table as value: " .. tostring(v))
						if type(real[k]) == 'table' then
							-- simply update the table rather than reassign it
							local oldVal = real[k]
							for k, v in pairs(v) do
								if oldVal[k] ~= v then
									oldVal[k] = v
								end
							end
							for k, _ in pairs(_proxyToReal[oldVal]) do
								if not v[k] then
									oldVal[k] = nil
								end
							end
							return 
						end
						v = ndoc.createTable(self, path, v)
					end
					if tk == 'string' then
						-- make sure it's in the string table
						if not _stringToId[k] then
							ndoc.addNetString(k)
						end
					end

					ndoc.print(tostring(tid) .. ' : ' .. tostring(k) .. ' = ' .. tostring(v))

					net_Start 'ndoc.t.setKV'
					net_WriteUInt(tid, 12)
					net_writeKey(k)
					net_writeValue(v)
					net_Send(ndoc.all_players)

					real[k] = v

					-- update the hook structure
					if type(v) == 'table' then
						propogateHooksFromParentToChild(proxy, k, v)
					end
					-- call hooks
					callHook(proxy, 'set', k, v)
				end
			})

		if inherits then
			_originalToProxy[inherits] = proxy

			-- TODO: add optimization for adding arrays
			for k,v in pairs(inherits) do
				proxy[k] = v
			end
		end

		return proxy
	end

	ndoc._syncTable = function(proxy, pl)
		local bytes = 0
		local tid = _proxyToId[proxy]
		if not tid then
			ndoc.error("syncing tables for "..pl:SteamID().." tried to sync an invalid tableid.")
			return 0
		end

		net_Start 'ndoc.t.sync'
		net_WriteUInt(tid, 12)

		local real = _proxyToReal[proxy]
		if not real then 
			ndoc.error("syncing tables for "..pl:SteamID().." no real entry for " .. tostring(proxy) .. " proxy")
			return 
		end -- we don't want to kill the entire onboard just because of this

		for k, v in ndoc.pairs(proxy) do

			if net_BytesWritten() > 32768 then
				net_WriteUInt(0, 4) -- TYPE_NIL
				bytes = bytes + 32768
				net_Send(pl or net.all_players)
				
				net_Start 'ndoc.t.sync'
				net_WriteUInt(tid, 12)
			end
			
			net_writeKey(k)
			net_writeValue(v)
		end

		net_WriteUInt(0, 4)
		bytes = bytes + net_BytesWritten()
		net_Send(pl or net.all_players)

		return bytes
	end

	net.Receive('ndoc.t.cl.requestFullSync', function(_, pl)
		local totalBytes = 0
		local lastTotalBytes = 0
		ndoc.async.eachSeries(_idToProxy, function(k, v, cback)
			totalBytes = totalBytes + ndoc._syncTable(v, pl)
			if  totalBytes - lastTotalBytes > 32768 then
				timer.Simple(0.1, cback)
				lastTotalBytes = totalBytes
			else
				cback()
			end
		end, function() 
			ndoc.print("bigtable sync data pack used " .. totalBytes)
		end)
	end)

	ndoc.table = ndoc.createTable() -- table with id: 0
elseif CLIENT then

	-- CLIENT
	local _idToProxy = setmetatable({}, {_mode = 'v'})
	local _proxyToId = setmetatable({}, {_mode = 'k'})
	local _proxyToReal = setmetatable({}, {_mode = 'k'})
	local tableStaging = {} -- stage a table while we request a partial sync

	function ndoc.getTableById(id)
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
	local _tableWithId = ndoc.getTableById

	function ndoc.ipairs(tbl)
		return ipairs(_proxyToReal[tbl])
	end

	function ndoc.pairs(tbl)
		return pairs(_proxyToReal[tbl])
	end

	net.Receive('ndoc.t.setKV', function()
		local tid = net_ReadUInt(12)
		local k = net_readKey()
		local v = net_readValue()

		--ndoc.print(tostring(tid) .. ' : ' .. tostring(k) .. ' = ' .. tostring(v))
		local real = _proxyToReal[_tableWithId(tid)]
		if not real then
			return 
		end
		real[k] = v
	end)

	net.Receive('ndoc.t.sync', function()
		local tid = net_ReadUInt(12)
		local t = _tableWithId(tid)
		local real = _proxyToReal[t]

		print("syncing table " .. tid)

		while true do
			local k = net_readKey()
			if k == nil then break end
			local v = net_readValue()
			real[k] = v
		end
	end)

	ndoc.loadBigtable = function()
		ndoc.print("syncing net document")
		net.Start 'ndoc.t.cl.requestFullSync'
		net.SendToServer()
	end

	ndoc.table = ndoc.getTableById(0) -- table from id: 0
end

-- TODO: optimize onboarding arrays