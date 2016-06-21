if SERVER then AddCSLuaFile() end

-- ----------------------------------------
-- NETWORK UTILITIES
-- ----------------------------------------

-- localizations
local net_Start, net_Send = net.Start, net.Send
local player_GetAll = player.GetAll
local net_WriteUInt, net_ReadUInt = net.WriteUInt, net.ReadUInt 
local net_WriteInt, net_ReadInt = net.WriteInt, net.ReadInt 
local net_WriteString, net_ReadString = net.WriteString, net.ReadString
local net_WriteFloat, net_ReadFloat = net.WriteFloat, net.ReadFloat
local math_floor = math.floor
local Entity = Entity

-- table of all players
local all_players = player.GetAll()
ndoc.all_players = all_players
local function _updateAllPlayers()
	all_players = player.GetAll()
	ndoc.all_players = all_players
end
hook.Add('PlayerInitialSpawn', 'ndoc.update_all_players', _updateAllPlayers)
hook.Add('PlayerDisconnected', 'ndoc.update_all_players', _updateAllPlayers)


--
-- NETWORKED STRINGS
--
local _stringToId = {}
local _idToString = {}
local _stringTableSize = 0

if SERVER then
	util.AddNetworkString('ndoc.st.cl.requestSync')
	util.AddNetworkString('ndoc.st.addNetString')
	util.AddNetworkString('ndoc.st.syncNetStrings')

	ndoc.addNetString = function(string)
		_stringTableSize = _stringTableSize + 1 
		_idToString[_stringTableSize] = string
		_stringToId[string] = _stringTableSize

		net_Start('ndoc.st.addNetString')
			net_WriteUInt(_stringTableSize, 12)
			net_WriteString(string)
		net_Send(all_players)

		return _stringTableSize
	end

	ndoc.stringToId = function(string)
		return _stringToId[string]
	end
	ndoc.idToString = function(id)
		return _idToString[id]
	end

	-- syncing with clients
	ndoc._syncStringTableWithPlayer = function(pl)
		net_Start 'ndoc.st.syncNetStrings' -- should be less than 64kb
			net_WriteUInt(_stringTableSize, 12)
			for i = 1, _stringTableSize do
				net_WriteString(_idToString[i])
			end
		net_Send(pl)
	end

	net.Receive('ndoc.st.cl.requestSync', function(_, pl)
		ndoc._syncStringTableWithPlayer(pl)
	end)

