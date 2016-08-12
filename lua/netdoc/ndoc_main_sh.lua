-- TODO: sync netdoc tables

ndoc = {}

local id_to_table = {}
local function createTable(id)
		local theTable = kvo.newKVOTable()
		id_to_table[id] = theTable
		rawset(theTable, '__id', id)

		theTable:__kvo_observe('_sync', function(key, value)
			net.Start('ndoc.set')
				writeValue(theTable) -- sends the table id for free and gets them to fetch it if they haven't yet!
				writeKey(key)
				writeValue(value)
			net.Send(player.GetAll())
		end, kvo.kWILDCARD)

		return theTable
end

if SERVER then
	local nextTableId = 0
	ndoc.createTable = function()
		local table = createTable(nextTableId)
		nextTableId = nextTableId + 1
		return nextTableId
	end

	net.Receive('ndoc.fetch_table', function(_, pl)
		local tableId = ndoc.ReadUInt(32)
		-- TODO send the table back as a reply
	end)
end


local net_write = {}
net_write['table'] = function(table)
	net.WriteUInt(0, 4)
	net.WriteUInt(table.__id, 32)
end
net_write['string'] = function(string)
	net.WriteUInt(1, 4)
	net.WriteString(string)
end
net_write['number'] = function(number)
	if number % 1 == 0 then
		net.WriteUInt(2, 4)
		net.WriteInt(number)
	else
		net.WriteInt(3, 4)
		net.WriteFloat(number)
	end
end

local net_read = {}
if CLIENT then
	net_read[0 --[[TABLE]]] = function()
		local id = net.ReadUInt(4)
		if id_to_table[id] then
			net.Start('ndoc.fetch_table')
			net.WriteUInt(id, 32)
			net.SendToServer()
			return id_to_table[id]
		else
			return createTable(id)
		end
	end
else
	-- TODO: whatever should go here
end
net_read[1 --[[STRING]]] = function()
	return net.ReadString()
end
net_read[2 --[[NUMBER]]] = function()
	return net.ReadInt(32)
end
net_read[3 --[[NUMBER]]] = function()
	return net.ReadFloat()
end
