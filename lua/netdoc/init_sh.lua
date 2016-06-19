require 'ra'

print "loading netdoc by thelastpenguin"

ndoc = {}

-- ----------------------------------------
-- SETUP RESTRICTIONS ON TYPES SUPPORTED
-- ----------------------------------------
ndoc._legal_key_types = {
	['string'] = true,
	['Entity'] = true,
	['Player'] = true,
	['Vehicle'] = true,
	['number'] = true,
	['boolean'] = true
}

ndoc._leagl_value_types = {
	['string'] = true,
	['table'] = true,
	['Entity'] = true,
	['Player'] = true,
	['Vehicle'] = true,
	['number'] = true,
	['boolean'] = true
}

-- ----------------------------------------
-- NETWORK UTILITIES
-- ----------------------------------------
local net_Start, net_Send = net.Start, net.Send
local player_GetAll = player.GetAll
local net_WriteUInt, net_ReadUInt = net.WriteUInt, net.ReadUInt 
local net_WriteInt, net_ReadInt = net.WriteInt, net.ReadInt 
local net_WriteString, net_ReadString = net.WriteString, net.ReadString
local net_WriteFloat, net_ReadFloat = net.WriteFloat, net.ReadFloat
local math_floor = math.floor
local Entity = Entity

local all_players = player.GetAll()
hook.Add('PlayerInitialSpawn', 'ndoc.update_all_players', function()
	all_players = player.GetAll()
end)
ndoc.getAllPlayers = function()
	return all_players 
end


--
-- NETWORKED STRINGS
--
local _stringToId = {}
local _idToString = {}
local _stringTableSize = 0

if SERVER then
	util.AddNetworkString('ndoc.st.addNetString')
	util.AddNetworkString('ndoc.st.syncNetStrings')

	ndoc.addNetString = function(string)
		_stringTableSize = _stringTableSize + 1 
		_idToString[_stringTableSize] = string
		_stringToId[string] = _stringTableSize
		net_Start('ndoc.st.addNetString')
			net_WriteUInt(_stringTableSize, 16)
			net_WriteString(string)
		net_Send(all_players)
	end

	ndoc.stringToId = function(string)
		return _stringToId[string]
	end
	ndoc.idToString = function(id)
		return _idToString[id]
	end

	hook.Add('PlayerInitialSpawn', 'ndoc.syncNetStrings', function(pl)
		ra.net.waitFor(pl, function()
			net_Start('ndoc.st.syncNetStrings')
			net_WriteUInt(_stringTableSize, 16)
			for i = 1, _stringTableSize do
				net_WriteString(_idToString[i])
			end
			net_Send(pl)
		end)
	end

else

	net.Receive('ndoc.st.syncNetStrings', function()
		_stringTableSize = net_ReadUInt(16)
		for i = 1, _stringTableSize do
			local str = net_ReadString()
			_idToString[i] = str 
			_stringToId[str] = i
		end
	end)

end

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

-- key encoder: string
if SERVER then
	local _nextStringIndex = 0 -- up to 2^12
	local _stringTable = {}
	local _playerStringtables = {}
	key_encoders['string'] = function(value)
		local stIndex = _stringTable[value]
		if _stringToId[value] == nil then
			ndoc.addNetString(value)
		end
		net_WriteUInt(TYPE_STRING, 4)
		net_WriteUInt(_stringToId[value], 12)
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
	return net_ReadSTring()
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

-- value encoder: table
if SERVER then
	value_encoders['table'] = function(table)

		-- WRITE CODE TO NETWORK A TABLE EFFICIENTLY!
		net_WriteUInt(TYPE_TABLE, 4)
		for k,v in pairs(table) do

		end
	end
	value_decoders[TYPE_TABLE] = function(table)
		net.ReadTable() -- not designed to be fast at all... please never use this
else
	value_encoders['table'] = function(table)
		net.WriteTable(values)
	end
	value_decoder['table'] = function()
		-- not going to be fun
	end
end

for k,v in pairs(key_encoders) do 
	if not value_encoders[k] then
		value_encoders[k] = key_encoders[k]
	end 
end


--
-- NET READ AND WRITE UTILS
--
ndoc.writeKey = function(key)
	key_encoders[type(key)](key)
end
ndoc.writeValue = function(value)
	value_encoders[type(value)](value)
end

ndoc.readKey = function(key, value)
	return key_decoders[net_ReadUInt(4)]()
end

ndoc.readValue = function(key, value)
	return value_decoders[net_ReadUInt(4)]()
end

