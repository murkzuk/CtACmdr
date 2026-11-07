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

**You do not need git, PowerShell or any other download.** One zip has
everything.

1. Go to the **[latest release](https://github.com/murkzuk/CtACmdr/releases/latest)**
   and download **`CtACmdr-v…-Windows.zip`** (under *Assets*).
2. **Close the game.**
3. In Steam: right-click the game, **Manage**, **Browse local files**.
4. Open these folders, one after the other:

   ```text
   call_to_arms_pe
   Binaries
   Win64
   ```

   You are now inside **`Win64`**. You can see `call_to_arms_pe-Win64-Shipping.exe`.
5. Double-click the zip to **open** it, in a second window. You see its
   **contents**: `dwmapi.dll`, a `ue4ss` folder and a read-me. Select the
   contents (`Ctrl + A`) and **drag the contents into the `Win64` window**.
   Do **not** drag the `.zip` file itself.
6. Start the game. **The first start sits on a black screen for up to a
   minute. That is normal.**
7. Get into a tank and press **F3**.

> ### ⚠️ The one thing that goes wrong
>
> **The contents of the zip must go INTO the `Win64` folder itself.**
> Not the `.zip` file. The files and folders inside it.
>
> Windows' *Extract All* offers a new folder named after the zip.
> **Do not use it. Nothing will work.**
>
> **Right:** beside the exe
>
> ```text
> Win64
>    call_to_arms_pe-Win64-Shipping.exe
>    dwmapi.dll          <-- here
>    ue4ss               <-- here (a folder)
> ```
>
> **Wrong:** one folder too deep
>
> ```text
> Win64
>    call_to_arms_pe-Win64-Shipping.exe
>    CtACmdr-...-Windows        <-- folder named after the zip
>       dwmapi.dll              <-- too deep
>       ue4ss                   <-- too deep
> ```
>
> If yours looks like the wrong one, drag `dwmapi.dll` and `ue4ss` up one
> level into `Win64`, then delete the empty folder.

The zip also contains a `READ ME FIRST.txt` with the same steps.

**Antivirus:** `dwmapi.dll` is how UE4SS loads into the game. It pretends to be
a Windows file, so some antivirus programs remove it. If the mod does
nothing, check your protection history, allow that file, and extract again.

**Already use UE4SS mods?** Do not use the Windows zip, it would replace your
UE4SS files and settings. Download **`CtACmdr-v…-mod-only.zip`** instead and
copy its `CtACmdr` folder into your UE4SS `Mods` folder (`Win64\ue4ss\Mods`,
or `Win64\Mods` on older builds). The normal UE4SS v3.0.1 release does **not**
work on this game (it fails its signature scan and loads no mods), so use the
build named in [INSTALL.md](INSTALL.md).

**Check your download (optional):** the release notes list a SHA256 for each
zip. In PowerShell: `Get-FileHash .\CtACmdr-v…-Windows.zip`

### Other ways to install

- **Full walkthrough, doing UE4SS by hand:** [INSTALL.md](INSTALL.md)
- **One command, from a copy of this repo:**
  `powershell -ExecutionPolicy Bypass -File tools\setup.ps1`
  (downloads UE4SS, then installs the mod; add `-GameRoot "D:\path"` if the
  game is not on the default path)
- **Mod only, from a copy of this repo:**
  `powershell -ExecutionPolicy Bypass -File tools\install.ps1`

The `CtACmdr` folder carries an `enabled.txt`, so UE4SS loads it whether or not
`mods.txt` mentions it.

## Uninstall

- **Just the mod:** delete `Win64\ue4ss\Mods\CtACmdr`
  (`Win64\Mods\CtACmdr` on an older UE4SS).
- **Everything the zip added:** delete `Win64\dwmapi.dll` and the
  `Win64\ue4ss` folder.

**To switch it off without deleting**, remove or rename
`CtACmdr\enabled.txt`. That file tells UE4SS to load the mod no
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
