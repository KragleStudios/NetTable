# netdoc
Network document library by thelastpenguin

## Abstract
Nested table structures essentially form at ree where leaf nodes are values, and internal nodes are the tables themselves. The children of a table are essentially key value pairs. NetDoc essentially syncs a tree structure of tables and their values between the client and the server as well as changes made to the structure in real time.
 
The second feature that netdoc provides that is that you can "hook" a path in the table. A path is specified with the standard "." notation i.e. "players.?.money" will specify the path described by the following table
```
ndoc.table.players = {}
ndoc.table.players[some player entity] = {}
ndoc.table.players[some player entity].money = 15
```
now you can create a hook as follows
```
ndoc.addHook('players.?.money', 'set', function(player, value)
end)
```
this will be called whenever the money field is changed. Every ? in the path is added as a parameter to the function with the last parameter as the value.

## Usage
Assuming you have a structure yourmod.players[player entity].money stores some numeric amount of money that a player has
```
ndoc.hook('yourmod.players.?.money', 'set', function(player, money)
  player:ChatPrint("you now have $" .. tostring(money) .. " in your wallet!")
end)
```
The general pattern is that a '?' is a placeholder used either to indicate that you are interested in a wild card key 
at this depth in the path OR as a place holder value when used at the end of a path to indicate that you're interested
in receiving the value that was assigned or updated etc.

Hooks can be added serverside or client side and are processed automatically. It's worth noting that there is some overhead 
to a hook but it's not super signifigant. That being said minimizing assignments made to "bigtable" is wise.

## Network Visibility
```
ndoc.hook('yourmod.players.?', 'sync', function(playerTo, key)
  return player == key
end)
```
using the 'sync' hook you can control who gets to see which parts of the bigtable. This as you can imagine is VERY powerful.
THIS IS NOT YET IMPLEMENTED.
