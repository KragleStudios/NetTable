include 'netdoc/init_sh.lua'

if SERVER then
	AddCSLuaFile()

	ndoc.all_players = {}
	ndoc.print("constructing a huge table!")
	for i = 1, 1000 do
		ndoc.bigtable[i] = {
			value = i,
			astring = 'test'
		}

		for j = 1, 1000 do 
			ndoc.bigtable[i][j] = 'this is a big string to use alot of data'
		end
	end

	ndoc.all_players = player.GetAll()
	ndoc.print("waiting for sync to finish!")
else
	timer.Simple(1, function()
		ndoc.print("on board syncing!")
		ndoc._onboard()
	end)
end