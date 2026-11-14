# SOMEONE'S HERE — Godot 4 Map & Controls Test (`godot_game/`)

## 📁 Folder structure
```
godot_game/
├── project.godot
├── scenes/            player.tscn, main_map_test.tscn
├── scripts/           player_controller.gd, map_loader.gd, main_map_test.gd
├── shaders/           vhs_psx_overlay.gdshader
└── assets/
    ├── map/                       ← Mutum 3D_Retro_World models (Props/Gas_Store, Gas_Station, Camp, Roads, Rocks, Vegetation)
    ├── fewitemsandmodels/         ← flashlight, cell_phone, broom, knife, dirty_car, abandoned car, truck
    ├── Model1withanimations/      ← 8 animation .fbx + Male_Character_PSX/ (character + texture)
    ├── audio/                     ← wind + crickets loops, flashlight click, phone beep, door creak (procedural placeholders)
    ├── Utility Infrastructure.zip ← electric poles, lamps, transformer
    └── 3D_Retro_World 0.01.zip    ← Git LFS pointer in repo: drop the real zip here on your PC
```

## 🚀 Kaise chalayein
1. **Godot 4.x** (4.2+) kholo → **Import** → `godot_game/project.godot` select karo.
2. **Pehli baar** Godot sab `.glb` / `.fbx` / `.wav` import karega — 1–3 min lag sakte hain. Ek baar complete hone do.
3. **F5** dabao.

### `3D_Retro_World 0.01.zip` ke liye
- Repo me ye file 134-byte Git LFS pointer hai (asli zip GitHub LFS pe hai).
- Apne PC pe asli zip ko **`godot_game/assets/`** me copy kar do (ya game chalte waqt window pe drag & drop karo). Game use automatically extract karke Gas Station, Trees, Roads, Camp load kar dega.

---

## 🏪 Mile 47 Gas & Mart (ab assembled hai)
- **Store shell 12m × 8m**: 3m walls, front door + window, back door (backroom), corner pillars, floor, roof, dark ceiling.
- **Canopy 6m × 6m** (3×3 GasRoof tiles, 6m pillars), **4 pumps** (2 islands), 2 canopy lamps, price board.
- **Campsite** (Zone 2): tent, bonfire + fire light, cooker + pans, sleeping bag, ice box + cover, lantern, bag, bottle.
- Jo pieces layout me use nahi hue unhe **`[unassembled]`** label ke saath map ke north side (z = -62) me rakha hai.
- **Abhi shop ke andar koi shelves / counter / fridge nahi hain** — wo next step me banenge.

## 🧍 Enemy character
- `Male_Character_PSX/MaleCharacter.fbx` + saari 8 animations ek hi skeleton pe attach hain.
- Default: **Idle** loop. **`N`** dabao to next clip (Walking, Running, Crouched_Walking, Talking, Look_Around, Melee_Attack, killing) play hogi.

---

## 🎮 Controls
| Key | Action |
| :--- | :--- |
| **`W A S D`** | Chalna (head-bob + footsteps) |
| **`Shift`** | Sprint |
| **`Ctrl` / `C`** | Crouch |
| **`Space`** | Jump (Noclip mode me upar) |
| **`Right Mouse (Hold)`** | Squint / Focus zoom |
| **`F`** | Flashlight ON/OFF (click sound) |
| **`P`** | Phone raise / put away — 3D phone chehre tak uthta hai aur messages wali screen khulti hai (SMS beep) |
| **`B`** | Broom haath me |
| **`V`** | **Noclip fly** — deewar ke aar-paar ghus kar interior check karo |
| **`L`** | Night horror ↔ bright inspector daylight |
| **`G`** | VHS / PSX filter ON/OFF |
| **`N`** | Enemy animation clip next |
| **`1` `2` `3` `4`** | Teleport: Station / Campsite / Gallery / Showcase |
| **`Tab`** | Full asset list (har model ke saath Teleport button) |
| **`H`** | HUD hide/show |
| **`Esc`** | Mouse free / lock |

## 🔧 Crash fix (Illegal Instruction)
- Pehle collision ke liye `ConcavePolygonShape3D` (trimesh) use hota tha; Gas_Pilar par raycast hone pe crash hua.
- Ab har mesh ko **BoxShape3D** collider milta hai, aur trees/bushes par collision nahi (walk-through).
- Physics engine **GodotPhysics3D** set kiya hai (`project.godot`).

## 📱 Phone (Fears to Fathom style)
- P dabane par phone haath se uthkar chehre ke saamne aata hai, screen glow karti hai, aur messages ka overlay khulta hai.
- Messages abhi placeholder hain (`scripts/phone_screen.gd` ke `MESSAGES` me edit kar sakta hai).

## ⚠️ Known limits (abhi)
- Ye game engine me test nahi hua hai jab tak aap run na karein — pehli run pe kuch pieces ka pivot/size tweak lag sakta hai.
- Audio files **placeholder** (procedural) hain; baad me real sounds se replace kar sakte ho (same naam).
- `sfx_door_creak.wav` abhi kisi key se trigger nahi hai (doors ka interaction next phase me).

## 🏪 Main map: Mile 47 full gas station (naya)
- Main map ab `assets/mile47/gas_station.glb` hai (store + canopy + pumps + interior + trees + road, pre-assembled).
- Collision: har solid mesh par box collider. Trees, bushes, background, ground, road aur chhoti/flat items par collision nahi.
- Player forecourt (5, 0.25, 3) se start hota hai, store ka entrance north (-Z) par hai.
- Hand-built store/canopy layout ab band hai (overlap se bachne ke liye). Camp props Zone 2 clearing me hain (pack se).
- Store ke andar `Fusible` (breaker box) bhi model me hai. Doors abhi static hain, animation baad me.
