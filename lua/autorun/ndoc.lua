if SERVER then
	AddCSLuaFile()
	util.AddNetworkString('netdoc.setKV')
	util.AddNetworkString('netdoc.sync')
	util.AddNetworkString('netdoc.fetch')
end

ndoc = {}
local ndoc = ndoc

require 'ra'
local kvo, ds = ra.kvo, ra.ds

ndoc.kWILDCARD = kvo.kWILDCARD
ndoc.compilePath = kvo.compilePath

-- DEFINE LOCALS
local ndoc_writeKey
local ndoc_writeValue
local ndoc_readKey
local ndoc_readValue
local ndoc_keyReaders
local ndoc_valueReaders
local ndoc_keyWriters
local ndoc_valueWriters
local id_to_table
local createTable


id_to_table = {}
function createTable(id, baseTable)
	local obj
	if baseTable and baseTable.__observers then
		obj = baseTable
	else
		obj = kvo.newKVOTable(baseTable)
	end
	rawset(obj, '__id', id)
	id_to_table[id] = obj
	return obj
end

--
-- PUBLIC API
--

if SERVER then
	local nextTableId = 1
	function ndoc.createTable(baseTable)
		local id = nextTableId
		nextTableId = nextTableId + 1

		local obj = createTable(id, baseTable)
		kvo.observe(obj, '_sync', function(key, value, oldValue)
			if type(value) == 'table' and value.__id == nil then
				print("ndoc.createTable(value)", value.__observers)
				ndoc.createTable(value)
				print(value.__id)
			end

			net.Start('netdoc.setKV')
				net.WriteUInt(id, 32)
				ndoc_writeKey(key)
				ndoc_writeValue(value)
			net.Send(player.GetAll())
		end, kvo.kWILDCARD)
		return obj
	end
end

function ndoc.ipairs(obj)
	return ipairs(obj.__real)
end

function ndoc.pairs(obj)
	return pairs(obj.__real)
end

function ndoc.getReal(obj)
	return obj.__real
end

function ndoc.observe(...)
	kvo.observe(...)
end

--
-- NETWORKING
--
-- ndoc.setKV
if CLIENT then
	net.Receive('netdoc.setKV', function()
		local tableId = net.ReadUInt(32)
		local table = id_to_table[tableId]
		if not table then return end
		local key = ndoc_readKey()
		local value = ndoc_readValue()
		print(tostring(key) .. ' = ' .. tostring(value))
		table[key] = value
	end)
end

-- ndoc.sync
if SERVER then
	local syncQueues = {}
	net.Receive('netdoc.fetch', function(_, pl)
		local fetchId = net.ReadUInt(32)
		if not id_to_table[fetchId] then return end
		if not syncQueues[pl] then
			syncQueues[pl] = ds.queue()
		end
		local queue = syncQueues[pl]
		local obj = id_to_table[fetchId]
		local real = rawget(obj, '__real')

		local restoreKey = nil
		queue:push(function()
			local real = real
			local key, value = restoreKey, nil
			net.WriteUInt(fetchId, 32) -- the table id being written
			while net.BytesWritten() < 0x4000 do
				key, value = next(real, key)
				if key == nil then break end
				ndoc_writeKey(key)
				ndoc_writeValue(value)
			end
			net.WriteUInt(0, 4) -- end of table delimiter
			if key == nil then return false end -- indicates writing is done on this routine
			restoreKey = key
			return true
		end)
	end)

	timer.Create('ndoc.processPlayerQueues', 0.1, 0, function()
		for pl, queue in pairs(syncQueues) do
			if queue:peek() == nil or not IsValid(pl) then
				syncQueues[pl] = nil
			else
				while true do
					net.Start('netdoc.sync')
					local top = queue:peek()
					if top and not top() then
						queue:pop() -- if it returns false then it is done, we should pop it and loop again to continue writing
					else
						break -- if it returned true then the writer has indicated that it has more writing to do, this player's channel has used it's data limit. break.
					end
					net.WriteUInt(0, 32) -- 0 is the null table id. used as an end of write stream delimiter.
					net.Send(pl)
				end
			end
		end
	end)
else
	net.Receive('netdoc.sync', function()
		while true do
			local tableId = net.ReadUInt(32)
			if tableId == 0 then break end -- end of the write stream delimiter
			local obj = id_to_table[tableId] or createTable(tableId)

			while true do
				local keyType = net.ReadUInt(4)
				if keyType == 0 then break end -- end of table stream delimiter
				local key = ndoc_keyReaders[keyType]()
				local value = ndoc_valueReaders[net.ReadUInt(4)]()
				print('\t' .. tostring(key) .. ' = ' .. tostring(value))
				obj[key] = value
			end
		end
	end)


