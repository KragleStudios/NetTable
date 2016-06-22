if ndoc._stringtable_loaded then return end 
ndoc._stringtable_loaded = true

if SERVER then AddCSLuaFile() end

-- ----------------------------------------
-- NETWORK STRING TABLE 
-- ----------------------------------------

local net_Start, net_Send = net.Start, net.Send
local net_WriteUInt, net_ReadUInt = net.WriteUInt, net.ReadUInt 
local net_WriteString, net_ReadString = net.WriteString, net.ReadString


local _stringToId = {}
local _idToString = {}
local _stringTableSize = 0

ndoc._stringToId = _stringToId
ndoc._idToString = _idToString

local function computeChecksum()
	local t = {}
	for k,v in pairs(_idToString) do
		t[#t + 1] = v
	end
	return util.CRC(table.concat(t, ','))
end

if SERVER then
	util.AddNetworkString('ndoc.st.cl.requestSync')
	util.AddNetworkString('ndoc.st.addNetString')
	util.AddNetworkString('ndoc.st.syncNetStrings')
	util.AddNetworkString('ndoc.st.cl.checksum')

	local checksum = nil


	ndoc.addNetString = function(string)
		checksum = nil

		_stringTableSize = _stringTableSize + 1 
		_idToString[_stringTableSize] = string
		_stringToId[string] = _stringTableSize

		net_Start('ndoc.st.addNetString')
			net_WriteUInt(_stringTableSize, 12)
			net_WriteString(string)
		net_Send(ndoc.all_players)

		return _stringTableSize
	end

	ndoc.stringToId = function(string)
		return _stringToId[string]
	end
	ndoc.idToString = function(id)
		return _idToString[id]
	end

	-- handle string table sync requests
	net.Receive('ndoc.st.cl.requestSync', function(_, pl)
		net_Start 'ndoc.st.syncNetStrings' -- should be less than 64kb
			net_WriteUInt(_stringTableSize, 12)
			for i = 1, _stringTableSize do
				net_WriteString(_idToString[i])
			end
		net_Send(pl)
	end)

	net.Receive('ndoc.st.cl.checksum', function(_, pl)
		if not checksum then
			checksum = computeChecksum()
		end

		net_Start 'ndoc.st.cl.checksum'
		net_WriteString(checksum) -- verify the string table
		net_Send(pl)
	end)

else

	ndoc._stringTableReady = false
	ndoc.loadStringtable = function(callback)
		net_Start 'ndoc.st.cl.requestSync'
		net.SendToServer()

		net.Receive('ndoc.st.syncNetStrings', function()
			ndoc._stringTableReady = true
			local count = net_ReadUInt(12)
			for i = 1, count do 
				local string = net_ReadString()
				_idToString[i] = string
				_stringToId[string] = i 
			end

			ndoc.validateStringtable(function(success)
				if success then
					callback()
				else
					ndoc.loadStringtable(callback)
				end
			end)
		end)
	end

	ndoc.validateStringtable = function(callback, count)
		if count == ndoc.maxChecksumRetries then
			callback(false)
		end

		net_Start 'ndoc.st.cl.checksum'
		net.SendToServer()
		net.Receive('ndoc.st.cl.checksum', function()
			local server = net_ReadString()
			local client = computeChecksum()
			ndoc.print("checking stringtable checksum, server: " .. server .. " client: " .. client)

			if server ~= client then
				MsgC(Color(255, 0, 0), '[ndoc] stringtable checksum mismatch, retry ' .. tostring(count or 1))
				return timer.Simple(0.1, function() ndoc.validateStringtable(callback, (count or 0) + 1) end)
			end
			ndoc.print("checksum okay, string table in sync.")
			callback(true)
		end)
	end

	net.Receive('ndoc.st.addNetString', function()
		local id = net_ReadUInt(12)
		local string = net_ReadString()
		_stringToId[string] = id
		_idToString[id] = string 
		_stringTableSize = math.max(_stringTableSize, id)
		ndoc.print("network string: " .. tostring(id) .. " -> " .. string)
	end)

end