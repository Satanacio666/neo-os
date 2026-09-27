-- apps/bench.lua - High-Level Lua 3D Scripting & Telemetry Bridge
print("$FG,CYAN$=======================================================$FG$")
print("$FG,WHITE$ NeoOS LuaGL 3D Controller & Real-Time Telemetry Bridge $FG$")
print("$FG,CYAN$=======================================================$FG$")

-- 1. Start NeoBench Extreme in Mode 2 (Dynamics 3D Multi-Body Physics)
print("$FG,YELLOW$[LUA]$FG$ Starting NeoBench Extreme Dynamics via neo3d.start(2)...")
neo3d.start(2)

-- 2. Trigger explosive multi-body impulse in Ring 0
print("$FG,YELLOW$[LUA]$FG$ Triggering explosive multi-body velocity impulse...")
neo3d.trigger_impulse()

-- 3. Configure Global Hardware V-Sync to 60 Hz Smooth Lock
print("$FG,YELLOW$[LUA]$FG$ Configuring Global V-Sync to 60 Hz lock...")
neo3d.set_vsync(60)
print("$FG,GREEN$[LUA]$FG$ Active V-Sync Target: " .. tostring(neo3d.get_vsync()) .. " Hz")

-- 4. Native AAPCS FFI test: Call HolyC/C mathematical symbols directly via _G reflection
print("$FG,YELLOW$[LUA AAPCS FFI]$FG$ Calling native C symbols directly with AArch64 registers...")
if fast_sqrt_neon then
    local res = fast_sqrt_neon(64.0)
    print("$FG,GREEN$[LUA AAPCS FFI]$FG$ fast_sqrt_neon(64.0) [F32] = " .. tostring(res))
end
if fast_sqrt_d then
    local res_d = fast_sqrt_d(144.0)
    print("$FG,GREEN$[LUA AAPCS FFI]$FG$ fast_sqrt_d(144.0) [F64] = " .. tostring(res_d))
end
if math3d_sin then
    local s = math3d_sin(90.0)
    print("$FG,GREEN$[LUA AAPCS FFI]$FG$ math3d_sin(90 deg) [F32] = " .. tostring(s))
end
if math3d_sin_d then
    local s_d = math3d_sin_d(90.0)
    print("$FG,GREEN$[LUA AAPCS FFI]$FG$ math3d_sin_d(90 deg) [F64] = " .. tostring(s_d))
end

-- 5. Query Real-Time Telemetry
local fps = neo3d.get_fps()
local ft = neo3d.get_frame_time()
print("$FG,CYAN$[LUA TELEMETRY]$FG$ Current FPS: " .. tostring(fps) .. " | Avg Frame Time: " .. tostring(ft) .. " ms")

print("$FG,GREEN$[LUA]$FG$ Script completed successfully. Dynamics active with 64-bit physics.")
