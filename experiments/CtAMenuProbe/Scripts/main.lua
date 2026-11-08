-- CtAMenuProbe v2 : does ModMenu work IN GAMEPLAY, and can we always recover?
--
--   F5 = open / close the panel. Closing always forces the game back to
--        normal mouse-look input afterwards, whatever ModMenu did.
--   F6 = panic. Force the game back to normal input, no matter what state
--        it is in. Use this if the game feels frozen or unclickable.
--
-- Our keybinds go through UE4SS, not the game's input, so F6 still works
-- even when the game itself has stopped responding to the mouse.

local OUT = "CtAMenuProbe.log"

local function log(m)
    print("[CtAMenuProbe] " .. tostring(m))
    local h = io.open(OUT, "a")
    if h then h:write(tostring(m) .. "\n"); h:flush(); h:close() end
end

local function getPC()
    local list = nil
    pcall(function() list = FindAllOf("PlayerController") end)
    if not list then return nil end
    for _, p in ipairs(list) do
        local valid = false
        pcall(function() valid = p:IsValid() end)
        if valid and not string.find(p:GetFullName(), "Default__", 1, true) then return p end
    end
    return nil
end

-- Put the game back to plain mouse-look, the way ModMenu itself does it.
local function restoreGameInput(tag)
    local pc = getPC()
    if pc == nil then log("  [" .. tag .. "] no PlayerController"); return end

    local lib = nil
    pcall(function() lib = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end)
    if lib ~= nil then
        -- UE5 signature takes a trailing bFlushInput; fall back if it refuses
        local ok = pcall(function() lib:SetInputMode_GameOnly(pc, false) end)
        if not ok then ok = pcall(function() lib:SetInputMode_GameOnly(pc) end) end
        log("  [" .. tag .. "] SetInputMode_GameOnly ok=" .. tostring(ok))
    else
        log("  [" .. tag .. "] no WidgetBlueprintLibrary")
    end

    pcall(function() pc.bShowMouseCursor = false end)
    pcall(function() pc:SetIgnoreLookInput(false) end)
    pcall(function() pc:SetIgnoreMoveInput(false) end)
    log("  [" .. tag .. "] cursor off, look and move released")
end

log("=== probe v2 start ===")
local okReq, ModMenu = pcall(require, "ModMenu.ModMenu")
log("require ok=" .. tostring(okReq) .. " type=" .. type(ModMenu))
if not okReq or type(ModMenu) ~= "table" then return end

local okInit, errInit = pcall(function()
    ModMenu.Init({
        title = "CtACmdr probe",
        instanceId = "CtAMenuProbe",
        theme = "dark",
        key = Key.F5,
        keyHint = "F5",
        dock = "left",
        debug = true,        -- traces into the UE4SS log
        ignoreLook = true,   -- this is a mouse-look game
    })
end)
log("Init ok=" .. tostring(okInit) .. " err=" .. tostring(errInit))

local okReg, errReg = pcall(function()
    ModMenu.Register({
        id = "probe",
        title = "Probe",
        items = {
            { type = "label", id = "status", label = "not opened yet" },
            { type = "checkbox", id = "toggle", label = "Test checkbox", default = false,
              onChange = function(v) log("checkbox changed to " .. tostring(v)) end },
            { type = "button", id = "press", label = "Press me", variant = "primary",
              onPress = function()
                  log("button pressed")
                  pcall(function() ModMenu.SetLabel("probe", "status", "button pressed") end)
              end },
        },
    })
end)
log("Register ok=" .. tostring(okReg) .. " err=" .. tostring(errReg))

local opened = false

local function setStatus(t)
    pcall(function() ModMenu.SetLabel("probe", "status", tostring(t)) end)
end

RegisterKeyBind(Key.F5, function()
    local ok, err = pcall(function()
        if not opened then
            ModMenu.Open()
            opened = true
            log("menu OPEN")
            setStatus("open - F5 close, F6 panic")
        else
            ModMenu.Close()
            opened = false
            log("menu CLOSED")
            -- give ModMenu a moment, then take the game's input back ourselves
            ExecuteWithDelay(150, function() restoreGameInput("after-close") end)
        end
    end)
    if not ok then log("F5 failed: " .. tostring(err)) end
end)

RegisterKeyBind(Key.F6, function()
    log("PANIC requested")
    pcall(function() ModMenu.Close() end)
    opened = false
    ExecuteInGameThread(function()
        ExecuteWithDelay(100, function() restoreGameInput("panic") end)
    end)
end)

log("=== probe v2 ready : F5 panel, F6 panic ===")