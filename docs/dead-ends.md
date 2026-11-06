# The grander plan, and why it stalled

Written up so nobody repeats it. This is the "reverse the animation" idea:
have the commander open the hatch, pop up, stay up, and ride his actual
head. Then a bino view on top.

Status: **dead end, parked.** The working commander view does not depend
on any of this.

## What was confirmed working

- The whole call sequence is visible and hookable.
- Blocking calls and swallowing notifications both work.
- Widget visibility, camera FOV and post-process blend weight all write
  and hold, verified by sampling 20 times over 3 seconds.
- The game can be driven with the binos raised.

## What was found

The commander is a real mesh: `Crew_Commander`, a
`CrewMemberSkeletalMeshComponent` on the tank blueprint. He has climb
animations per vehicle, for example:

```
Content/Vehicles/M4A3_75/Animations/A_binocular_crew_M4A3_75_climb_in_hatch_01
Content/Vehicles/M4A3_75/Animations/A_binocular_crew_M4A3_75_climb_out_hatch_01
```

The bino view is a per-vehicle camera blueprint:

```
Content/Blueprints/Components/Binoculars/Cameras/BP_Binoculars_PZIVG
Content/Blueprints/Components/Binoculars/PPMaterials/M_PP_Binoculars_basic
```

And the call order, from the hooks:

```
raise:  binos START()  ->  crew OnBinocularsStateChanged(1)    1 = InUse
lower:  binos STOP()   ->  crew OnBinocularsStateChanged(0)    0 = None
```

`SetStateForAllCrewAnims(2, 0.0)` also fires during normal play.

## The two fatal moves

Both were called with the exact signature the game reports, and both
crashed it:

- `BinocularsComponent:StartUsingBinoculars()`
- `CrewManagerComponent:OnBinocularsStateChanged(1)`

Presumably each expects the game's own call order or internal state.
Hooking them is fine. Calling them is not.

## The wall: the mask

The bino mask and the range scale would not go away. Every theory was
tested and eliminated:

| Tried | Result |
| --- | --- |
| `Camera.FieldOfView = 90` | worked, view widened, mask stayed |
| `Camera.PostProcessBlendWeight = 0` | wrote, read back 0, held 3 seconds, mask stayed |
| re-assert both every 60 ms | no change |
| `PostProcessComponent` on the bino actor | none exists |
| `WBP_Vignette` `Visibility = 1` | wrote, read back 1, held, mask stayed |
| crosshair widgets collapsed | wrote, held, scale stayed |
| post process volumes | only the level lighting volume, priority 12 |

The mask scales with the screen, not with the field of view, so it is
screen space: a post-process material, a camera modifier, or a widget.
It is none of the four we could reach. `M_PP_Binoculars_basic` exists but
no `MaterialInstanceDynamic` for it was found at runtime, so the weight
cannot be reached through a parameter either.

## Where to look next, if anyone picks this up

1. **Camera modifiers.** `APlayerCameraManager` holds modifiers, and a
   modifier can add post-process blendables. Enumerate
   `CameraModifier` instances while the binos are raised. This is the
   most likely holder and the one path never tested.
2. **`PostProcessSettings.WeightedBlendables`.** The material is almost
   certainly a blendable entry with its own weight. It sits in a nested
   struct array that plain Lua property reads cannot reach cleanly, but
   a C++ UE4SS mod or a struct-aware approach could zero it.
3. **Swap the material at runtime.** If a blendable holds
   `M_PP_Binoculars_basic`, replacing that material reference with a
   transparent one would work regardless of weights.

## The useful side step that also did not land

Reading the bino camera's world position and adding the difference to
the follow arm's `SocketOffset` should have put our own mask free
camera exactly where the bino camera sits. The measurement works and the
numbers are logged; the resulting view did not land where expected,
probably because `SocketOffset` is in parent space and the tank is
yaw rotated relative to world space. Rotating the delta into the arm's
space before writing it is the obvious unfinished step.
