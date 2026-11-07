# CtACmdr - commander view for Call to Arms: Panzer Elite

![Commander view from the cupola of a Panzer IV](docs/commander-view.webp)

*Looking out over the hull roof from the commander's position. Hatch rim,
MG mount and ammo box in frame. This is the view the mod gives you.*

A mod that gives you a proper tank commander view.

The game ships with an external camera that slides into the gunsight.
There is no commander position to switch to. This mod puts the camera
at the commander's head instead, lets you move it, and remembers the
position for each tank.

## What you get

- Commander view: head up, out of the cupola.
- Free look, fairly wide limits.
- Your own camera position, nudged with the numpad.
- One saved position per tank, remembered across sessions.
- **The binoculars still work.** They use their own camera, so raising
  them from the commander view behaves normally.

## Keys

| Key | Does |
| --- | --- |
| F3 | Commander view on / off |
| F4 | Back to the normal view |
| ALT + NUM 8 / 2 | Camera forward / back |
| ALT + NUM 4 / 6 | Left / right |
| ALT + NUM 9 / 3 | Up / down |
| ALT + NUM 5 | Reset the offset to zero |
| ALT + NUM 0 | Save this tank's position |
| F6 | Write a report to CtACmdr.log |

ALT because plain numpad navigates between units in skirmish mode.
ALT rather than CTRL because UE4SS binds CTRL+NUM 6..9 to debug file
dumps.

Each numpad press moves the camera 5 cm. Hold or tap to creep.

The view also applies itself about 1.5 seconds after you get into a
vehicle that has a saved position.

## Install

**One command.** From a copy of this repo:

    powershell -ExecutionPolicy Bypass -File tools\setup.ps1

That downloads UE4SS, puts it next to the game exe, and installs the mod.
Re-running it will not touch camera positions you tuned in game.

    -GameRoot "D:\path"   if the game is not in the default place
    -QuietDumps           also switch off UE4SS's 33 MB crash dumps
    -Force                re-download UE4SS even if it is present

**Full walkthrough, including doing UE4SS by hand:** [INSTALL.md](INSTALL.md)

**Already have UE4SS?** Then just the mod:

    powershell -ExecutionPolicy Bypass -File tools\install.ps1

**By hand:** copy the `CtACmdr` folder into

    ...\call_to_arms_pe\Binaries\Win64\Mods\

That is the whole install. The folder carries an `enabled.txt`, so UE4SS
loads it whether or not `mods.txt` mentions it.

## Uninstall

Delete the `Mods\CtACmdr` folder.

**To switch it off without deleting**, remove or rename
`Mods\CtACmdr\enabled.txt`. That file tells UE4SS to load the mod no
matter what `mods.txt` says, so `CtACmdr : 0` on its own will **not**
disable it.

Nothing is written into the game's .pak files. Nothing touches your saves.

## Where the positions live

    Binaries\Win64\CtACmdr_views.txt

One line per tank, in the form:

    BP_PzKpfwIVAusfG_C -70.00 0.00 0.00

The name is the vehicle blueprint class, then X, Y, Z in centimetres.

## Singleplayer only

There is no anti-cheat in this game, but keep it out of multiplayer.

## See also

- `docs/api-notes.md` - everything found out about the game's internals
- `docs/game-enums.txt` - 67 game enums dumped from the running game
- `NOTES.md` - the working diary, including the dead ends

---

## Credits

**Created by DeepSeek, at the behest of a human.**

Every part of this was produced by DeepSeek in a single working session,
at the request of [@murkzuk](https://github.com/murkzuk):

- the reverse-engineering of the game's camera, crew and hatch systems
- the reflection probes, and the crash forensics that pinned down which
  reflection calls this build cannot survive
- the Lua mod
- the per-tank camera save system
- this documentation

The human drove: it was their idea to build a commander view, they sat
through every crash test, and they decided when a view was good enough.

---

## License

MIT - see [LICENSE](LICENSE).

Use it, change it, ship it, fork it. Just keep the copyright notice, and
do not hold anyone liable if it breaks something.
