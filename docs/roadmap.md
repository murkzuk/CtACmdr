# Where this could go next

A plan, not a promise. Everything below is grounded in things we have
actually seen in this game - reflection dumps, enum dumps, or the asset
manifest - rather than guesses about how similar games work.

Ordered by what is cheap and certain first, speculative last.

---

## 1. Unlock every vehicle {#unlock}

**Why it should be possible:** the game models unlocks explicitly, with
its own vocabulary:

```
IsVehicleUnlocked              GetUnlockedVehicles
IsVehicleUnlockedByDefault     GetUnlockedVehiclesCount
bUnlockedByDefault             GetMissionThatUnlocksThisVehicle
OnVehicleUnlocked              bLastUnlocked
GetMissionRewards              EMissionRewardType
```

And in the assets:

```
Blueprints/Subsystems/BP_ProgressionSubsystem
Blueprints/startMenu/BP_GarageManager
Data/DT_GarageVehicleTable_GER       Data/DT_GarageVehicleTable_USA
Data/MissionRewards/RDA_<vehicle>    <- one per tank, granted by a mission
```

So a vehicle is a row in a garage table plus a mission reward. There is a
real flag to flip.

### FOUND: the game has its own unlock functions

`/Script/Panzer_Elite_2.ProgressionSubsystem` carries the whole system:

```
UnlockAllVehicles()        no parameters
UnlockAllMissions()        no parameters
LockAllVehicles()          ResetAllProgress()
UnlockVehicle(tag)         LockVehicle(tag)
GetUnlockedVehiclesCount() -> int
IsVehicleUnlocked(tag) -> bool
GetProgressionSubsystemInstance(WorldContextObject) -> instance
SavePlayerProgress() -> bool
```

Reached and called successfully in game: located the instance through the
main menu player controller, called `UnlockAllVehicles`, then
`SavePlayerProgress` which returned true.

**Resolved - and the answer is no.**

`GetVehicleProgressMap()` returns 25 entries, and
`GetUnlockedVehiclesCount()` returns 25. Those are the same 25: the map
tracks exactly the vehicles that exist, so "unlocked" already covers
everything obtainable. `UnlockAllVehicles` therefore had nothing to do,
and correctly changed nothing.

A look at the hangar confirmed it. Every released vehicle is selectable.
The two cards still locked - **PzKpfw V Panther and PzKpfw VI Tiger** -
show "0/0 UNITS", which is the shape of content that is not in the game
yet rather than content behind progression. The title is in Early Access
(BETA v.0.11.03), `IsVehicleComingSoon` exists in the API for exactly
this case, and neither tank appears in the progress map at all.

### So what is an unlocker worth?

Not much for a player who has finished the missions - there is nothing
left to unlock. It would matter for a fresh save, where it would skip the
mission-reward progression. That makes it a small optional toggle, not a
headline feature, and it should say so plainly rather than promise tanks
that do not exist yet.

### The original probe plan, kept for reference

The steps below were written before the subsystem was found. The DataTable
route turned out to be a dead end: `DT_GarageVehicleTable_GER` is a
template with 3 rows named Row1..Row3 and seven auto-generated
`Column1_19_E5988...` object columns from a blueprint struct.

### Step 1 - probe (one keypress, changes nothing)

A `CtAUnlock` probe that, names only:

- lists every class whose name contains `Progression`, `Garage` or `Reward`
- for each, lists its properties and functions with types
- on the `ProgressionSubsystem` instance, lists the current unlocked set

This is the same names-only enumeration that has never once frozen this
game, as long as we never read a value whose name we have not seen first.

### Step 2 - edit the garage DataTable

UE4SS exposes `UDataTable` with **reference-based row access**:

```
dt:ForEachRow(function(rowName, row)
    row.someFlag = true          -- writes straight into the table
end)
dt:FindRow("RowName")            -- same, for one row
```

and `LoadAsset` fetches an asset by path without the game needing to be
in any particular state.

So the unlocker is most likely:

```
LoadAsset("/Game/Data/DT_GarageVehicleTable_GER")
LoadAsset("/Game/Data/DT_GarageVehicleTable_USA")
  -> ForEachRow, set the unlock column on every row
```

**This is the cheapest lever by a wide margin**, and it is the standard
technique in other UE games. It replaces the earlier plan of poking the
progression object or hooking `IsVehicleUnlocked`.

The probe still has to happen first, for one reason: we need the real
column names on the row struct. Guessing a property name crashes this
game. `RegisterCustomProperty` and the row struct's own
`ForEachProperty` give us the names safely.

Fallbacks, in order, if the table does not hold the flag:

1. A bool or array on the progression object.
2. Hook `IsVehicleUnlocked` and always answer yes.
3. Edit the save (`SharedGameSettings.sav`, GVAS). Least reversible, last.

### The caveat that decides the design

The progression subsystem talks to **PlayFab** - `GetProgressionSubsystemInstance`,
`OnPlayFabProgressionRequestCompleted`, `InitializeProgressionSystem`. If
unlocks are validated online, a local flag may be overwritten on the next
sync. That would show up as the garage snapping back after a mission.

So: expect this to work in singleplayer campaign, test in skirmish, and
if it does snap back, say so in the docs rather than calling it a bug.

---

## 2. Realism work

Five things the game models that we can already reach. The first two are
almost free.

### 2.1 Optics magnification per vehicle

Already half-built by the developers:

