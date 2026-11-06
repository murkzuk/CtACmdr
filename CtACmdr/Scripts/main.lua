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
-- hook params arrive as RemoteUnrealParam handles; :get() reads the value
local function resolveParam(v)
    if type(v) ~= "userdata" then return tostring(v) end
    local ok, val = pcall(function() return v:get() end)
    if ok and val ~= nil and type(val) ~= "userdata" then
        return tostring(val)
    end
    if ok and type(val) == "userdata" then
        local okN, nm = pcall(function() return val:GetFullName() end)
        if okN and nm then return "<" .. tostring(nm) .. ">" end
        return "object"
    end
    local okN, nm = pcall(function() return v:GetFullName() end)
    if okN and nm then return "<" .. tostring(nm) .. ">" end
    return "param"
end

local function argDump(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        parts[#parts + 1] = resolveParam((select(i, ...)))
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

-- ==== the brake: refuse to let him duck back in ====
local keepUp = false

local brakeOk = pcall(function()
    RegisterHook("/Script/Panzer_Elite_2.BinocularsComponent:StopUsingBinoculars", function(Context, ...)
        local okArgs, args = pcall(argDump, ...)
        openLog()
        local held = "no"
        if keepUp then held = "yes" end
        pcall(log, "[brake] StopUsingBinoculars " .. (okArgs and args or "?") .. " hold=" .. held)
        -- do NOT block here: the optics must return to normal.
        -- the crew notification is the thing to stop, hooked below.
    end)
end)
if not brakeOk then print("[CtACmdr] brake hook failed") end

-- this is the one that matters: EBinocularsState 0 = None = duck back in
local crewBrakeOk = pcall(function()
    RegisterHook("/Script/Panzer_Elite_2.CrewManagerComponent:OnBinocularsStateChanged", function(Context, ...)
        local n = select("#", ...)
        local p1 = nil
        if n >= 1 then p1 = (select(1, ...)) end
        local valStr = resolveParam(p1)
        local num = tonumber(valStr)
        openLog()
        pcall(log, "[brake] crew notified state=" .. valStr .. " hold=" .. tostring(keepUp))
        if keepUp and num == 0 then
            pcall(log, "[brake] swallowed - commander stays up")
            return true   -- the crew manager never hears "duck down"
        end
    end)
end)
if not crewBrakeOk then print("[CtACmdr] crew brake hook failed") end

local function toggleBrake()
    openLog()
    keepUp = not keepUp
    log("[brake] keep commander up = " .. tostring(keepUp))
end

-- ==== flatten the bino lens: normal FOV, no mask ====
-- Only scalar properties are read. Reading a null object property is fatal
-- on this build, so textures and materials are listed but never touched.
local SCALAR = {
    FloatProperty = true, DoubleProperty = true, BoolProperty = true,
    IntProperty = true, ByteProperty = true, EnumProperty = true,
    NameProperty = true, StrProperty = true
}

local function flattenBinos()
    openLog()
    log("")
    log("#### flatten binos ####")
    local pawn = getPawn()
    if pawn == nil then log("no pawn"); return end
    local bino = getPart(pawn, "Binoculars")
    if bino == nil then log("no Binoculars component"); return end
    local setup = nil
    pcall(function() setup = bino["Setup"] end)
    if not isObj(setup) then log("no Setup asset"); return end
    log("Setup = " .. fullname(setup))
    log("class = " .. classname(setup))

    local cls = nil
    pcall(function() cls = setup:GetClass() end)
    if cls == nil then log("no class"); return end

    pcall(function()
        cls:ForEachProperty(function(prop)
            local n = fname(prop)
            local tn = classname(prop)
            if not SCALAR[tn] then
                log(string.format("  %-36s %-16s (not read)", n, tn))
                return
            end
            local okV, val = pcall(function() return setup[n] end)
            log(string.format("  %-36s %-16s = %s", n, tn, tostring(okV and val or "read failed")))

            local low = string.lower(n)
            local target = nil
            if tn == "FloatProperty" or tn == "DoubleProperty" then
                if string.find(low, "fov", 1, true) or string.find(low, "fieldofview", 1, true) then
                    target = 90.0
                elseif string.find(low, "postprocess", 1, true) or string.find(low, "vignette", 1, true)
                    or string.find(low, "mask", 1, true) or string.find(low, "strength", 1, true)
                    or string.find(low, "opacity", 1, true) or string.find(low, "alpha", 1, true) then
                    target = 0.0
                elseif string.find(low, "magnification", 1, true) then
                    target = 1.0
                end
            end
            if target ~= nil then
                local okW = pcall(function() setup[n] = target end)
                local okA, after = pcall(function() return setup[n] end)
                log(string.format("   -> wrote %s = %s  ok=%s  now=%s", n, tostring(target),
                    tostring(okW), tostring(okA and after or "?")))
            end
        end)
    end)
    log("#### end ####")
end

-- ==== inspect: what does the bino camera actually consist of? ====
-- Names and types only. No object property is ever read, because a null
-- object read is what crashes this build.
local function inspectBinos()
    openLog()
    log("")
    log("#### inspect binos ####")
    local pawn = getPawn()
    if pawn == nil then log("no pawn"); return end
    local bino = getPart(pawn, "Binoculars")
    if bino == nil then log("no Binoculars component"); return end

    local st = nil
    pcall(function() st = bino["CurrentState"] end)
    log("CurrentState = " .. tostring(st) .. "   (1 = binos up)")

    local setup = nil
    pcall(function() setup = bino["Setup"] end)
    if isObj(setup) then
        local scls = nil
        pcall(function() scls = setup:GetClass() end)
        if scls then
            log("-- setup struct layouts --")
            pcall(function()
                scls:ForEachProperty(function(prop)
                    local tn = classname(prop)
                    if tn ~= "StructProperty" then return end
                    local pn = fname(prop)
                    log("  " .. pn)
                    local stype = nil
                    pcall(function() stype = prop:GetStruct() end)
                    if stype then
                        pcall(function()
                            stype:ForEachProperty(function(f)
                                log(string.format("      %-30s %s", fname(f), classname(f)))
                            end)
                        end)
                    end
                end)
            end)
        end
    end

    local cam = nil
    pcall(function() cam = bino["CurrentCameraActor"] end)
    if isObj(cam) then
        log("-- bino camera actor --")
        log("  " .. fullname(cam))
        log("  class = " .. classname(cam))
        local ccls = nil
        pcall(function() ccls = cam:GetClass() end)
        if ccls then
            pcall(function()
                ccls:ForEachProperty(function(p)
                    log(string.format("     %-34s %s", fname(p), classname(p)))
                end)
            end)
        end
    else
        log("-- no camera actor yet (raise the binos and press again) --")
    end
    log("#### end ####")
end

-- ==== strip the lens: keep the bino camera, drop the FOV and the mask ====
-- Uses only properties confirmed to exist on the bino camera actor.
local function stripLens()
    openLog()
    log("")
    log("#### strip bino lens ####")
    local pawn = getPawn()
    if pawn == nil then log("no pawn"); return end
    local bino = getPart(pawn, "Binoculars")
    if bino == nil then log("no Binoculars component"); return end

    local cam = nil
    pcall(function() cam = bino["CurrentCameraActor"] end)
    if not isObj(cam) then
        log("no camera actor - raise the binos first, then press again")
        return
    end
    log("actor  = " .. fullname(cam))

    local cc = nil
    pcall(function() cc = cam["Camera"] end)
    if not isObj(cc) then log("no Camera component on the actor"); return end
    log("camera = " .. fullname(cc))

    local fovBefore = num(cc, "FieldOfView")
    local okFov = pcall(function() cc["FieldOfView"] = 90.0 end)
    log(string.format("FieldOfView            %s -> %s   write=%s",
        tostring(fovBefore), tostring(num(cc, "FieldOfView")), tostring(okFov)))

    local ppBefore = num(cc, "PostProcessBlendWeight")
    local okPP = pcall(function() cc["PostProcessBlendWeight"] = 0.0 end)
    log(string.format("PostProcessBlendWeight %s -> %s   write=%s",
        tostring(ppBefore), tostring(num(cc, "PostProcessBlendWeight")), tostring(okPP)))

    log("#### end ####")
end

-- ==== hold the lens stripped ====
-- The bino component animates FieldOfView and PostProcessBlendWeight from
-- VignetteCurve / CrossFadeCurve every frame, so a single write is undone.
-- This re-asserts the values on a timer while the hold is on.
local stripOn = false

local function stripTick()
    if not stripOn then return end
    local pawn = getPawn()
    if pawn == nil then return end
    local bino = getPart(pawn, "Binoculars")
    if bino == nil then return end

    -- never touch CurrentCameraActor unless the binos are actually up:
    -- reading a null object property is fatal on this build
    local st = nil
    pcall(function() st = bino["CurrentState"] end)
    if st ~= 1 then return end

    local cam = nil
    pcall(function() cam = bino["CurrentCameraActor"] end)
    if not isObj(cam) then return end
    local cc = nil
    pcall(function() cc = cam["Camera"] end)
    if not isObj(cc) then return end

    pcall(function() cc["FieldOfView"] = 90.0 end)
    pcall(function() cc["PostProcessBlendWeight"] = 0.0 end)
end

local function toggleStrip()
    openLog()
    stripOn = not stripOn
    log("[strip] holding lens off = " .. tostring(stripOn))
    if stripOn then pcall(stripTick) end
end

LoopAsync(60, function() pcall(stripTick) end)

-- ==== kill the bino post-process mask ====
-- The mask is M_PP_Binoculars_basic, applied by a post-process component.
-- Camera PostProcessBlendWeight being zeroed did nothing, so the post
-- process is coming from its own component on the bino camera actor.
local function killMask()
    openLog()
    log("")
    log("#### kill bino mask ####")
    local pawn = getPawn()
    if pawn == nil then log("no pawn"); return end
    local bino = getPart(pawn, "Binoculars")
    if bino == nil then log("no Binoculars component"); return end

    local cam = nil
    pcall(function() cam = bino["CurrentCameraActor"] end)
    if not isObj(cam) then log("no camera actor - raise the binos first"); return end
    local camPath = fullname(cam)
    log("bino actor = " .. camPath)

    local found, disabled = 0, 0
    local ppList = nil
    pcall(function() ppList = FindAllOf("PostProcessComponent") end)
    if ppList then
        for _, c in ipairs(ppList) do
            local path = fullname(c)
            if string.find(path, camPath, 1, true) then
                found = found + 1
                local bwBefore = num(c, "BlendWeight")
                local enBefore = nil
                pcall(function() enBefore = c["bEnabled"] end)
                local okW1 = pcall(function() c["BlendWeight"] = 0.0 end)
                local okW2 = pcall(function() c["bEnabled"] = false end)
                local bwAfter = num(c, "BlendWeight")
                local enAfter = nil
                pcall(function() enAfter = c["bEnabled"] end)
                log(string.format("  %s", path))
                log(string.format("     BlendWeight %s -> %s  (write=%s)", tostring(bwBefore), tostring(bwAfter), tostring(okW1)))
                log(string.format("     bEnabled    %s -> %s  (write=%s)", tostring(enBefore), tostring(enAfter), tostring(okW2)))
                disabled = disabled + 1
            end
        end
    end
    log(string.format("post process components on this actor: %d", found))
    if found == 0 then
        log("none found - listing every post process actor/volume with 'binoc' in the name")
        local vols = nil
        pcall(function() vols = FindAllOf("PostProcessVolume") end)
        if vols then
            for _, v in ipairs(vols) do
                local p = fullname(v)
                if string.find(string.lower(p), "binoc", 1, true) then log("  volume: " .. p) end
            end
        end
    end
    log("#### end ####")
end

local function bind(key, mods, fn, label)
    local guarded = function()
        local ok, err = pcall(fn)
        if not ok then
            openLog()
            log("[ERROR] " .. tostring(label) .. ": " .. tostring(err))
        end
    end
    local ok, err = pcall(function()
        if mods and RegisterKeyBindAsync then
            RegisterKeyBindAsync(key, mods, guarded)
        else
            RegisterKeyBind(key, guarded)
        end
    end)
    if not ok then print("[CtACmdr] bind failed for " .. tostring(label) .. ": " .. tostring(err)) end
end

loadProfiles()

bind(Key.F3, nil, function() toggle() end, "F3")
bind(Key.F2, nil, function() toggleBrake() end, "F2")
bind(Key.F1, nil, function() flattenBinos() end, "F1")
bind(Key.F7, nil, function() inspectBinos() end, "F7")
bind(Key.F8, nil, function() stripLens() end, "F8")
bind(Key.F9, nil, function() toggleStrip() end, "F9")
bind(Key.F5, nil, function() killMask() end, "F5")
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


print("[CtACmdr] v1.9 loaded. F5=kill mask F9=hold lens F8=strip F3=cmdr F4=normal F6=report")