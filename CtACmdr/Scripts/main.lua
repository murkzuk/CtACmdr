-- CtACmdr v1.0 : holds the camera in, plain numpad to move it, saved per tank.
-- MIT licensed, (c) 2026 murkz. See LICENSE.
--
--   F3          commander view ON  (pins zoom distances so the game cannot slide out)
--   F4          normal view
--   NUM 8 / 2   camera forward / back
--   NUM 4 / 6   left / right
--   NUM 9 / 3   up / down
--   NUM 5       reset offset
--   NUM 0       SAVE this tank
--   F6          report
-- No modifiers - SHIFT is the gunsight, CTRL is used by the debug tools.

local OUT = "CtACmdr.log"
local SAVE = "CtACmdr_views.txt"
local STEP = 5.0

local fh = nil

local function openLog()
    if fh then return end
    local ok, h = pcall(io.open, OUT, "a")
    if ok and h then fh = h end
end

local function log(msg)
    local stamp = "--:--:--"
    pcall(function() stamp = os.date("%H:%M:%S") end)
    local line = "[" .. stamp .. "] " .. tostring(msg)
    print("[CtACmdr] " .. line)
    if fh then pcall(function() fh:write(line .. "\n"); fh:flush() end) end
end

local profiles = {}

local function loadProfiles()
    profiles = {}
    local ok, h = pcall(io.open, SAVE, "r")
    if not ok or not h then return end
    pcall(function()
        for line in h:lines() do
            local name, x, y, z = string.match(line, "^%s*([%w_%-%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
            if name then
                profiles[name] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
            end
        end
    end)
    pcall(function() h:close() end)
end

local function saveProfiles()
    local ok, h = pcall(io.open, SAVE, "w")
    if not ok or not h then return false end
    pcall(function()
        h:write("# CtACmdr per-tank camera offsets: class x y z\n")
        for name, p in pairs(profiles) do
            h:write(string.format("%s %.2f %.2f %.2f\n", name, p.x or 0, p.y or 0, p.z or 0))
        end
        h:flush()
        h:close()
    end)
    return true
end

local function fname(o)
    local ok, n = pcall(function() return o:GetFName():ToString() end)
    if ok and n then return n end
    return "?"
end

local function fullname(o)
    local ok, n = pcall(function() return o:GetFullName() end)
    if ok and n then return n end
    return "?"
end

local function isObj(v)
    return type(v) == "userdata"
end

local function num(o, k)
    local ok, v = pcall(function() return o[k] end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function vecStr(v)
    if v == nil then return "nil" end
    if type(v) == "table" then return string.format("%.1f, %.1f, %.1f", v.X or 0, v.Y or 0, v.Z or 0) end
    local x, y, z = num(v, "X"), num(v, "Y"), num(v, "Z")
    if x == nil then return "struct?" end
    return string.format("%.1f, %.1f, %.1f", x, y, z)
end

local function getPawn()
    local pcs = nil
    pcall(function() pcs = FindAllOf("PlayerController") end)
    if not pcs then return nil end
    for _, p in ipairs(pcs) do
        local valid = false
        pcall(function() valid = p:IsValid() end)
        if valid and not string.find(fullname(p), "Default__", 1, true) then
            local temp = nil
            pcall(function() temp = p["Pawn"] end)
            if isObj(temp) then return temp end
        end
    end
    return nil
end

local function tankName(pawn)
    return fname(pawn:GetClass())
end

local state = { off = { x = 0, y = 0, z = 0 }, on = false }

local function getPart(pawn, name)
    local v = nil
    pcall(function() v = pawn[name] end)
    if isObj(v) then return v end
    return nil
end

local function applyOffset(pawn)
    local arm = getPart(pawn, "FollowSpringArm")
    if arm == nil then log("  no FollowSpringArm"); return end
    local want = { X = state.off.x, Y = state.off.y, Z = state.off.z }
    local okW = pcall(function() arm["SocketOffset"] = want end)
    local okR, got = pcall(function() return arm["SocketOffset"] end)
    local gx = num(got, "X")
    local match = (gx ~= nil and math.abs(gx - want.X) < 0.01)
    log(string.format("  SocketOffset want (%.1f, %.1f, %.1f) got (%s) write=%s %s",
        want.X, want.Y, want.Z, okR and vecStr(got) or "?", tostring(okW),
        match and "OK" or "MISMATCH"))
end

-- pin the zoom distances so the game cannot slide the camera back out
local function pinZoom(pawn, on)
    local zoom = getPart(pawn, "Zoom")
    if zoom == nil then log("  no Zoom component"); return end
    if on then
        -- leave MaxCamDistance alone: min == max == 0 risks a divide by zero
        pcall(function() zoom["MinCamDistance"] = 0.0 end)
        pcall(function() zoom["DefaultCamDistance"] = 0.0 end)
        pcall(function() zoom:SetCamDistanceTarget(0.0) end)
        pcall(function() zoom["RelativeZoomCameraPitchLimit"] = 85.0 end)
        pcall(function() zoom["RelativeZoomCameraYawLimit"] = 175.0 end)
        log("  zoom pinned: min=0 default=0 (max untouched), look limits 85/175")
    else
        pcall(function() zoom["MinCamDistance"] = 150.0 end)
        pcall(function() zoom["MaxCamDistance"] = 800.0 end)
        pcall(function() zoom["DefaultCamDistance"] = 500.0 end)
        pcall(function() zoom:SetCamDistanceTarget(500.0) end)
        pcall(function() zoom["RelativeZoomCameraPitchLimit"] = 20.0 end)
        pcall(function() zoom["RelativeZoomCameraYawLimit"] = 45.0 end)
        log("  zoom restored: 150/800/500, look limits 20/45")
    end
    log(string.format("  now min=%s max=%s default=%s",
        tostring(num(zoom, "MinCamDistance")),
        tostring(num(zoom, "MaxCamDistance")),
        tostring(num(zoom, "DefaultCamDistance"))))
end

local function cmdrOn()
    openLog()
    log("")
    log("#### commander view ON ####")
    local pawn = getPawn()
    if pawn == nil then log("no pawn"); return end
    local tank = tankName(pawn)
    local saved = profiles[tank]
    if saved then
        state.off = { x = saved.x or 0, y = saved.y or 0, z = saved.z or 0 }
        log("loaded saved offset for " .. tank)
    else
        state.off = { x = 0, y = 0, z = 0 }
        log("no saved offset for " .. tank)
    end
    local arm = getPart(pawn, "FollowSpringArm")
    if arm then pcall(function() arm["TargetArmLength"] = 0.0 end) end
    pinZoom(pawn, true)
    applyOffset(pawn)
    state.on = true
end

local function cmdrOff()
    openLog()
    log("#### commander view OFF ####")
    local pawn = getPawn()
    if pawn == nil then return end
    local arm = getPart(pawn, "FollowSpringArm")
    if arm then
        pcall(function() arm["SocketOffset"] = { X = 0.0, Y = 0.0, Z = 0.0 } end)
        pcall(function() arm["TargetArmLength"] = 500.0 end)
    end
    pinZoom(pawn, false)
    state.on = false
end

local function nudge(axis, delta)
    openLog()
    local pawn = getPawn()
    if pawn == nil then log("no pawn"); return end
    state.off[axis] = (state.off[axis] or 0) + delta
    log(string.format("nudge %s %+.0f  offset now (%.0f, %.0f, %.0f)", axis, delta,
        state.off.x, state.off.y, state.off.z))
    applyOffset(pawn)
end

local function resetOffset()
    openLog()
    local pawn = getPawn()
    if pawn == nil then return end
    state.off = { x = 0, y = 0, z = 0 }
    log("offset reset to 0, 0, 0")
    applyOffset(pawn)
end

local function saveTank()
    openLog()
    local pawn = getPawn()
    if pawn == nil then log("no pawn"); return end
    local tank = tankName(pawn)
    profiles[tank] = { x = state.off.x, y = state.off.y, z = state.off.z }
    local okW = saveProfiles()
    log(string.format("SAVED %s = (%.1f, %.1f, %.1f) file=%s", tank,
        state.off.x, state.off.y, state.off.z, tostring(okW)))
end

local crewState   -- defined further down, used by report()

local function report()
    openLog()
    log("")
    log("======== REPORT ========")
    local pawn = getPawn()
    if pawn == nil then log("no pawn"); return end
    log("tank = " .. tankName(pawn))
    log("offset = " .. string.format("%.1f, %.1f, %.1f", state.off.x, state.off.y, state.off.z))
    local arm = getPart(pawn, "FollowSpringArm")
    if arm then
        log("TargetArmLength = " .. tostring(num(arm, "TargetArmLength")))
        local okS, so = pcall(function() return arm["SocketOffset"] end)
        log("SocketOffset = " .. (okS and vecStr(so) or "fail"))
    end
    local zoom = getPart(pawn, "Zoom")
    if zoom then
        log(string.format("zoom min=%s max=%s default=%s",
            tostring(num(zoom, "MinCamDistance")),
            tostring(num(zoom, "MaxCamDistance")),
            tostring(num(zoom, "DefaultCamDistance"))))
    end
    crewState("report", pawn)
    for name, p in pairs(profiles) do
        log(string.format("saved: %s = %.1f %.1f %.1f", name, p.x or 0, p.y or 0, p.z or 0))
    end
    log("======== END ========")
end

local function toggle()
    if state.on then
        cmdrOff()
    else
        cmdrOn()
    end
end

-- auto-apply the saved view whenever the player takes a vehicle
local function autoApply()
    local pawn = getPawn()
    if pawn == nil then return end
    local tank = tankName(pawn)
    if profiles[tank] == nil then return end
    openLog()
    log("auto-apply on possession: " .. tank)
    cmdrOn()
end

local hooked = pcall(function()
    RegisterHook("/Script/Panzer_Elite_2.PE2Vehicle:SetIsPossessedByPlayerController", function(Context, bPossessed)
        local yes = false
        pcall(function() yes = Context:get() end)
        if yes == true then
            -- fires on the game thread; wait a beat so components exist
            pcall(function()
                ExecuteWithDelay(1500, function()
                    pcall(function() autoApply() end)
                end)
            end)
        end
    end)
end)
if not hooked then print("[CtACmdr] possession hook not available, press F3 manually") end

-- ==== crew experiment: can we pop the commander up ourselves? ====
crewState = function(tag, pawn)
    local cmdr = getPart(pawn, "Crew_Commander")
    if cmdr ~= nil then
        local okV, vis = pcall(function() return cmdr["bVisible"] end)
        log(string.format("%s Crew_Commander.bVisible = %s", tag, tostring(okV and vis or "read failed")))
    else
        log(tag .. " no Crew_Commander")
    end
    local bino = getPart(pawn, "Binoculars")
    if bino ~= nil then
        local okS, st = pcall(function() return bino["CurrentState"] end)
        log(string.format("%s Binoculars.CurrentState = %s", tag, tostring(okS and st or "read failed")))
    end
    local arm = getPart(pawn, "FollowSpringArm")
    if arm ~= nil then
        log(string.format("%s arm length = %s", tag, tostring(num(arm, "TargetArmLength"))))
    end
end

local function crewPush(value)
    openLog()
    log("")
    log("#### OnBinocularsStateChanged(" .. tostring(value) .. ") ####")
    local pawn = getPawn()
    if pawn == nil then log("no pawn"); return end
    crewState("before", pawn)
    local cm = getPart(pawn, "CrewManager")
    if cm == nil then log("no CrewManager"); return end
    log("calling CrewManager:OnBinocularsStateChanged(" .. tostring(value) .. ")")
    local ok, err = pcall(function() return cm:OnBinocularsStateChanged(value) end)
    log("call ok=" .. tostring(ok) .. " err=" .. tostring(err))
    crewState("after", pawn)
end

-- ==== observation hooks: log what the game calls, change nothing ====
local function argDump(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        local v = select(i, ...)
        if type(v) == "userdata" then
            local okN, nm = pcall(function() return v:GetFullName() end)
            parts[#parts + 1] = okN and nm or tostring(v)
        else
            parts[#parts + 1] = tostring(v)
        end
    end
    if #parts == 0 then return "()" end
    return "(" .. table.concat(parts, ", ") .. ")"
end

local function watch(path, label)
    local ok, err = pcall(function()
        RegisterHook(path, function(Context, ...)
            -- Lua forbids '...' inside a nested closure, so pass it to pcall directly
            local okArgs, args = pcall(argDump, ...)
            if not okArgs then args = "(arg dump failed)" end
            openLog()
            local suffix = ""
            local okCtx, ctx1 = pcall(function() return Context:get() end)
            if okCtx then suffix = " ctx1=" .. tostring(ctx1) end
            local okLog, logErr = pcall(log, "[watch] " .. label .. args .. suffix)
            if not okLog then print("[CtACmdr] watch log failed: " .. tostring(logErr)) end
        end)
    end)
    if not ok then log("[watch] could not hook " .. label .. ": " .. tostring(err)) end
end

watch("/Script/Panzer_Elite_2.BinocularsComponent:StartUsingBinoculars", "binos START")
watch("/Script/Panzer_Elite_2.BinocularsComponent:StopUsingBinoculars", "binos STOP")
watch("/Script/Panzer_Elite_2.CrewManagerComponent:SetStateForAllCrewAnims", "crew SetStateForAllCrewAnims")
watch("/Script/Panzer_Elite_2.CrewManagerComponent:SetAllCrewAnimsHidden", "crew SetAllCrewAnimsHidden")
watch("/Script/Panzer_Elite_2.CrewManagerComponent:PlayCrewMemberAnimation_ByRole", "crew PlayAnimByRole")
watch("/Script/Panzer_Elite_2.CrewManagerComponent:PlayCrewMemberAnimation_ByID", "crew PlayAnimByID")
watch("/Script/Panzer_Elite_2.CrewManagerComponent:OnBinocularsStateChanged", "crew OnBinocularsStateChanged")

local function bind(key, mods, fn, label)
    local ok, err = pcall(function()
        if mods and RegisterKeyBindAsync then
            RegisterKeyBindAsync(key, mods, fn)
        else
            RegisterKeyBind(key, fn)
        end
    end)
    if not ok then print("[CtACmdr] bind failed for " .. tostring(label) .. ": " .. tostring(err)) end
end

loadProfiles()

bind(Key.F3, nil, function() toggle() end, "F3")
bind(Key.F4, nil, function() cmdrOff() end, "F4")
bind(Key.F6, nil, function() report() end, "F6")

bind(Key.NUM_EIGHT, nil, function() nudge("x", STEP) end, "num8")
bind(Key.NUM_TWO, nil, function() nudge("x", -STEP) end, "num2")
bind(Key.NUM_FOUR, nil, function() nudge("y", -STEP) end, "num4")
bind(Key.NUM_SIX, nil, function() nudge("y", STEP) end, "num6")
bind(Key.NUM_NINE, nil, function() nudge("z", STEP) end, "num9")
bind(Key.NUM_THREE, nil, function() nudge("z", -STEP) end, "num3")
bind(Key.NUM_FIVE, nil, function() resetOffset() end, "num5")
bind(Key.NUM_ZERO, nil, function() saveTank() end, "num0")


print("[CtACmdr] v1.2 loaded. Watching bino and crew calls. F3=toggle F4=normal F6=report")