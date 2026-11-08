# The in-game menu: what was tried, what it cost, how to resume

**Status: PARKED.** Reverted on 08/11/2026 at the owner's request -
"it is too much for me at present". Nothing was broken by the revert;
the mod is back to keys only and the game starts clean.

This file exists so the work is not repeated from scratch.

---

## Why it was wanted

ALT+NUM keybinds work, but a panel would mean no memorising keys and
no numpad gymnastics: tick a box for the view, type an offset, press
a button to save. The plan is in `menu-plan.md`.

## What was built

ModMenu (mattdavida/ue4ss-ModMenu, MIT, v1.4.0, 52 KB, SHA256
`ba3856316417aa8dacf7b5242bba22346fe64e5cee1dcdebcb9bb0a08521c1f5`)
installed to `ue4ss/Mods/shared/ModMenu` as a `require`d library.

A panel inside CtACmdr with: a checkbox mirroring the view state, a
label showing the current tank, three integer fields for the offset,
buttons for Back off / Raise / Reset / Save this tank, and a status
line. It called the same functions the keys call - nothing was
implemented twice.

## What worked

- The panel renders in this game, in the menu *and* in a tank.
- Mouse clicks reach it; no cursor workaround needed.
- Number fields accept input and apply it live.
- The checkbox and buttons drive the real camera functions.

## What broke, and why

**The game semi-froze, then was alive but unclickable.** Opening the
panel in gameplay left the game unable to take the mouse back, and
Alt+F4 was the only exit. Fixed by three things together, so which one
mattered is not isolated:

1. `ignoreLook = true` in `ModMenu.Init` - the documented option for
   mouse-look games.
2. Binding F5 ourselves rather than handing it to ModMenu, so closing
   always runs **our** input restore: `SetInputMode_GameOnly` via
   `/Script/UMG.Default__WidgetBlueprintLibrary`, then cursor off,
   look and move released.
3. **F6 as a panic key.** UE4SS keybinds bypass the game's input, so
   F6 still fires when the game has stopped listening to the mouse.
   Without it, a stuck session needs Alt+F4.

**"Nudge 5 does nothing".** The buttons called `nudge()`, which refuses
while the commander view is off - a guard added earlier so keys cannot
move the normal camera. From a panel that is indistinguishable from
broken. Fixed by turning the view on first (`panelNudge`).

**"Typed 60, got 91".** The number field's `onChange` wrote the value
and then called `syncPanel()`, which pushed it back into the box being
typed in. Every keystroke fought a rewrite. Fixed by never calling
`syncPanel` from a number field. Verified afterwards: typing 6 then 0
logs `Y set to 6` then `Y set to 60`.

## The honest cost

This took more round trips than the camera work did, because every
step needed a human in a tank to confirm it. UI changes cannot be
verified the way a value write can, and each bug surfaced only in
play.

## How to resume

1. Read `menu-plan.md` first - it has the plan and the phases.
2. The working probe with the input-restore and panic logic is kept at
   `experiments/CtAMenuProbe/Scripts/main.lua`. It is the shortest
   known-good example for this game.
3. The panel integration is in git history: `5305b2c` (added) through
   `0c51187` (both bugs fixed). `git show 0c51187:CtACmdr/Scripts/main.lua`
   is the last working version with the panel.
4. Reinstall ModMenu from its release, pin the checksum above, and
   carry its MIT licence if it ships in our zip.
5. Ship it **optional**, as it was: if `require` fails, keys only.

## What the revert left behind

- `CtACmdr` is the pre-menu version: F3/F4, ALT+NUM, ALT+NUM 0, F6.
- ModMenu removed from the game folder.
- The menu probe removed.
- `CtATables` left on disk but disabled (`enabled.txt.off`).
- Verified after the revert: the game starts clean and logs
  `[CtACmdr] v1.8 loaded`, with no Lua errors.