```
ZoomComponent.MagnificationFactors      Array-of-float
ZoomComponent.DefaultFieldOfView
Data/.../DA_PzKpfwII_BinocularsSetup_20
Data/.../DA_M24_Chaffee_BinocularsSetup_30
Data/.../DA_StuH42_BinocularsSetup_40
Data/.../DA_GMC_M36_BinocularsSetup_120
```

Those numbers look like historical magnifications - 2x, 3x, 4x, 12x - but
the PzKpfw IV fell back to `DA_BinocularsSetup_Basic`, so not every
vehicle is wired to a real sight.

**Work:** give each vehicle its correct sight magnification (TZF 5b is
2.5x, Italian and German sights vary), and stop the binos from being a
free 10x spotting device where history says otherwise.

**Effort:** low. Floats on a component, and one data asset each.

### 2.2 Repair times

Every vehicle component carries its own repair figures:

```
VehicleComponent:  RepairTime   RepairPriority
                   MaxHealth    CurrentHealth
                   ComponentType  EVehicleComponentType
```

A knocked-out `Hull` currently reports `RepairTime 5.0`, which is
arcade-fast for a track or a transmission.

**Work:** per-component-type repair times that match the job - tracks
minutes, a gun barrel longer, an engine and transmission much longer - and
different figures per side if the data supports it.

**Effort:** low, and testable without any guessing: the values are floats
we have already read successfully.

### 2.3 Crew exposure

Crew are real objects that can die:

```
CrewMemberSkeletalMeshComponent
CrewManagerComponent: PlayCrewMemberAnimation_ByRole, SetAllCrewAnimsHidden
ECrewRole: Commander, Driver, Gunner, Loader, RadioOperator, Crew
OnOccupantDied, IsCrewComponentWithRole
EVehicleAdditionalDamageEvent
```

**Work:** make an unbuttoned commander genuinely at risk from nearby HE
and machine-gun fire, instead of a camera that cannot be hit.

**Effort:** medium. This is damage logic, so it needs care - and it is the
item most likely to need real gameplay tuning rather than a number.

### 2.4 A commander's head, not a developer's cheat

We measured this: the developers' bino camera sits **22 cm to the side and
6.6 cm above** the commander pivot - deliberately cheated so the hatch rim
and machine gun do not block the view.

**Work:** an option to put the camera on the actual crewman's head bone
instead, accepting a worse view for an honest one. The measurement is
already in `docs/api-notes.md`, and `GetBinocularsBone()` exists.

**Effort:** low. And mildly funny: the realism mod is to undo the
developers' cheat.

### 2.5 Look limits, buttoned versus unbuttoned

```
bEnableRotationLimit   RotationLimit   FreeLookMouse
BinocularsViewAngleLimit   EBinocularsLimitType
```

**Work:** a buttoned commander should be stuck behind a periscope, with a
much narrower arc than an unbuttoned one.

**Effort:** medium - it needs the two states to be distinguishable at
runtime, which is the piece we never solved.

---

## 3. Things we should not attempt without a reason

- **Pak mods** for damage or optics data. Possible, but every value above
  is reachable live, so shipping a 29 GB pak override is a bad trade.
- **Vehicle physics.** `EPE2VehicleDifferentialType`,
  `EPE2VehicleThrottleState` and the movement component exist, but bad
  physics tuning is worse than none, and it is the hardest thing to undo.
- **Multiplayer anything.** PlayFab is in the loop and the crew and bino
  state are replicated. Singleplayer only, as with everything here.

---

## 3b. What the tool can do that this project has not used

The UE4SS Lua API is much wider than what we touched. Confirmed from its
own documentation, and worth knowing before writing another keybind:

| Capability | What it would give us here |
| --- | --- |
| `UDataTable` + `LoadAsset` | **Edit game data tables live** - garage tables, mission rewards, anything row-based. The unlocker, and probably the optics and repair numbers too |
| `RegisterConsoleCommandGlobalHandler` | Real console commands (`cta_unlockall`) instead of a pile of function keys |
| `NotifyOnNewObject` | React the moment an object appears - the bino camera, a garage entry - instead of polling |
| `ForEachUObject` | Walk every object to find a subsystem instance, rather than guessing class names |
| `UWorld:SpawnActor`, `UUserWidget` | Spawn actors and build UI. We never made a single widget |
| `RegisterCustomEvent` | Let two mods talk to each other |
| `TArray`, `TMap`, `TSet` | Handle array properties properly. We avoided arrays entirely because reading them was awkward |
| `ExecuteInGameThread` | Run engine calls on the game thread. Our timers run on the async thread, which works but is the riskier side of the line |
| Blueprint mods (`BPModLoaderMod` + LogicMods) | Add content without Lua at all |
| C++ mods (UHT headers, SDK dump) | Reach anything the reflection system hides |

Real-world framing: in other UE games these are the everyday tools.
DataTable editing is how people rebalance loot and stats; Blueprint mods
and console commands are how people add content. This project wrote one
Lua script against object properties and stopped there.

## 4. Ground rules for whoever picks this up

Learned the hard way, all of it in `docs/api-notes.md`:

1. **Enumerate before reading.** A property name that does not exist
   hard-crashes this game, and `pcall` does not catch it.
2. **No null object reads.** Half a dozen freezes came from one empty VFX
   pointer.
3. **Probe first, change second.** Every successful step in this project
   started with a names-only dump.
4. **Test in game before claiming it works.** This project has shipped
   three "fixes" that were syntactically perfect and behaviourally wrong
   until someone pressed a key in a tank.