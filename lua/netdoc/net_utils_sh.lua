if ndoc._utils_loaded then return end
ndoc._utils_loaded = true

if SERVER then AddCSLuaFile() end

-- table of all players
local all_players = player.GetAll()
ndoc.all_players = all_players
local function _updateAllPlayers()
	all_players = player.GetAll()
	ndoc.all_players = all_players
end
hook.Add('PlayerInitialSpawn', 'ndoc.update_all_players', _updateAllPlayers)
hook.Add('PlayerDisconnected', 'ndoc.update_all_players', _updateAllPlayers)

-- simple way to wait for localplayer
-- slow and dumb don't use this outside the ONE place ndoc calls it
if CLIENT then
	ndoc._waitForLocalPlayerValidity = function(callback)
		if not IsValid(LocalPlayer()) then
			return timer.Simple(0.1, function()
				ndoc._waitForLocalPlayerValidity(callback)
			end)
		end
		callback()
	end
end