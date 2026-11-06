# Install, step by step

From a bare game install to a working commander view. About 10 minutes.

Everything here is reversible. Nothing is written into the game's
.pak files and your saves are never touched.

---

## What you need

- Call to Arms: Panzer Elite, installed through Steam.
- A file unzipper. Windows can do zip files on its own.
- UE4SS, which we download in step 2. It is free and open source.

---

## Step 1 - Find the game folder

In Steam: right click the game, Manage, Browse local files.

You land in something like:

    ...\steamapps\common\Call To Arms - Panzer Elite

Open this folder inside it:

    call_to_arms_pe\Binaries\Win64

**This is the important folder.** The game's exe lives here:

    call_to_arms_pe-Win64-Shipping.exe

Everything we install goes in here, next to that exe.

---

## Step 2 - Download UE4SS

UE4SS is the mod loader. It is what lets a Lua script talk to the game.

Go here:

**https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1**

Under Assets, download:

    UE4SS_v3.0.1.zip        (about 5 MB)

Ignore the files marked DEV or zDEV. Those are developer builds.

Why 3.0.1: it is the release this mod was built and tested against, on
this exact game.

---

## Step 3 - Unzip UE4SS into the game folder

Open `UE4SS_v3.0.1.zip`. Inside you will see:

    dwmapi.dll
    UE4SS.dll
    UE4SS-settings.ini
    Mods\

Select those items and copy them into the `Binaries\Win64` folder from
step 1. So you end up with:

    Binaries\Win64\call_to_arms_pe-Win64-Shipping.exe
    Binaries\Win64\dwmapi.dll
    Binaries\Win64\UE4SS.dll
    Binaries\Win64\UE4SS-settings.ini
    Binaries\Win64\Mods\...

Do not put them in a subfolder. They must sit beside the exe.

**How this works, briefly.** The game loads `dwmapi.dll` by itself.
UE4SS is pretending to be that Windows file, so the game loads UE4SS
instead, and UE4SS then loads the real one. That is why the file has
that odd name and why it has to be exactly there.

---

## Step 4 - Check that UE4SS works

1. Start the game from Steam.
2. **The screen will be black for up to a minute.** That is normal for
   this game, it is loading a 29 GB pak file. Do not panic, do not
   click. Wait.
3. When it loads, look for a small debug window in the corner. That is
   UE4SS's own overlay.
4. Quit the game.

Now check this file exists:

    Binaries\Win64\UE4SS.log

If it is there and it mentions `EngineVersion: 5.4`, UE4SS is working.

If there is no log at all, see Troubleshooting at the bottom.

---

## Step 5 - Install CtACmdr

### Easy way

Open PowerShell in this repo's folder and run:

    powershell -ExecutionPolicy Bypass -File tools\install.ps1

If your game is not on `L:\`, add the path:

    powershell -ExecutionPolicy Bypass -File tools\install.ps1 -GameRoot "D:\Games\Call To Arms - Panzer Elite"

### Manual way

1. Copy the `CtACmdr` folder from this repo into
   `Binaries\Win64\Mods\`
2. Open `Binaries\Win64\Mods\mods.txt` in Notepad.
3. Add this line at the bottom:

       CtACmdr : 1

The `1` means on. A `0` means off.

---

## Step 6 - Use it

Start the game and get into a tank.

| Key | Does |
| --- | --- |
| F3 | Commander view on / off |
| F4 | Back to the game's normal view |
| NUM 8 / 2 | Camera forward / back |
| NUM 4 / 6 | Left / right |
| NUM 9 / 3 | Up / down |
| NUM 5 | Reset the position to zero |
| NUM 0 | Save this tank's position |
| F6 | Write a report to CtACmdr.log |

Each numpad press moves the camera 5 cm.

If the view is buried in the cupola machine gun, tap NUM 2 to pull
back, and NUM 9 to lift. When it looks right, press NUM 0.

Your saved positions live in:

    Binaries\Win64\CtACmdr_views.txt

One line per tank. The binoculars keep working normally from this view.

---

## Step 7 - How to undo all of it

**Just the mod:**

1. Delete `Binaries\Win64\Mods\CtACmdr`
2. Delete the `CtACmdr : 1` line in `mods.txt`

**UE4SS as well:**

Delete these from `Binaries\Win64`:

    dwmapi.dll
    UE4SS.dll
    UE4SS-settings.ini
    UE4SS.log
    Mods\
    UE4SS_Signatures\

The game does not care. It will look for its own `dwmapi.dll` again
and find it.

Steam's "Verify integrity of game files" also ignores everything we
added, because we added files rather than changing them. It will not
clean up for you, and it will not break this either.

---

## Troubleshooting

**Black screen for a long time.**
Normal. This game takes 30 to 60 seconds. Wait it out before assuming
anything is wrong.

**No UE4SS.log appeared.**
- The files are in the wrong folder. They must be next to
  `call_to_arms_pe-Win64-Shipping.exe`, not in `call_to_arms_pe\Binaries\`.
- Antivirus may have removed `dwmapi.dll`. A DLL pretending to be a
  system file is exactly what antivirus dislikes. Check your
  protection history, allow the folder, and re-copy.
- The game was not fully closed when you copied the files.

**The mod loads but F3 does nothing.**
Check `UE4SS.log` for the line `Starting Lua mod 'CtACmdr'`. If it is
missing, the `CtACmdr : 1` line in `mods.txt` is missing or has a typo.

**The view slides back out on its own.**
The zoom component is rewriting the camera arm. That is what
`MinCamDistance` and `DefaultCamDistance` being zeroed is for. Press F3
again and check `CtACmdr.log` for the `zoom pinned` line.

**The game crashed.**
This game crashes on its own now and then, mod or no mod. Crashes are
recorded in:

    %LOCALAPPDATA%\call_to_arms_pe\Saved\Crashes\

**After a game update.**
UE4SS usually keeps working. If mods stop loading, reinstall UE4SS from
the link in step 2. The mod itself lives entirely in `Mods\CtACmdr` and
survives game updates.

---

## Links

- This mod: https://github.com/murkzuk/CtACmdr
- UE4SS v3.0.1: https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1
- UE4SS project: https://github.com/UE4SS-RE/RE-UE4SS
- Game internals we mapped: [docs/api-notes.md](docs/api-notes.md)