end


ndoc_valueWriters = {}
ndoc_valueWriters['string'] = function(string)
	net.WriteUInt(1, 4)
	net.WriteString(string)
end
ndoc_valueWriters['table'] = function(table)
	net.WriteUInt(2, 4)
	net.WriteUInt(rawget(table, '__id'), 32)
end
ndoc_valueWriters['number'] = function(number)
	if number % 1 == 0 then
		net.WriteUInt(3, 4)
		net.WriteInt(number, 32)
	else
		net.WriteUInt(4, 4)
		net.WriteFloat(number)
	end
end
ndoc_valueWriters['nil'] = function()
	net.WriteUInt(5, 4)
end
ndoc_valueWriters['bool'] = function(value)
	if value then
		net.WriteUInt(6, 4)
	else
		net.WriteUInt(7, 4)
	end
end
ndoc_valueWriters['Entity'] = function(ent)
	net.WriteUInt(8, 4)
	net.WriteEntity(ent)
end
ndoc_valueWriters['Vehicle'] = ndoc_valueWriters['Entity']
ndoc_valueWriters['Player'] = ndoc_valueWriters['Entity']
ndoc_valueWriters['NextBot'] = ndoc_valueWriters['Entity']
ndoc_valueWriters['Weapon'] = ndoc_valueWriters['Entity']
ndoc_keyWriters = table.Copy(ndoc_valueWriters)

ndoc_valueReaders = {}
ndoc_valueReaders[1 --[[STRING]]] = net.ReadString
ndoc_valueReaders[2 --[[TABLE]]] = function()
	local id = net.ReadUInt(32)
	if id_to_table[id] then return id_to_table[id] end
	net.Start('netdoc.fetch')
		net.WriteUInt(id, 32)
	net.SendToServer()
	return createTable(id)
end
ndoc_valueReaders[3 --[[INTEGER]]] = function()
	return net.ReadInt(32)
end
ndoc_valueReaders[4 --[[FLOAT]]] = net.ReadFloat
ndoc_valueReaders[5 --[[NIL]]] = function() return nil end
ndoc_valueReaders[6 --[[TRUE]]] = function() return true end
ndoc_valueReaders[7 --[[FALSE]]] = function() return false end
ndoc_valueReaders[8 --[[ENTITY]]] = net.ReadEntity

ndoc_keyReaders = table.Copy(ndoc_valueReaders)

function ndoc_writeValue(value)
	ndoc_valueWriters[type(value)](value)
end

function ndoc_readValue()
	return ndoc_valueReaders[net.ReadUInt(4)]()
end

ndoc_writeKey = ndoc_writeValue
ndoc_readKey = ndoc_readValue



if SERVER then
	ndoc.table = ndoc.createTable()
	ndoc.ents = ndoc.createTable()

	hook.Add('EntityRemoved', 'ndoc.cleanup', function(entity)
		ndoc.ents[entity:EntIndex()] = nil
	end)
else
	ndoc.table = createTable(1)
	ndoc.ents = createTable(2)
	ra.net.WaitForPlayer(function()
		net.Start('netdoc.fetch')
			net.WriteUInt(1, 32)
		net.SendToServer()
		net.Start('netdoc.fetch')
			net.WriteUInt(2, 32)
		net.SendToServer()
	end)
end

local ents = ndoc.ents
local Entity = FindMetaTable('Entity')
function Entity:ndocData()
	local index = self:EntIndex()
	if not ents[index] then ents[index] = {} end
	return ents[index]
end

function ndoc.PrintTable(table)
	local function helper(depth, table)
		local prefix = string.rep('\t', depth)
		for k,v in pairs(table.__real) do
			if type(v) == 'table' then
				print(prefix..tostring(k)..' = '..tostring(v) .. ':' .. tostring(v.__id))
				helper(depth + 1, v)
			else
				print(prefix..tostring(k)..' = ' .. tostring(v))
			end
		end
	end
	helper(0, table)
end


concommand.Add('ndoc_PrintTable'..(SERVER and '_sv' or '_cl'), function(pl)
	if SERVER and IsValid(pl) and not pl:IsListenServerHost() then return end
	print("ndoc.table:")
	ndoc.PrintTable(ndoc.table)
	print("\nndoc.entities:")
	ndoc.PrintTable(ndoc.ents)
end)
