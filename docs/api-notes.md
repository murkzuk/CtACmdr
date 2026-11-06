# Game internals - Call to Arms: Panzer Elite

Everything here was read out of the running game with UE4SS 3.0.1
reflection, or mined from the shipping exe.

- Engine: **UE 5.4.4**
- Game module: `/Script/Panzer_Elite_2`
- Steam appid: **1343070**
- Content: one 28.9 GB `pakchunk0-Windows.pak`, **pak v11, index not
  encrypted, Oodle compressed**. No `.sig` files. No anti-cheat.

## HARD RULES - read before writing any code

These cost a lot of crashes to learn.

1. **Never read a property name that might not exist.**
   `obj["MadeUpName"]` does not return nil, it crashes the game.
   Always enumerate names with `ForEachProperty` first and read only those.

2. **Never read a null object property.**
   `pawn["TracesVFX_LeftBack"]` was null and killed the game.

3. **Never call a native function without the exact argument list.**
   Get the signature first, from `UFunction:ForEachProperty`.

3b. **Some functions are fatal even with correct arguments.** Confirmed
   crashes, called with the exact signature the game reported:
   - `BinocularsComponent:StartUsingBinoculars()`
   - `CrewManagerComponent:OnBinocularsStateChanged(1)`
   Both presumably expect the game's own call order or internal state.
   Drive these systems through their properties or by hooking, not by
   calling handlers directly.

4. **Safe:** `FindAllOf`, `FindFirstOf`, `StaticFindObject`,
   `ForEachProperty`, `ForEachFunction`, `UEnum:ForEachName`,
   `GetFName`, `GetFullName`, `GetClass`, `GetSuperStruct` (mostly).

5. **Safe and useful:** writing scalar and struct properties.
   `zoom.MinCamDistance = 0.0` works.
   `arm.SocketOffset = { X = 0, Y = 0, Z = 0 }` works, and reads back.

6. `FindAllOf("ClassName")` matches the **exact** class only, not
   subclasses. A blueprint subclass like `BP_BinocularsComponent_C`
   will not be found by `FindAllOf("BinocularsComponent")`.

## How the camera actually works

One camera, driven by a spring arm:

```
FollowSpringArm  (SpringArmComponent)  TargetArmLength = 500
  FollowCamera   (CameraComponent)     FieldOfView = 90
```

The visible camera sits at the end of that arm, 500 cm behind the pivot.
Verified: with the arm at 500 the camera was exactly 500.9 units from
the arm origin.

The "scroll into the gunsight" is the ZoomComponent shortening the arm
toward `MinCamDistance` (150). It re-asserts that every frame, so
setting the arm alone does not hold.

**To hold the camera at the pivot:**

```
zoom.MinCamDistance     = 0
zoom.DefaultCamDistance = 0
zoom:SetCamDistanceTarget(0)
```

Do **not** also set `MaxCamDistance = 0` - min == max risks a divide
by zero inside the zoom maths.

At arm length 0 the camera lands on the commander. From there
`FollowSpringArm.SocketOffset` moves it, in centimetres, relative to
the arm's parent space.

Measured positions on a PzKpfw IV Ausf G:

```
pawn origin        38098.1  52976.0  2304.7
mesh origin        38098.1  52976.0  2304.7
Crew_Commander     38145.6  52891.1  2573.1
follow arm origin  38119.3  52933.9  2597.0
camera at arm 500  38420.2  52535.7  2639.1
```

The follow arm origin is about 56 cm from the commander mesh origin.

## PE2Vehicle  (/Script/Panzer_Elite_2.PE2Vehicle)

Selected properties:

```
EyesBoneName            Name
LookInputHandler        Enum    EVehicleLookInputHandlerType
FireInputHandler        Enum
Mesh                    Object  VehicleSkeletalMeshComponent
FollowSpringArm         Object  SpringArmComponent
FollowCamera            Object  CameraComponent
ZoomViewSpringArm       Object  SpringArmComponent
ZoomViewCamera          Object  CameraComponent
Zoom                    Object  ZoomComponent
Binoculars              Object  BinocularsComponent
CrewComponent           Object
PassengersComponent     Object
WeaponryComponent       Object
HealthComponent         Object
AimPointsComponent      Object
VehicleLookInfo         Struct
VehicleType             Enum
GarageCamera            Enum
bIsPossessedByPlayerController  Bool
```

Functions:

```
SetLookInputHandlerType(NewType Enum)
SetFireInputHandlerType(NewType Enum)
SetIsPossessedByPlayerController(bPossessed Bool)
SetLookCustomizations(LookInfo Struct)
ApplyVehicleLookCustomizations()
GetCameraRotation() -> Struct
SetCanBeSpotted(bNewCanBeSpotted Bool)
```

## PE2TrackedVehicle

```
LeftTrackSpline   LeftTreadMesh
RightTrackSpline  RightTreadMesh
```

## BinocularsComponent

