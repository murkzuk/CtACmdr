-- CtACmdr v1.8 : commander view for Call to Arms: Panzer Elite
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

local function readProfilesFrom(path)
    local ok, h = pcall(io.open, path, "r")
    if not ok or not h then return false end
    pcall(function()
        for line in h:lines() do
            local name, x, y, z = string.match(line, "^%s*([%w_%-%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
            if name then
                profiles[name] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
            end
        end
    end)
    pcall(function() h:close() end)
    return true
end

local function loadProfiles()
    profiles = {}
    -- the .bak is what a failed save leaves behind
    if not readProfilesFrom(SAVE) then
        readProfilesFrom(SAVE .. ".bak")
    end
end

-- Write to a temp file first, then swap it in. Truncating the real file
-- before writing would lose every saved tank if the game died mid-write.
local function saveProfiles()
    local tmp = SAVE .. ".tmp"
    local bak = SAVE .. ".bak"

    local okOpen, h = pcall(io.open, tmp, "w")
    if not okOpen or not h then return false end

    local okWrite = pcall(function()
        h:write("# CtACmdr per-tank camera offsets: class x y z\n")
        for name, p in pairs(profiles) do
            h:write(string.format("%s %.2f %.2f %.2f\n", name, p.x or 0, p.y or 0, p.z or 0))
        end
        h:flush()
        h:close()
    end)
    if not okWrite then
        pcall(function() h:close() end)
        pcall(function() os.remove(tmp) end)
        return false
    end

    -- keep the previous good file as a backup
    pcall(function() os.remove(bak) end)
    pcall(function() os.rename(SAVE, bak) end)

    -- os.rename returns nil plus a message on failure; it does not raise,
    -- so pcall alone always looks like success
    local callOk, renamed = pcall(function() return os.rename(tmp, SAVE) end)
    if (not callOk) or (renamed == nil) then
        -- put the previous file back so nothing is lost
        pcall(function() os.rename(bak, SAVE) end)
        pcall(function() os.remove(tmp) end)
        return false
    end
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
            if isObj(temp) then
                -- a stale or null pawn would be read further down, and a
                -- null object read is fatal on this build
                local pv = false
                pcall(function() pv = temp:IsValid() end)
                if pv then return temp end
            end
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
    if isObj(v) then
        local ok = false
        pcall(function() ok = v:IsValid() end)
        if ok then return v end
    end
    return nil
end

-- Reading a property name that does not exist is fatal on this build, so
-- never touch vehicle properties on a pawn that is not a vehicle.
local vehicleClass = nil
pcall(function() vehicleClass = StaticFindObject("/Script/Panzer_Elite_2.PE2Vehicle") end)

local vehicleCheckWarned = false

local function isVehicle(pawn)
    if pawn == nil then return false end
    if vehicleClass ~= nil then
        local ok, res = pcall(function() return pawn:IsA(vehicleClass) end)
        if ok and res ~= nil then return res end
    end
    if not vehicleCheckWarned then
        vehicleCheckWarned = true
        openLog()
        log("[WARN] could not check the pawn class with IsA. Allowing the pawn through,")
        log("       which is what older versions did. A dismounted pawn may then")
        log("       trip a property read, so check UE4SS.log if the game freezes.")
    end
    -- Deliberately permissive: guessing from the class name would reject a
    -- tank like BP_PzKpfwIVAusfG_C, which contains neither word, and then the
    -- mod would silently do nothing at all.
    return true
end

local function getVehicle()
    local pawn = getPawn()
    if pawn == nil then return nil end
    if not isVehicle(pawn) then
        openLog()
        log("  pawn is not a vehicle: " .. fullname(pawn))
        return nil
    end
    return pawn
end

-- ---------- the camera ----------
-- where a tank starts if it has no saved position yet. Tuned on a
-- PzKpfw IV; every vehicle can differ, so this is a starting point to
-- nudge from rather than a correct answer.
local DEFAULT = { x = -63.9, y = -3.0, z = -3.4 }

-- Assigned further down if ModMenu is available. Forward declared so the
-- action functions can refresh the panel without knowing whether it exists.
local syncPanel = function() end

local state = { off = { x = DEFAULT.x, y = DEFAULT.y, z = DEFAULT.z }, on = false }

-- Originals are kept per vehicle, keyed by the pawn's full name, and are
-- recorded BEFORE anything is written. A vehicle that is already pinned is
-- never recorded, because its current values are ours, not the game's.
local originals = {}
local pinned = {}
local lastPinned = nil

local function recordOriginals(pawn)
    local key = fullname(pawn)
    if originals[key] ~= nil then return originals[key] end
    if pinned[key] then
        log("  already pinned, keeping the values recorded earlier")
        return nil
    end
    local o = {}
    local zoom = getPart(pawn, "Zoom")
    if zoom ~= nil then
        for _, f in ipairs({ "MinCamDistance", "MaxCamDistance", "DefaultCamDistance",
                             "RelativeZoomCameraPitchLimit", "RelativeZoomCameraYawLimit" }) do
            local v = num(zoom, f)
            if v ~= nil then o[f] = v end
        end
    end
    local arm = getPart(pawn, "FollowSpringArm")
    if arm ~= nil then
        local a = num(arm, "TargetArmLength")
        if a ~= nil then o.arm = a end
    end
    originals[key] = o
    log(string.format("  recorded this vehicle's own values (arm=%s min=%s)",
        tostring(o.arm), tostring(o.MinCamDistance)))
    return o
end

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
        local o = originals[fullname(pawn)]
        if o == nil then
            log("  nothing recorded for this vehicle, leaving zoom alone")
            return
        end
        local function restore(field)
            local v = o[field]
            if v ~= nil then pcall(function() zoom[field] = v end) end
        end
        restore("MinCamDistance")
        restore("MaxCamDistance")
        restore("DefaultCamDistance")
        restore("RelativeZoomCameraPitchLimit")
        restore("RelativeZoomCameraYawLimit")
        if o.DefaultCamDistance ~= nil then
            pcall(function() zoom:SetCamDistanceTarget(o.DefaultCamDistance) end)
        end
        log("  zoom restored to this vehicle's own values")
    end
end

local function cmdrOn()
    openLog()
    log("")
    log("#### commander view ON ####")
    local pawn = getVehicle()
    if pawn == nil then log("no vehicle"); return end
    recordOriginals(pawn)        -- BEFORE any write, or we record our own numbers
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
    state.tank = tank
    pinned[fullname(pawn)] = true
    lastPinned = pawn
    pcall(syncPanel)
end

local function cmdrOff(target)
    openLog()
    log("#### commander view OFF ####")
    local pawn = target or getVehicle()
    if pawn == nil then return end
    local key = fullname(pawn)
    local o = originals[key]
    if o == nil then
        log("  nothing was changed on this vehicle, leaving it alone")
        state.on = false
        return
    end
    local arm = getPart(pawn, "FollowSpringArm")
    if arm then
        pcall(function() arm["SocketOffset"] = { X = 0.0, Y = 0.0, Z = 0.0 } end)
        if o.arm ~= nil then pcall(function() arm["TargetArmLength"] = o.arm end) end
    end
    pinZoom(pawn, false)
    pinned[key] = nil
    state.on = false
    if lastPinned == pawn then lastPinned = nil end
    pcall(syncPanel)
end

local function toggle()
    if state.on then cmdrOff() else cmdrOn() end
end

local function nudge(axis, delta)
    openLog()
    if not state.on then
        log("commander view is off - press F3 first, nudging now would move the normal camera")
        return
    end
    local pawn = getVehicle()
    if pawn == nil then log("no pawn"); return end
    state.off[axis] = (state.off[axis] or 0) + delta
    log(string.format("nudge %s %+.0f  offset (%.0f, %.0f, %.0f)", axis, delta,
        state.off.x, state.off.y, state.off.z))
    applyOffset(pawn)
    pcall(syncPanel)
end

local function resetOffset()
    openLog()
    local pawn = getVehicle()
    if pawn == nil then return end
    state.off = { x = 0, y = 0, z = 0 }
    log("offset reset")
    applyOffset(pawn)
    pcall(syncPanel)
end

local function saveTank()
    openLog()
    local pawn = getVehicle()
    if pawn == nil then log("no pawn"); return end
    local tank = tankName(pawn)
    if state.tank ~= nil and state.tank ~= tank then
        log("this position was tuned in " .. tostring(state.tank) ..
            ", not in " .. tank .. " - press F3 here first, then save")
        return
    end
    profiles[tank] = { x = state.off.x, y = state.off.y, z = state.off.z }
    local okW = saveProfiles()
    log(string.format("SAVED %s = (%.1f, %.1f, %.1f) file=%s", tank,
        state.off.x, state.off.y, state.off.z, tostring(okW)))
    pcall(syncPanel)
end

local function report()
    openLog()
    log("")
    log("#### report ####")
    local pawn = getVehicle()
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
    -- hand the vehicle we left its own values back first
    if lastPinned ~= nil then
        local stillThere = false
        pcall(function() stillThere = lastPinned:IsValid() end)
        if stillThere then
            log("restoring the vehicle we left")
            cmdrOff(lastPinned)
        end
        lastPinned = nil
    end
    state.on = false
    local pawn = getVehicle()
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

-- ---------- in-game panel (optional, needs ModMenu) ----------
-- ModMenu is a shared library, not an enabled mod. If it is not installed
-- the mod works exactly as before, on keys only.
local MenuOpen = false

local function getPanelPC()
    local list = nil
    pcall(function() list = FindAllOf("PlayerController") end)
    if not list then return nil end
    for _, p in ipairs(list) do
        local valid = false
        pcall(function() valid = p:IsValid() end)
        if valid and not string.find(fullname(p), "Default__", 1, true) then return p end
    end
    return nil
end

-- Hand the game back to plain mouse-look. ModMenu restores input on close,
-- but this game fights for the mouse, so we do it ourselves as well.
local function restoreGameInput(tag)
    local pc = getPanelPC()
    if pc == nil then return end
    local lib = nil
    pcall(function() lib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end)
    if lib ~= nil then
        local ok = pcall(function() lib:SetInputMode_GameOnly(pc, false) end)
        if not ok then pcall(function() lib:SetInputMode_GameOnly(pc) end) end
    end
    pcall(function() pc.bShowMouseCursor = false end)
    pcall(function() pc:SetIgnoreLookInput(false) end)
    pcall(function() pc:SetIgnoreMoveInput(false) end)
    log("  input restored (" .. tostring(tag) .. ")")
end

openLog()
local okReq, ModMenu = pcall(require, "ModMenu.ModMenu")
if okReq and type(ModMenu) == "table" then
    local okInit = pcall(function()
        ModMenu.Init({
            title = "CtACmdr",
            instanceId = "CtACmdr",
            theme = "dark",
            keyHint = "F5",
            dock = "left",
            ignoreLook = true,
        })
    end)
    log("panel: ModMenu ready=" .. tostring(okInit))

    local okReg = pcall(function()
        ModMenu.Register({
            id = "cmdr",
            title = "Commander view",
            items = {
                { type = "checkbox", id = "on", label = "Commander view", default = false,
                  onChange = function(v)
                      if v then cmdrOn() else cmdrOff() end
                      log("panel: view " .. (v and "on" or "off"))
                  end },
                { type = "label", id = "tank", label = "tank: -" },
                { type = "label", id = "status", label = "F5 closes, F6 is the way out" },
                { type = "separator" },
                { type = "number", id = "ox", label = "Offset X (cm)", default = state.off.x, integer = true, min = -600, max = 600,
                  onChange = function(v) state.off.x = v; local p = getVehicle(); if p then applyOffset(p) end; pcall(syncPanel) end },
                { type = "number", id = "oy", label = "Offset Y (cm)", default = state.off.y, integer = true, min = -600, max = 600,
                  onChange = function(v) state.off.y = v; local p = getVehicle(); if p then applyOffset(p) end; pcall(syncPanel) end },
                { type = "number", id = "oz", label = "Offset Z (cm)", default = state.off.z, integer = true, min = -600, max = 600,
                  onChange = function(v) state.off.z = v; local p = getVehicle(); if p then applyOffset(p) end; pcall(syncPanel) end },
                { type = "row", items = {
                    { type = "button", id = "back", label = "Back off 5", onPress = function() nudge("x", -STEP) end },
                    { type = "button", id = "raise", label = "Raise 5", onPress = function() nudge("z", STEP) end },
                } },
                { type = "row", items = {
                    { type = "button", id = "reset", label = "Reset", variant = "warning", onPress = function() resetOffset() end },
                    { type = "button", id = "save", label = "Save this tank", variant = "primary", onPress = function() saveTank() end },
                } },
            },
        })
    end)
    log("panel: section registered=" .. tostring(okReg))

    -- our own key, so the close path is ours and the restore always runs
    RegisterKeyBind(Key.F5, function()
        local ok, err = pcall(function()
            if not MenuOpen then
                ModMenu.Open()
                MenuOpen = true
                log("panel OPEN")
            else
                ModMenu.Close()
                MenuOpen = false
                log("panel CLOSED")
                ExecuteWithDelay(150, function() restoreGameInput("after-close") end)
            end
            pcall(syncPanel)
        end)
        if not ok then log("F5 failed: " .. tostring(err)) end
    end)

    -- panic: works even when the game ignores the mouse, because UE4SS
    -- keybinds do not go through the game's input
    RegisterKeyBind(Key.F6, function()
        log("PANIC")
        pcall(function() ModMenu.Close() end)
        MenuOpen = false
        ExecuteInGameThread(function()
            ExecuteWithDelay(100, function() restoreGameInput("panic") end)
        end)
    end)

    syncPanel = function()
        pcall(function()
            local pawn = getVehicle()
            ModMenu.Set("cmdr", "on", state.on == true)
            ModMenu.Set("cmdr", "ox", math.floor((state.off.x or 0) + 0.5))
            ModMenu.Set("cmdr", "oy", math.floor((state.off.y or 0) + 0.5))
            ModMenu.Set("cmdr", "oz", math.floor((state.off.z or 0) + 0.5))
            if pawn ~= nil then
                ModMenu.SetLabel("cmdr", "tank", "tank: " .. tankName(pawn))
            end
        end)
    end
else
    log("panel: ModMenu not found, keys only. Install ModMenu into ue4ss/Mods/shared to get the panel.")
end

-- ---------- keys ----------
local function bind(key, mods, fn, label)
    local guarded = function()
        local ok, err = pcall(fn)
        if not ok then
            openLog()
            log("[ERROR] " .. tostring(label) .. ": " .. tostring(err))
        end
    end
    local ok, err = pcall(function()
        if mods then
            -- never fall back to a bare bind: plain numpad also drives unit
            -- selection in skirmish, so a missing modifier is worse than no key
            if RegisterKeyBindAsync == nil then
                error("RegisterKeyBindAsync missing, cannot bind a modified key", 0)
            end
            RegisterKeyBindAsync(key, mods, guarded)
        else
            RegisterKeyBind(key, guarded)
        end
    end)
    if not ok then
        openLog()
        log("[ERROR] could not bind " .. tostring(label) .. ": " .. tostring(err))
    end
end

loadProfiles()

bind(Key.F3, nil, toggle, "F3")
bind(Key.F4, nil, cmdrOff, "F4")
bind(Key.F6, nil, report, "F6")
local ALT = { ModifierKey.ALT }
local haveALT = (ModifierKey.ALT ~= nil)
if not haveALT then
    openLog()
    log("[ERROR] this UE4SS build has no ModifierKey.ALT, so the camera move keys cannot be bound.")
    log("        F3 and F4 still work. Report it and a plain-key fallback can be added.")
end

if haveALT then
    bind(Key.NUM_EIGHT, ALT, function() nudge("x", STEP) end, "alt+num8")
    bind(Key.NUM_TWO, ALT, function() nudge("x", -STEP) end, "alt+num2")
    bind(Key.NUM_FOUR, ALT, function() nudge("y", -STEP) end, "alt+num4")
    bind(Key.NUM_SIX, ALT, function() nudge("y", STEP) end, "alt+num6")
    bind(Key.NUM_NINE, ALT, function() nudge("z", STEP) end, "alt+num9")
    bind(Key.NUM_THREE, ALT, function() nudge("z", -STEP) end, "alt+num3")
    bind(Key.NUM_FIVE, ALT, resetOffset, "alt+num5")
    bind(Key.NUM_ZERO, ALT, saveTank, "alt+num0")
end

print("[CtACmdr] v1.8 loaded. F3=commander view F4=normal ALT+NUM=move ALT+NUM0=save F6=report")