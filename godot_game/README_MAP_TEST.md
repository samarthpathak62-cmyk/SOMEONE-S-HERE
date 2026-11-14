# SOMEONE'S HERE: Mile 47 map test (Godot 4)

Map: `assets/mile47/gas_station.glb` (one pre-assembled gas station: store, canopy, pumps, shop interior, fridges, shelves, toilets, cameras, fuse box, trees and highway road).

The old pack (Gas_Store, Gas_Station, Camp, Roads, Rocks, Vegetation, utility poles, 3D_Retro_World zip, gallery) has been removed. Nothing else from it is placed on the map.

## Controls
| Key | Action |
|---|---|
| WASD / Mouse | Move / look |
| Shift / Ctrl (C) | Sprint / crouch |
| Space | Jump |
| RMB (hold) | Zoom |
| **E** | **Interact with the object under the crosshair** |
| F | Flashlight on/off |
| P | Phone up/down (3D phone + message screen) |
| B | Broom on/off |
| V | Noclip fly on/off (E then flies up, so E interacts only in walk mode) |
| L | Night horror / bright daylight inspection light |
| G | VHS overlay on/off |
| H | Hide HUD |
| 1 / 2 | Teleport to forecourt / inside the shop |
| ESC | Toggle mouse capture |

## Animations (scripted, `scripts/map_loader.gd`)
The GLB has no baked animation. These are added by code:

| Object kind | Behaviour |
|---|---|
| Doors (store, toilets, fuse box door) | Hinged swing open/close, creak sound (E) |
| Fridge lids, dumpster lid | Lift open/close (E) |
| Security cameras | Idle sweep, always on |
| Ceiling lamps, spotlight, logo, sign | Flicker with occasional dropout, always on |
| Fuel pumps, coffee/ice/slush machines, dispenser, fuse box parts | Vibrate (E) |
| Shelves, desks, chairs, boxes, boards, fridge, dumpster, counters | Knock/wobble (E) |
| Small products (food, drinks, cups, etc.) | Pick up and put back (E) |
| Trees, bushes, background, ground, road | Scenery, no interaction |

## Collision
- One box collider per solid mesh part (walls, pumps, pillars, counters, fridges, doors).
- Trees, bushes, background, ground, road, flat tiles and tiny items do not block the player.
- Small items and lids get non-blocking boxes that only the inspector and E use.
- No trimesh (ConcavePolygon) colliders, because they crashed the physics engine (Illegal Instruction).
- Physics engine: GodotPhysics3D (`project.godot`).
- The inspector does not use physics raycasts. It tests the `inspectable` boxes with plain ray-vs-box maths.

## Not yet done (waiting for playtest feedback)
- Interior furniture pieces beyond what is in the GLB.
- Vehicles (car, truck), enemy character, story acts, AI, sound design per object.
- Animations are simple scripted tweens, not Blender-authored motion. Tune them after testing.

## Run
Open `project.godot` in Godot 4.7 and press F5 (main scene: `scenes/main_map_test.tscn`).