```
Setup                 Object   -> DA_BinocularsSetup_Basic
bBinocularsAvailable  Bool
BinocularsOrientation Struct
CurrentState          Enum     EBinocularsState   (None=0, InUse=1)
CurrentCameraActor    Object   the bino camera, created on demand
```

```
StartUsingBinoculars()                        <- takes no args, but
                                                 calling it directly
                                                 crashed the game
StopUsingBinoculars()
SetBinocularsAvailable(bNewAvailable Bool)
GetCurrentCameraActor(bHasCamera Bool) -> Object
GetCameraSwitchType() -> Enum
GetBinocularsBone() -> Name
```

`GetCurrentCameraActor` needs its out-parameter passed in, which is why
calling it bare returned `ok=false`.

## ZoomComponent

Values as shipped, on a fresh PzKpfw IV:

```
MinCamDistance              150
MaxCamDistance              800
DefaultCamDistance          500
DefaultFieldOfView          50
CamDistanceZoomTime         0.05
CamFOVZoomSpeed
DeltaCamDistance
bStabilizeOnZoom            true
RelativeZoomCameraPitchLimit  20
RelativeZoomCameraYawLimit    45
MagnificationFactors        Array
```

```
SetCamDistanceTarget(InCamDistanceTarget Float)
GetCameraArmLength() -> Float
IsInZoom() -> Bool
GetZoomLevel() -> Int
ZoomIn(IsGamepadUsed Bool)
ZoomOut()
EnableZoom()
DisableZoom()
ClientDisableZoom(DistanceFactor Float)
SetMaxZoom()
QuickZoom()
```

## CrewManagerComponent

```
CrewMembers                 Array
OnBinocularsOnTag           Struct  (gameplay tag)
OnBinocularsOffTag          Struct
OnMachineGunOnTag           Struct
OnMachineGunOffTag          Struct
OnMachineGunReloadTag       Struct
CrewOperatedWeaponCategory  Enum
CrewOperatedWeapons         Map
```

```
SetAllCrewAnimsHidden(bNewHidden Bool)
SetStateForAllCrewAnims(NewState Enum, CurrentHealth Float)
PlayCrewMemberAnimation_ByRole(CrewMemberRole Enum, bOnlyIfAlive Bool,
                               AnimationTag Struct, Type Enum)
PlayCrewMemberAnimation_ByID(CrewMemberID Name, bOnlyIfAlive Bool,
                             AnimationTag Struct, Type Enum)
```

## CrewMemberSkeletalMeshComponent

```
SkeletalMeshes  Map
```

One per crewman. On the PzKpfw IV blueprint the commander is the
component property `Crew_Commander`. Its `bVisible` was false while
buttoned up.

## VehicleHatch  (ScriptStruct)

```
HatchName  Name
bOpen      Bool
```

## VehicleComponent

```
Identifier      Name      e.g. "Hull"
ComponentType   Enum      EVehicleComponentType
CrewRole        Byte      ECrewRole
Bones           Array     e.g. "armor_Glacis", "armor_driver_plate"
MaxHealth       Float     e.g. 220.0
CurrentHealth   Float
ComponentFlags  Byte
RepairTime      Float
RepairPriority  Int
```

```
IsCrewComponent() -> Bool
IsCrewComponentWithRole(InCrewRole Enum) -> Bool
GetCrewRoles() -> Array
```

## Blueprint components on BP_PzKpfwIVAusfG_C

```
CrewManager  Crew_Commander  BP_CrewAnimation
hatch_01 .. hatch_07, hatch_02_1, hatch_03_1
engine_hatch_L  engine_hatch_R
gun  gun_rot  gun_turret  gun_turret_antenna_l_01
mgun_hull  mgun_rot  mgun_turret
Body  body_decal
Wheel_L_01..10  Wheel_R_01..10  suspension_rollers  shield_*  VFX
```

## Key enums

```
EVehicleLookInputHandlerType   None=0  ZoomComponent=1  BinocularsComponent=2
ECrewRole                      Commander=0 Driver=1 Gunner=2 Loader=3
                               RadioOperator=4 Crew=5
EBinocularsState               None=0 InUse=1
EBinocularsCameraSwitchType    Slow=0 Fast=1
EBinocularsCameraParameter     FOV=0 PostProcessStrength=1
EBinocularsLimitType           None / Absolute / RelativeToBone / RelativeToActor
EBinocularsTransitionDirection None=0 Into=1 OutOf=2
```

The full set, 67 enums with every value, is in `game-enums.txt`.

## Open questions

- ~~Does raising the binoculars still work while the commander view is
  on?~~ **Yes, confirmed in game.** They use a separate camera actor so
  they are unaffected by the follow arm being pinned.
- `VehicleLookInfo` / `SetLookCustomizations` is the game's own look
  customisation path and was never explored.
- `EyesBoneName` read back empty on the PzKpfw IV, so it is not the
  commander eye bone.