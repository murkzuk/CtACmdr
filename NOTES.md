# Working diary

## The goal

A proper tank commander view. Head up out of the cupola, free look,
able to drive, and the binoculars on a key afterwards.

The developers' version has no commander position at all. There is an
external camera that scrolls into the gunsight, and lowering the
binoculars sends the commander back down inside the cupola.

## Where it stands

**Working.** F3 puts the camera at the commander's head. The game stays
there now instead of sliding back. Numpad moves it, and the position is
saved per tank.

Screenshot check: first person over the hull roof, hatch rim, MG mount
and ammo box in frame. Saved offset for the Panzer IV: `-70, 0, 0`.

## The thing that cracked it

The camera is not separate from the zoom. It is one spring arm:

```
FollowSpringArm  TargetArmLength = 500  ->  FollowCamera
```

Scrolling shortens that arm toward `MinCamDistance` (150). Setting the
arm to 0 puts the camera on the pivot, which is the commander. But the
zoom component rewrites the length every frame, so the arm has to be
held down by zeroing `MinCamDistance` and `DefaultCamDistance` too.

## Dead ends, and what they cost

| Attempt | Result |
| --- | --- |
| Walk the class chain, dump properties | froze the game |
| Read a guessed property name | froze the game |
| Read a null object property | froze the game |
| Call `StartUsingBinoculars()` directly | froze the game |
| Set `MaxCamDistance = 0` as well | suspect, reverted |

Rule now: enumerate names first, read only those, never call a function
without its signature.

## Milestones

- v0.1 - recon, crashed. Kept 67 enums from it.
- v0.2 - guessed names, crashed at the first one.
- v0.3 - enumerated then read, crashed on a null VFX pointer. Gave us
  `CrewManager` and `Crew_Commander`.
- v0.4 - names only. Complete API surface, no crash.
- v0.5 - proved property writes stick.
- v0.6 - measured the real camera position. Found it was the Follow rig,
  not the zoom rig.
- v0.7 - never run.
- v0.8 - numpad editor, but SHIFT was already the gunsight key and the
  arm slid back because the zoom numbers were not pinned.
- v0.9 - pinned, plain numpad. **First working commander view.**
- v1.0 - auto-applies when you get in a vehicle.

## Verified working

- Commander view holds at the commander position.
- Free look at 85 pitch / 175 yaw, up from 20 / 45.
- Numpad positioning, saved per tank.
- **Binoculars still work from the commander view.** Confirmed in game.
  They use their own camera actor, so they are unaffected by the
  follow arm being pinned.

## Still to try

1. `VehicleLookInfo` and `SetLookCustomizations` - the game's own look
   customisation path. Never explored, might be the cleaner way to do
   the look limits.
3. Whether the game is stable enough with UE4SS to keep going. It has
   crashed on its own several times, including before this mod existed.

## Crash spots, for reference

- `%LOCALAPPDATA%\call_to_arms_pe\Saved\Crashes\` - UE writes a folder
  per crash with a minidump and `CrashContext.runtime-xml`.
- `Binaries\Win64\crash_*.dmp` - UE4SS's own dumps.

## Credits

Created by DeepSeek at the behest of a human (@murkzuk), in one session.
The human specified the goal and ran every in-game test.

## House rules

- **Always run `tools\check-lua.ps1` before installing.** A Lua syntax
  error makes the whole mod silently fail to load, and the only clue is
  one line in UE4SS.log after a full game restart. Cost a test run once.

- Log every line with a timestamp. Two runs appending to the same log
  with no timestamps is impossible to untangle.

- Singleplayer only.
- Never write into the .pak. Everything is loose files.
- Every mod keeps a kill switch: delete the folder, set the line in
  `mods.txt` to 0.

## The grander plan - keep the commander out

Not built. This is the design, so it can be picked up later.

### The idea

The commander model already exists and already animates. At mission start
he is up, out of the cupola. When you lower the binoculars he ducks back
inside and the hatch closes. We want to reverse that on demand: F3 opens
the hatch, he pops up, and he stays up while you drive. The camera then
rides his actual head instead of an offset we guessed.

### Why it should work

```
CrewManagerComponent
  func OnBinocularsStateChanged(NewState Enum)
  func SetAllCrewAnimsHidden(bNewHidden Bool)
  func SetStateForAllCrewAnims(NewState Enum, CurrentHealth Float)
  func PlayCrewMemberAnimation_ByRole(CrewMemberRole Enum, bOnlyIfAlive Bool,
                                      AnimationTag Struct, Type Enum)
```

The crew manager subscribes to the binocular state. That is the
mechanism that pops the commander up and down, so it can be driven
directly rather than faked.

Supporting evidence:

- `Crew_Commander` is a `CrewMemberSkeletalMeshComponent` on the tank
  blueprint, and its `bVisible` was false while he was buttoned up.
- `EBinocularsState`: None = 0, InUse = 1.
- `ECrewRole`: Commander = 0.
- The tank blueprint has hatch mesh components: `hatch_01` .. `hatch_07`,
  `hatch_02_1`, `hatch_03_1`, plus `engine_hatch_L` / `engine_hatch_R`.
- The exe mentions `SetHatchState`, `GetHatchState`, `SetAllHatchState`,
  `GetAllHatchStates`, `HatchSocket` and `CrewHatchID`. We never found
  which class owns them, because only keyword matching functions were
  listed for `PE2Vehicle`. Enumerating its full function list would
  answer that, and enumerating names has never crashed.

### Test order, cheapest first

1. One call: `crewManager:OnBinocularsStateChanged(1)`. If he pops up,
   that is the whole mechanism found in a single line.
   Watch `Crew_Commander.bVisible` in the log to confirm.
2. If the body rises but the hatch stays shut, find the hatch owner
   (step 4 above) and drive it the same way.
3. If he rises, anchor the camera to his head. Either the
   `BinocularsBone` the game already returns from `GetBinocularsBone()`,
   or the eye socket on the `Crew_Commander` mesh. That removes the
   hand-tuned `-70, 0, 0` offset entirely and would follow the turret
   properly on every vehicle.
4. Then F3 becomes: crew up, camera on the head bone. Lowering the
   binoculars should no longer duck him, or we simply re-pop him.

### The catch

Crew state looks replicated. `BinocularsComponent` has
`SendCurrentStateToServer` and `SendCurrentOrientationToServer`, and
`OnRep_BinocularsState` style handlers. In singleplayer the local player
is the server, so it should hold. In multiplayer it will fight the
server and probably snap back. Singleplayer only, as with the rest.