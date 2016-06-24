# netdoc
Network document library by thelastpenguin

## Usage
Assuming you have a structure yourmod.players[player entity].money stores some numeric amount of money that a player has
```
ndoc.hook('yourmod.players.$.money=$', 'onset', function(player, money)
  player:ChatPrint("you now have $" .. tostring(money) .. " in your wallet!")
end)
```
The general pattern is that a '$' is a placeholder used either to indicate that you are interested in a wild card key 
at this depth in the path OR as a place holder value when used at the end of a path to indicate that you're interested
in receiving the value that was assigned or updated etc.

Hooks can be added serverside or client side and are processed automatically. It's worth noting that there is some overhead 
to a hook but it's not super signifigant. That being said minimizing assignments made to "bigtable" is wise.

## Network Visibility
```
ndoc.hook('yourmod.players.$.*', 'sync', function(playerTo, key)
  return player == key
end)
```
using the 'sync' hook you can control who gets to see which parts of the bigtable. This as you can imagine is VERY powerful.
