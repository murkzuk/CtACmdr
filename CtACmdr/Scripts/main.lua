-- CtACmdr v1.1 : commander view for Call to Arms: Panzer Elite
-- MIT licensed, (c) 2026 murkz. See LICENSE.
--
--   F3            commander view on / off
--   F4            back to the game's normal view
--   ALT+NUM 8/2   camera forward / back
--   ALT+NUM 4/6   left / right
--   ALT+NUM 9/3   up / down
--   ALT+NUM 5     reset the offset
--   ALT+NUM 0     save this tank's position
--
-- ALT, not plain numpad: numpad navigates between units in skirmish mode.
-- ALT, not CTRL: UE4SS uses CTRL+NUM 6..9 for debug file dumps.
--   F6            write a report to CtACmdr.log
--
-- Applies itself about 1.5s after getting into a vehicle that has a saved
-- position. Nothing else is touched: no bino state, no widgets, no hooks
-- that can alter the game beyond the camera numbers below.

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

-- ---------- saved positions, one line per tank ----------
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

-- ---------- reflection helpers ----------
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

local function classname(o)
    local ok, c = pcall(function() return o:GetClass() end)
    if ok and c then return fname(c) end
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

local function getPart(pawn, name)
    local v = nil
    pcall(function() v = pawn[name] end)
    if isObj(v) then return v end
    return nil
end

-- ---------- the camera ----------
-- where a tank starts if it has no saved position yet. Tuned on a
-- PzKpfw IV; every vehicle can differ, so this is a starting point to
-- nudge from rather than a correct answer.
local DEFAULT = { x = -63.9, y = -3.0, z = -3.4 }

local state = { off = { x = DEFAULT.x, y = DEFAULT.y, z = DEFAULT.z }, on = false }

local function applyOffset(pawn)
    local arm = getPart(pawn, "FollowSpringArm")
    if arm == nil then log("  no FollowSpringArm"); return end
    local want = { X = state.off.x, Y = state.off.y, Z = state.off.z }
    pcall(function() arm["SocketOffset"] = want end)
    local okR, got = pcall(function() return arm["SocketOffset"] end)
    log(string.format("  offset (%.1f, %.1f, %.1f) -> (%s)", want.X, want.Y, want.Z,
        okR and vecStr(got) or "?"))
end

-- the zoom component rewrites the arm length every frame; zeroing the
-- min and default distances is what makes the camera stay put
local function pinZoom(pawn, on)
    local zoom = getPart(pawn, "Zoom")
    if zoom == nil then log("  no Zoom component"); return end
    if on then
        pcall(function() zoom["MinCamDistance"] = 0.0 end)
        pcall(function() zoom["DefaultCamDistance"] = 0.0 end)
        pcall(function() zoom:SetCamDistanceTarget(0.0) end)
        pcall(function() zoom["RelativeZoomCameraPitchLimit"] = 85.0 end)
        pcall(function() zoom["RelativeZoomCameraYawLimit"] = 175.0 end)
        log("  zoom pinned")
    else
        pcall(function() zoom["MinCamDistance"] = 150.0 end)
        pcall(function() zoom["MaxCamDistance"] = 800.0 end)
        pcall(function() zoom["DefaultCamDistance"] = 500.0 end)
        pcall(function() zoom:SetCamDistanceTarget(500.0) end)
        pcall(function() zoom["RelativeZoomCameraPitchLimit"] = 20.0 end)
        pcall(function() zoom["RelativeZoomCameraYawLimit"] = 45.0 end)
        log("  zoom restored")
    end
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
        state.off = { x = DEFAULT.x, y = DEFAULT.y, z = DEFAULT.z }
        log("no saved offset for " .. tank .. " - using the default, ALT+NUM to tune, ALT+NUM 0 to save")
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

local function toggle()
    if state.on then cmdrOff() else cmdrOn() end
end

local function nudge(axis, delta)
    openLog()
    local pawn = getPawn()
    if pawn == nil then log("no pawn"); return end
    state.off[axis] = (state.off[axis] or 0) + delta
    log(string.format("nudge %s %+.0f  offset (%.0f, %.0f, %.0f)", axis, delta,
        state.off.x, state.off.y, state.off.z))
    applyOffset(pawn)
