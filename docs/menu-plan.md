# Plan: an in-game menu for the commander view

Instead of function keys and a numpad: one panel, in the game.
Everything below is checked against ModMenu's own source and README.

---

## The framework

**mattdavida/ue4ss-ModMenu** - MIT, (c) 2026 Matthew Arvidson.

| Fact | Value |
| --- | --- |
| Latest release | v1.4.0 - `ModMenu.zip` 52 KB, plus `SHA256SUMS.txt` |
| Installed at | `ue4ss/Mods/shared/ModMenu` |
| Kind | a `require`d library, **not** an enabled mod of its own |
| Loaded with | `local ModMenu = require("ModMenu.ModMenu")` |

Widget types, from `widgets/`: `button, checkbox, dropdown, fold, label,
number, row, separator, textinput, init`. That covers everything needed here.

## The API we would actually call

```lua
ModMenu.Init({ title=, instanceId=, key=, keyHint=, dock=, tabs={...}, theme= })
ModMenu.Register({ id=, title=, tab=, items={ ... } })
ModMenu.Get(sectionId, itemId)            -- read a checkbox or dropdown
ModMenu.Set(sectionId, itemId, value)     -- write it, widget updates live
ModMenu.SetLabel(sectionId, itemId, "..")
ModMenu.SetButtonLabel / SetButtonEnabled / SetButtonVariant / SetButtonActive
ModMenu.Open() / Close() / Toggle() / SetTab() / SetDock()
```

Item fields, read out of the widget sources:

- `checkbox`: `id`, `label`, `default`, `onChange(bool)`, `showState`
- `number`: `id`, `label`, `default`, `integer`, `min`, `max`
- `button`: `id`, `label`, `variant` (default/primary/secondary/success/danger/), `enabled`, `active`, `onPress`
- `label`: `id`, and text set later with `ModMenu.SetLabel`
- `fold`: a collapsible group inside a section

---

## What the panel would show

**Tab: Commander view**

| Control | Type | Does |
| --- | --- | --- |
| Commander view | checkbox | same as F3 today |
| Tank | label | `BP_PzKpfwIVAusfG_C`, so you know what you are editing |
| Offset X / Y / Z | number x3 | replaces numpad nudging |
| Back off / Raise | button x2 | the usual two-axis fix, 5 cm a press |
| Reset | button | back to 0,0,0 |
| Save this tank | button | same as ALT+NUM 0 |
| Status | label | last action, so nothing happens silently |

**Later tab: Realism** - repair times, optics magnification, and the
unlock toggle, each as its own section once built.

---

## Phases

**Phase 1 - prove the framework runs in this game. One test, on its own.**

1. Unpack ModMenu into `ue4ss/Mods/shared/ModMenu`
2. Add a panel to CtACmdr with one label and one button that only logs
3. Press its key and see whether a panel appears

Everything else depends on that answer, so it does not get bundled with
anything. This game uses UMG heavily - one dump counted 1616 widgets - but
that is a reason to expect it to work, not a reason to assume it.

**Phase 2 - move the existing controls in.** The panel calls the same Lua
functions the keys already call. The camera code does not change at all,
and the keys keep working, so a menu failure cannot take the feature down.

**Phase 3 - per-tank dropdown and FOV.** A dropdown of every tank with a
saved position, and a number field for camera FOV, currently fixed at the
game's 90.

**Phase 4 - realism tab.** Repair times, optics, unlock. Each is a section
that can be added or removed without touching the others.

---

## Decisions

**Panel key: F5.** F3/F4 are the view, ALT+NUM moves the camera, F7 is
taken by another mod in this install, F8/F9 are the dev probe.

**Cursor: expect to need `cursorMode = "modmenu"`.** Games often suppress
the mouse pointer, and that option draws its own. Phase 1 settles it.

**Pinning: same treatment as UE4SS.** Version named, SHA256 pinned, MIT
licence text shipped next to it.

---

## Risks

- **A third-party dependency in our zip.** Small, MIT, pinned - but it is
  someone else's code shipping with ours, and that should be a deliberate
  decision, not a side effect.
