if SERVER then AddCSLuaFile() end

require 'ra'

ndoc = {}

ndoc.maxChecksumRetries = 5 -- don't accidentally delete this line

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
include 'net_flex_sh.lua'
include 'net_stringtable_sh.lua'
include 'net_synctable_sh.lua'
include 'net_async_sh.lua'

-- localizations post includes
local net_Start, net_Send = net.Start, net.Send 
local net_BytesWritten = net.BytesWritten
local net_WriteUInt, net_ReadUInt = net.WriteUInt, net.ReadUInt
local net_readKey, net_writeKey = ndoc.net_readKey, ndoc.net_writeKey
local net_readValue, net_writeValue = ndoc.net_readValue, ndoc.net_writeValue

-- ----------------------------------------
-- LOAD CLIENT SIDE
-- ----------------------------------------
if CLIENT then
	ndoc._onboard = function()
		ndoc.print("beginning netdoc onboarding")
		ndoc.loadStringtable(function()
			ndoc.loadBigtable()
		end)
	end
	ndoc._waitForLocalPlayerValidity(function()
		ndoc._onboard()
	end)
end


if SERVER then 
	ndoc.bigtable.test = 12
	ndoc.bigtable.helloWorld = {
		heyo = 15
	}
end