end

local function resetOffset()
    openLog()
    local pawn = getPawn()
    if pawn == nil then return end
    state.off = { x = 0, y = 0, z = 0 }
    log("offset reset")
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

local function report()
    openLog()
    log("")
    log("#### report ####")
    local pawn = getPawn()
    if pawn == nil then log("no pawn"); return end
    log("tank = " .. tankName(pawn))
    log("offset = " .. string.format("%.1f, %.1f, %.1f", state.off.x, state.off.y, state.off.z))
    local arm = getPart(pawn, "FollowSpringArm")
    if arm then
        log("arm length = " .. tostring(num(arm, "TargetArmLength")))
        local okS, so = pcall(function() return arm["SocketOffset"] end)
        log("socket offset = " .. (okS and vecStr(so) or "?"))
    end
    local zoom = getPart(pawn, "Zoom")
    if zoom then
        log(string.format("zoom min=%s max=%s default=%s",
            tostring(num(zoom, "MinCamDistance")),
            tostring(num(zoom, "MaxCamDistance")),
            tostring(num(zoom, "DefaultCamDistance"))))
    end
    for name, p in pairs(profiles) do
        log(string.format("saved: %s = %.1f %.1f %.1f", name, p.x or 0, p.y or 0, p.z or 0))
    end
    log("#### end ####")
end

-- ---------- apply automatically when getting into a known vehicle ----------
local function autoApply()
    local pawn = getPawn()
    if pawn == nil then return end
    if profiles[tankName(pawn)] == nil then return end
    openLog()
    log("auto-apply on possession: " .. tankName(pawn))
    cmdrOn()
end

pcall(function()
    RegisterHook("/Script/Panzer_Elite_2.PE2Vehicle:SetIsPossessedByPlayerController", function(Context, ...)
        local n = select("#", ...)
        local p1 = nil
        if n >= 1 then p1 = (select(1, ...)) end
        local yes = false
        pcall(function() yes = p1:get() end)
        if yes == true then
            pcall(function()
                ExecuteWithDelay(1500, function() pcall(autoApply) end)
            end)
        end
    end)
end)

-- ---------- keys ----------
local function bind(key, mods, fn, label)
    local guarded = function()
        local ok, err = pcall(fn)
        if not ok then
            openLog()
            log("[ERROR] " .. tostring(label) .. ": " .. tostring(err))
        end
    end
    local ok = pcall(function()
        if mods and RegisterKeyBindAsync then
            RegisterKeyBindAsync(key, mods, guarded)
        else
            RegisterKeyBind(key, guarded)
        end
    end)
    if not ok then print("[CtACmdr] could not bind " .. tostring(label)) end
end

loadProfiles()

bind(Key.F3, nil, toggle, "F3")
bind(Key.F4, nil, cmdrOff, "F4")
bind(Key.F6, nil, report, "F6")
local ALT = { ModifierKey.ALT }
if ModifierKey.ALT == nil then print("[CtACmdr] WARNING: ModifierKey.ALT missing, camera keys will not work") end

bind(Key.NUM_EIGHT, ALT, function() nudge("x", STEP) end, "alt+num8")
bind(Key.NUM_TWO, ALT, function() nudge("x", -STEP) end, "alt+num2")
bind(Key.NUM_FOUR, ALT, function() nudge("y", -STEP) end, "alt+num4")
bind(Key.NUM_SIX, ALT, function() nudge("y", STEP) end, "alt+num6")
bind(Key.NUM_NINE, ALT, function() nudge("z", STEP) end, "alt+num9")
bind(Key.NUM_THREE, ALT, function() nudge("z", -STEP) end, "alt+num3")
bind(Key.NUM_FIVE, ALT, resetOffset, "alt+num5")
bind(Key.NUM_ZERO, ALT, saveTank, "alt+num0")

print("[CtACmdr] v1.3 loaded. F3=commander view F4=normal ALT+NUM=move ALT+NUM0=save F6=report")