- **UI frameworks break on game patches** more readily than plain Lua,
  because they build engine widgets directly.
- **Input backend.** ModMenu can use `RegisterKeyBind` or poll the engine.
  Our keybinds work today, so the default should be fine - and it is the
  first thing to check if the panel key does nothing.
- **The panel is a second way to do things.** If it becomes the *only* way,
  a framework problem takes the whole mod with it. Keys stay.

---

## Phase 1 result - PASSED

Run on 08/11/2026, main menu, with a throwaway probe mod.

```
require ok=true   type=table
Init ok=true      err=nil
Register ok=true  err=nil
Open ok=true      err=nil
checkbox changed to true        <- after a real mouse click
```

The panel drew as intended - title, hotkey hint, dock selector, section
header, label, checkbox, button. See `menu-probe.png` in this folder.

Then a synthetic left click at the checkbox coordinates produced
`checkbox changed to true`, so **mouse input reaches the panel** without
any cursor workaround. That retires the cursor risk from the plan below.

**What this proves:** UMG can be built at runtime in this game, ModMenu
resolves through `require("ModMenu.ModMenu")` from
`ue4ss/Mods/shared/ModMenu`, and clicks land.

**What it does not prove:** this was the main menu. In gameplay the game
captures the mouse for camera look, which is exactly when a menu tends to
lose its cursor. That is the next thing to test, and it needs someone in
a tank - it cannot be checked from the menu.

---

## Phase 1b result - it works in the menu, and it can strand the game

Reported from a real session: opening the panel **in gameplay** made the game
semi-freeze, and closing it left the game alive but unclickable. Refocusing
did not help; Alt+F4 was the only way out.

That is the cursor risk from this plan arriving exactly where predicted.
Two things were missing:

1. **The panel opened in gameplay with no way to hand input back.** ModMenu
   does restore GameOnly on close, but nothing guarantees it won when the
   game was still fighting for the mouse.
2. **Nothing could recover the session.** Alt+F4 was the only exit.

### The fix, now in the probe

Read from ModMenu's own source rather than guessed: it applies input mode
through `/Script/UMG.Default__WidgetBlueprintLibrary`:

```lua
lib:SetInputMode_GameOnly(pc, false)   -- UE5 arity
pc.bShowMouseCursor = false
pc:SetIgnoreLookInput(false)
pc:SetIgnoreMoveInput(false)
```

So the probe now does three things:

- **Closing the panel always runs that restore itself**, 150 ms after
  `ModMenu.Close()`, instead of trusting the framework to win.
- **F6 is a panic key.** It closes the menu and forces the same restore.
  Critical detail: UE4SS keybinds go through UE4SS, not the game's input,
  so **F6 still fires when the game has stopped responding to the mouse**.
- **`ignoreLook = true`**, the documented option for mouse-look games. The
  camera should no longer fight the cursor while the panel is open.

Also removed: the probe used to open itself 15 seconds after load. A
diagnostic that pops up unbidden mid-mission is a bad diagnostic.

### Tested, and not

Tested at the main menu: open, close, restore and panic all log correctly,
game stays responsive.

**Not tested: gameplay.** That is where it failed, and it needs a person in
a tank. Steps: F5 to open, click the checkbox, F5 to close. If the game
feels stuck, press **F6**, which is the whole point of adding it.

---

## Phase 1c result - PASSED IN GAMEPLAY

Confirmed in a tank, 08/11/2026. The panel drew over the live game, the
checkbox toggled to ON, the status label read `open - F5 close, F6 panic`,
and closing it returned the game to normal.

So the framework works in gameplay, not just in menus, once it is given
three things:

1. `ignoreLook = true`, so the camera stops fighting the cursor.
2. Our own input restore after closing, rather than trusting the framework.
3. F6 as a panic key, because a stuck session must never need Alt+F4.

Which of the three actually fixed it is not isolated - all three went in
together. They stay in together; each is cheap and each guards a failure
we have already seen.

**Phase 1 is complete. Phase 2 can start.**