else
	net.Receive('ndoc.st.addNetString', function()
		local id = net_ReadUInt(12)
		local string = net_ReadString()
		_stringToId[string] = id
		_idToString[id] = string 
		_stringTableSize = math.max(_stringTableSize, id)
		ndoc.print("network string: " .. tostring(id) .. " -> " .. string)
	end)


	timer.Create('ndoc.waitForSelf', 1, 0, function()
		if not IsValid(LocalPlayer()) then return end
		ndoc.print("requesting string table sync")
		timer.Destroy('ndoc.waitForSelf')

		-- request the string table sync
		net_Start 'ndoc.st.cl.requestSync'
		net.SendToServer()

		net.Receive('ndoc.st.syncNetStrings', function()
			-- read string table
			ndoc.print("sync'd string table...")
			for i = 1, net_ReadUInt(12) do
				local str = net_ReadString()
				_idToString[i] = str 
				_stringToId[str] = i
				ndoc.print("\t" .. str)
			end

			ndoc.print("sync'd stringtable: " .. tostring(#_idToString))

			-- allow hooking
			hook.Call('ndoc.ReadyForOnboarding')
		end)
	end)
end

-- networking enums
local type         = type 
local TYPE_NIL     = 0
local TYPE_STRING  = 1
local TYPE_ENTITY  = 2
local TYPE_NUMBER  = 3
local TYPE_FLOAT   = 4
local TYPE_BOOLEAN_TRUE = 5
local TYPE_BOOLEAN_FALSE = 6
local TYPE_TABLE   = 7

-- data encoders
local key_encoders = {}
local key_decoders = {}
local value_encoders = {}
local value_decoders = {}

--
-- NET READ AND WRITE UTILS
--
ndoc.net_writeKey = function(key)
	key_encoders[type(key)](key)
end
ndoc.net_writeValue = function(value)
	value_encoders[type(value)](value)
end

ndoc.net_readKey = function(key, value)
	return key_decoders[net_ReadUInt(4)]()
end

ndoc.net_readValue = function(key, value)
	return value_decoders[net_ReadUInt(4)]()
end



-- key encoder: string
if SERVER then
	local _nextStringIndex = 0 -- up to 2^12
	local _stringTable = {}
	local _playerStringtables = {}
	key_encoders['string'] = function(value)
		local stIndex = _stringTable[value]
		if _stringToId[value] == nil then
			stIndex = ndoc.addNetString(value)
		end
		net_WriteUInt(TYPE_STRING, 4)
		net_WriteUInt(stIndex, 12)
	end
	key_decoders[TYPE_STRING] = function()
		return net_ReadString()
	end
else
	key_decoders[TYPE_STRING] = function()
		return _idToString[net_ReadUInt(12)]
	end
	key_encoders['string'] = function(value)
		net_WriteUInt(TYPE_STRING, 4)
		net_WriteString(_stringToId[value], 12)
	end
end

value_encoders['string'] = function(value)
	net_WriteUInt(TYPE_STRING, 4)
	net_WriteString(value)
end 
value_decoders[TYPE_STRING] = function()
	return net_ReadString()
end

-- key encoder: number
key_encoders['number'] = function(value)
	if math_floor(value) == value and (value < 8388608 and value > -8388608) --[[ 2 ^ (24 - 1) ]] then
		net_WriteUInt(TYPE_NUMBER, 4)
		net_WriteInt(value, 24)
	else
		net_WriteUInt(TYPE_FLOAT, 4)
		net_WriteFloat(value)
	end
end

key_decoders[TYPE_FLOAT] = net_ReadFloat
key_decoders[TYPE_NUMBER] = function()
	return net_ReadUInt(24)
end

-- key encoder: Entity
key_encoders['Entity'] = function(value)
	net_WriteUInt(TYPE_ENTITY, 4)
	net_WriteUInt(value:EntIndex(), 12)
end
key_decoders[TYPE_ENTITY] = function()
	return Entity(net_ReadUInt(12))
end
key_encoders['Player'] = key_encoders['Entity']

-- key encoder: boolean
key_encoders['boolean'] = function(value)
	if value then
		net_WriteUInt(TYPE_BOOLEAN_TRUE, 4)
	else
		net_WriteUInt(TYPE_BOOLEAN_FALSE, 4)
	end 
end 
key_decoders[TYPE_BOOLEAN_TRUE] = function() return true end
key_decoders[TYPE_BOOLEAN_FALSE] = function() return false end 

key_encoders['nil'] = function()
	net_WriteUInt(TYPE_NIL, 4)
end
key_decoders[TYPE_NIL] = function() return nil end 

-- value encoder: table
if SERVER then
	value_encoders['table'] = function(table)

		-- WRITE CODE TO NETWORK A TABLE EFFICIENTLY!
		net_WriteUInt(TYPE_TABLE, 4)
		net_WriteUInt(ndoc.tableGetId(table), 12)
	end
	value_decoders[TYPE_TABLE] = function(table)
		return net.ReadTable() -- not designed to be fast at all... please never use this
	end
else
	value_encoders['table'] = function(table)
		net.WriteTable(values)
	end
	value_decoders[TYPE_TABLE] = function()
		return ndoc.tableWithId(net_ReadUInt(12))
	end
end

for k,v in pairs(key_encoders) do 
	if not value_encoders[k] then
		value_encoders[k] = v
	end 
end

for k,v in pairs(key_decoders) do 
	if not value_decoders[k] then
		value_decoders[k] = v
	end 
end

