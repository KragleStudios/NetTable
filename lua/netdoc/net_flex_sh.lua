if ndoc._flex_loaded then return end
ndoc._flex_loaded = true

if SERVER then AddCSLuaFile() end

include 'net_stringtable_sh.lua'
include 'net_utils_sh.lua'

-- ----------------------------------------
-- NETWORK ARBITRARY KEYS AND VALUES
-- ----------------------------------------

-- localizations
local net_Start, net_Send = net.Start, net.Send
local net_WriteUInt, net_ReadUInt = net.WriteUInt, net.ReadUInt 
local net_WriteInt, net_ReadInt = net.WriteInt, net.ReadInt 
local net_WriteString, net_ReadString = net.WriteString, net.ReadString
local net_WriteFloat, net_ReadFloat = net.WriteFloat, net.ReadFloat
local math_floor = math.floor
local Entity = Entity

local _stringToId = ndoc._stringToId
local _idToString = ndoc._idToString


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
	local _playerStringtables = {}
	key_encoders['string'] = function(value)
		local stIndex = _stringToId[value]
		if stIndex == nil then
			error "client is expected to add keys to string table before attempting to network with them"
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
		net_WriteUInt(ndoc.getTableId(table), 12)
	end
	value_decoders[TYPE_TABLE] = function(table)
		return net.ReadTable() -- not designed to be fast at all... please never use this
	end
else
	value_encoders['table'] = function(table)
		net.WriteTable(values)
	end
	value_decoders[TYPE_TABLE] = function()
		return ndoc.getTableById(net_ReadUInt(12))
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
