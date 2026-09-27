-- NeoOS Lua 5.4.7 Demo Script
print("$FG,CYAN$=== NeoOS Unified Lua 5.4.7 Demo ===$FG$")
print("$FG,GREEN$[LUA -> DOLDOC]$FG$ Hello from Lua 5.4.7 in EL1 Ring 0 SASOS!")
local sum = 0
for i = 1, 10 do sum = sum + i end
print("Lua computed sum 1..10 = " .. tostring(sum))
