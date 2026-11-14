extends Node3D
class_name RetroMapLoader

signal loading_status_updated(summary_text: String, lfs_warning: bool)
signal manifest_updated(entries: Array)

var asset_manifest: Array = []
var retroworld_loaded: bool = false
var retroworld_lfs_pointer_detected: bool = false

var _world_root: Node3D
var _dynamic_pack_root: Node3D
var _gallery_root: Node3D
var _placeholder_station: Node3D
var _station_interior_lights: Array[OmniLight3D] = []
var enemy_anim_player: AnimationPlayer = null
var enemy_clip_names: PackedStringArray = []
var enemy_clip_index: int = -1

const ENEMY_MODEL_RES: String = "res://assets/Model1withanimations/Male_Character_PSX/MaleCharacter.fbx"
const ENEMY_TEX_RES: String = "res://assets/Model1withanimations/Male_Character_PSX/MaleCharacter_Texture.png"
const ENEMY_LOOPING_CLIPS: Array[String] = ["Idle", "Walking", "Running", "Crouched_Walking", "Talking", "Look_Around"]

var _project_dir: String = ""
var _repo_root: String = ""
var _extract_cache_root: String = ""

# Teleport landmarks populated during map build
var landmark_station: Vector3 = Vector3(0.0, 0.2, 9.0)
var landmark_campsite: Vector3 = Vector3(44.0, 0.2, -26.0)
var landmark_gallery: Vector3 = Vector3(-36.0, 0.2, 32.0)
var landmark_showcase: Vector3 = Vector3(-34.0, 0.2, 6.0)


func _ready() -> void:
	_project_dir = ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	_repo_root = _project_dir.get_base_dir()
	_extract_cache_root = ProjectSettings.globalize_path("user://extracted_packs").replace("\\", "/").trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(_extract_cache_root)

	_world_root = Node3D.new()
	_world_root.name = "GeneratedWorld"
	add_child(_world_root)

	_dynamic_pack_root = Node3D.new()
	_dynamic_pack_root.name = "RetroWorldAssets"
	_world_root.add_child(_dynamic_pack_root)

	_gallery_root = Node3D.new()
	_gallery_root.name = "AssetGalleryGrid"
	_world_root.add_child(_gallery_root)

	_build_base_ground_and_highway()


func build_all_and_equip_player(player: HorrorPlayerController) -> void:
	asset_manifest.clear()

	# 1. Load Player Handhelds + Uploaded Items & Vehicles (fewitemsandmodels/)
	var items_dir: String = _find_existing_dir([
		_project_dir.path_join("assets/fewitemsandmodels"),
		_repo_root.path_join("fewitemsandmodels")
	])
	_load_uploaded_items_and_vehicles(items_dir, player)

	# 2. Load Enemy Character Preview (Model1withanimations/)
	_load_enemy_character_preview()

	# 3. Extract & Place Utility Infrastructure Electric Poles along Highway
	_load_utility_infrastructure()

	# 4. Auto-discover, Extract & Place Mutum Studios 3D_Retro_World Pack
	_discover_and_load_retroworld()

	_emit_final_summary()
	manifest_updated.emit(asset_manifest)


func load_dropped_paths(paths: PackedStringArray) -> void:
	var loaded_any: bool = false
	var collected_models: Array[Dictionary] = []

	for raw_p in paths:
		var p: String = raw_p.replace("\\", "/")
		if DirAccess.dir_exists_absolute(p):
			_scan_model_files_recursive(p, p.get_file(), collected_models)
			loaded_any = true
		elif FileAccess.file_exists(p):
			var lower: String = p.to_lower()
			if lower.ends_with(".zip"):
				var fsize: int = _get_file_size(p)
				if fsize > 2048:
					var out_dir: String = _extract_zip_cached(p, "dropped_" + p.get_file().get_basename().validate_filename())
					if not out_dir.is_empty():
						_scan_model_files_recursive(out_dir, p.get_file().get_basename(), collected_models)
						loaded_any = true
			elif lower.ends_with(".glb") or lower.ends_with(".gltf"):
				collected_models.append({
					"abs_path": p,
					"rel_path": p.get_file(),
					"pack": "Dropped"
				})
				loaded_any = true

	if loaded_any and not collected_models.is_empty():
		retroworld_loaded = true
		retroworld_lfs_pointer_detected = false
		if _placeholder_station != null and is_instance_valid(_placeholder_station):
			_placeholder_station.queue_free()
			_placeholder_station = null
		_populate_retroworld_models(collected_models)
		_emit_final_summary()
		manifest_updated.emit(asset_manifest)


# ============================================================================
# BASE GROUND, HIGHWAY-9 & PLACEHOLDER MARKERS
# ============================================================================

func _build_base_ground_and_highway() -> void:
	# Walkable dark forest earth (520m x 520m)
	var ground_sb := StaticBody3D.new()
	ground_sb.name = "ForestGround"
	ground_sb.set_meta("asset_label", "Base Terrain: Forest Ground (520m x 520m)")
	var ground_col := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(520.0, 1.0, 520.0)
	ground_col.shape = ground_box
	ground_col.position = Vector3(0.0, -0.5, 0.0)
	ground_sb.add_child(ground_col)

	var ground_mi := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(520.0, 0.2, 520.0)
	ground_mi.mesh = ground_mesh
	ground_mi.position = Vector3(0.0, -0.1, 0.0)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.08, 0.095, 0.075)
	ground_mat.roughness = 0.96
	ground_mi.material_override = ground_mat
	ground_sb.add_child(ground_mi)
	_world_root.add_child(ground_sb)

	# State Highway-9 Asphalt Strip (runs East-West along Z = 0, width 11m, length 320m)
	var road_mi := MeshInstance3D.new()
	road_mi.name = "HighwayAsphalt"
	var road_mesh := BoxMesh.new()
	road_mesh.size = Vector3(320.0, 0.05, 11.0)
	road_mi.mesh = road_mesh
	road_mi.position = Vector3(0.0, 0.015, 0.0)
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.11, 0.115, 0.125)
	road_mat.roughness = 0.84
	road_mi.material_override = road_mat
	_world_root.add_child(road_mi)

	# Yellow dashed highway center line
	var dash_mat := StandardMaterial3D.new()
	dash_mat.albedo_color = Color(0.78, 0.62, 0.16)
	dash_mat.roughness = 0.7
	for i in range(-26, 27):
		var dash := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(2.8, 0.02, 0.16)
		dash.mesh = dm
		dash.position = Vector3(float(i) * 6.0, 0.042, 0.0)
		dash.material_override = dash_mat
		_world_root.add_child(dash)

	# Concrete Gas Station Forecourt Pad (Z = -22, 48m x 32m)
	var apron := MeshInstance3D.new()
	apron.name = "StationForecourtConcrete"
	var apron_mesh := BoxMesh.new()
	apron_mesh.size = Vector3(48.0, 0.04, 32.0)
	apron.mesh = apron_mesh
	apron.position = Vector3(0.0, 0.01, -21.0)
	var apron_mat := StandardMaterial3D.new()
	apron_mat.albedo_color = Color(0.16, 0.165, 0.175)
	apron_mat.roughness = 0.88
	apron.material_override = apron_mat
	_world_root.add_child(apron)

	# Zone Signposts so player always knows what each area is
	_spawn_zone_signpost(Vector3(0.0, 0.0, -6.2), "ZONE 1: GAS STATION & HIGHWAY [Key 1]", Color(1.0, 0.86, 0.45))
	_spawn_zone_signpost(Vector3(44.0, 0.0, -29.0), "ZONE 2: FOREST CAMPSITE [Key 2]", Color(1.0, 0.62, 0.30))
	_spawn_zone_signpost(Vector3(-36.0, 0.0, 35.0), "ZONE 3: ALL PACK MODELS GALLERY [Key 3]", Color(0.55, 0.90, 1.0))
	_spawn_zone_signpost(Vector3(-34.0, 0.0, 1.5), "ZONE 4: UPLOADED CARS, ITEMS & ENEMY [Key 4]", Color(0.75, 1.0, 0.65))


func _spawn_lfs_placeholder_station() -> void:
	if _placeholder_station != null:
		return
	_placeholder_station = Node3D.new()
	_placeholder_station.name = "PlaceholderStationNotice"
	_placeholder_station.position = Vector3(0.0, 0.0, -22.0)

	var frame := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(16.0, 4.5, 10.0)
	frame.mesh = bm
	frame.position = Vector3(0.0, 2.25, 0.0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.25, 0.18, 0.18)
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.22, 0.15)
	mat.emission_energy_multiplier = 0.4
	frame.material_override = mat
	_placeholder_station.add_child(frame)

	var lbl := Label3D.new()
	lbl.text = "3D_Retro_World 0.01.zip is a 134-byte Git LFS pointer in this folder!\n\nDrag & Drop your real '3D_Retro_World 0.01.zip' (or unzipped folder)\ndirectly onto this game window — the Gas Station, Roads, Trees & Camp\nwill extract and spawn right here automatically!"
	lbl.font_size = 38
	lbl.pixel_size = 0.008
	lbl.modulate = Color(1.0, 0.90, 0.55)
	lbl.outline_size = 10
	lbl.position = Vector3(0.0, 3.2, 5.2)
	_placeholder_station.add_child(lbl)

	_world_root.add_child(_placeholder_station)


# ============================================================================
# UPLOADED PROPS, VEHICLES & PLAYER HANDHELDS (fewitemsandmodels/)
# ============================================================================

func _load_uploaded_items_and_vehicles(items_dir: String, player: HorrorPlayerController) -> void:
	var flash_hand: Node3D = null
	var phone_hand: Node3D = null
	var broom_hand: Node3D = null

	if not items_dir.is_empty():
		var flash_path: String = items_dir.path_join("flashlight.glb")
		if FileAccess.file_exists(flash_path):
			flash_hand = _instantiate_gltf_or_fbx(flash_path)

		var phone_path: String = items_dir.path_join("cell_phone.glb")
		if FileAccess.file_exists(phone_path):
			phone_hand = _instantiate_gltf_or_fbx(phone_path)

		var broom_path: String = items_dir.path_join("broom_wood_-_5mb.glb")
		if FileAccess.file_exists(broom_path):
			broom_hand = _instantiate_gltf_or_fbx(broom_path)

		# Place Vehicles on Highway & Station Lot with exact real-meter scales!
		var dirty_car_path: String = items_dir.path_join("dirty_car.glb")
		if FileAccess.file_exists(dirty_car_path):
			# Measured raw size = [262.06, 178.61, 600.78] -> 0.0078 scale = 4.69m sedan!
			_place_known_prop(dirty_car_path, "Uploaded Vehicle", "dirty_car.glb (Stalker Sedan)", Vector3(26.0, 0.02, -3.2), 78.0, 0.0078, true)

		var aban_car_path: String = items_dir.path_join("lowpoly_abandoned_simple_car_prop_-_game_ready.glb")
		if FileAccess.file_exists(aban_car_path):
			# Measured raw size = [70.33, 24.31, 28.74] -> 0.065 scale = 4.57m car!
			_place_known_prop(aban_car_path, "Uploaded Vehicle", "abandoned_car.glb", Vector3(-25.0, 0.02, -16.0), 22.0, 0.065, true)

		var truck_path: String = items_dir.path_join("truck.glb")
		if FileAccess.file_exists(truck_path):
			# Measured raw size = [3.45, 4.51, 15.91] -> already in meters!
			_place_known_prop(truck_path, "Uploaded Vehicle", "truck.glb (Highway Escape Truck)", Vector3(-42.0, 0.04, 2.7), 90.0, 1.0, true)

		# Also line up tabletop showcase of handheld items in Zone 4 (-34, 0, -5)
		_build_zone4_item_table(items_dir)

	if player != null:
		player.attach_handheld_models(flash_hand, phone_hand, broom_hand)


func _build_zone4_item_table(items_dir: String) -> void:
	# Pedestal table for inspecting small items (flashlight, phone, knife, broom)
	var table_sb := StaticBody3D.new()
	table_sb.name = "ShowcaseTable"
	table_sb.position = Vector3(-34.0, 0.0, -5.5)
	table_sb.set_meta("asset_label", "Zone 4 Inspection Table (Uploaded Props)")
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(6.5, 0.95, 1.6)
	cs.shape = bx
	cs.position = Vector3(0.0, 0.475, 0.0)
	table_sb.add_child(cs)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(6.5, 0.95, 1.6)
	mi.mesh = bm
	mi.position = Vector3(0.0, 0.475, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.17, 0.14)
	mi.material_override = mat
	table_sb.add_child(mi)

	var spot := OmniLight3D.new()
	spot.position = Vector3(0.0, 3.2, 0.6)
	spot.light_color = Color(1.0, 0.95, 0.85)
	spot.light_energy = 2.4
	spot.omni_range = 11.0
	table_sb.add_child(spot)
	_world_root.add_child(table_sb)

	var specs: Array[Dictionary] = [
		{"file": "flashlight.glb", "scale": 0.65, "pos": Vector3(-36.2, 0.96, -5.5), "label": "flashlight.glb [Press F in hand]"},
		{"file": "cell_phone.glb", "scale": 1.4, "pos": Vector3(-34.8, 0.96, -5.5), "label": "cell_phone.glb [Press P in hand]"},
		{"file": "utility_knife.glb", "scale": 0.007, "pos": Vector3(-33.3, 0.96, -5.5), "label": "utility_knife.glb (Killer Weapon)"},
		{"file": "broom_wood_-_5mb.glb", "scale": 0.0065, "pos": Vector3(-31.5, 0.02, -5.5), "label": "broom_wood.glb [Press B in hand]"}
	]
	for sp in specs:
		var fp: String = items_dir.path_join(str(sp["file"]))
		if FileAccess.file_exists(fp):
			_place_known_prop(fp, "Uploaded Prop", str(sp["label"]), sp["pos"], 0.0, float(sp["scale"]), true)


func _load_enemy_character_preview() -> void:
	var anim_dir: String = _project_dir.path_join("assets/Model1withanimations")
	if not DirAccess.dir_exists_absolute(anim_dir):
		return

	# Every animation FBX in the folder becomes a clip on the character
	var clip_files: PackedStringArray = []
	var d := DirAccess.open(anim_dir)
	if d != null:
		d.list_dir_begin()
		var fn: String = d.get_next()
		while not fn.is_empty():
			if not d.current_is_dir() and fn.to_lower().ends_with(".fbx"):
				clip_files.append(fn)
			fn = d.get_next()
		d.list_dir_end()
	clip_files.sort()

	var enemy_pos := Vector3(-29.0, 0.02, -5.5)
	var char_root: Node3D = _load_res_scene(ENEMY_MODEL_RES)
	if char_root == null:
		push_warning("Enemy model not imported yet: %s (open the project once in the editor so Godot imports it)" % ENEMY_MODEL_RES)
		return
	char_root.name = "EnemyMaleCharacter"

	if ResourceLoader.exists(ENEMY_TEX_RES):
		var tex := load(ENEMY_TEX_RES) as Texture2D
		if tex != null:
			_apply_psx_texture_recursive(char_root, tex)

	var aabb: AABB = compute_node_aabb(char_root)
	var sc: float = 1.0
	if aabb.size.y > 0.01 and (aabb.size.y > 4.0 or aabb.size.y < 0.5):
		sc = 1.78 / aabb.size.y
	char_root.scale = Vector3.ONE * sc
	var center_offset := Vector3(aabb.position.x + aabb.size.x * 0.5, aabb.position.y, aabb.position.z + aabb.size.z * 0.5) * sc
	char_root.position = enemy_pos - center_offset
	_world_root.add_child(char_root)
	_add_trimesh_collisions_recursive(char_root, "Enemy Model: MaleCharacter.fbx")

	# Attach all clips (needs the character in the tree so skeleton paths resolve)
	enemy_anim_player = _attach_clips(char_root, clip_files)
	if enemy_anim_player != null:
		enemy_clip_names = enemy_anim_player.get_animation_list()
		if enemy_anim_player.has_animation("Idle"):
			enemy_anim_player.play("Idle")

	_spawn_floating_label(
		enemy_pos + Vector3(0.0, 2.35, 0.0),
		"ENEMY: MaleCharacter PSX\nClips (%d): %s" % [enemy_clip_names.size(), ", ".join(enemy_clip_names)],
		Color(1.0, 0.55, 0.55)
	)
	asset_manifest.append({
		"category": "Enemy & Animations",
		"name": "MaleCharacter.fbx + %d clips (%s)" % [enemy_clip_names.size(), ", ".join(enemy_clip_names)],
		"size_text": "1.78m Humanoid",
		"meshes": enemy_clip_names.size(),
		"pos": enemy_pos + Vector3(0.0, 0.2, 3.8)
	})


# Loads a project (res://) model that Godot has imported (FBX, GLB...) as a fresh instance.
func _load_res_scene(res_path: String) -> Node3D:
	if not ResourceLoader.exists(res_path):
		return null
	var ps := load(res_path) as PackedScene
	if ps == null:
		return null
	return ps.instantiate() as Node3D


# Copies the first animation of each FBX onto the character's AnimationPlayer, re-pointed at its skeleton.
func _attach_clips(char_root: Node3D, clip_files: PackedStringArray) -> AnimationPlayer:
	var skel := _find_first_of_class(char_root, "Skeleton3D") as Skeleton3D
	if skel == null:
		push_warning("Enemy: no Skeleton3D found, animations skipped")
		return null
	var ap := _find_first_of_class(char_root, "AnimationPlayer") as AnimationPlayer
	if ap == null:
		ap = AnimationPlayer.new()
		ap.name = "AnimationPlayer"
		char_root.add_child(ap)
	var skel_rel: String = str(char_root.get_path_to(skel))

	var lib: AnimationLibrary
	if ap.has_animation_library(""):
		lib = ap.get_animation_library("")
	else:
		lib = AnimationLibrary.new()
		ap.add_animation_library("", lib)

	for fn in clip_files:
		var clip_name: String = fn.get_basename().replace(" ", "_")
		var src: Node3D = _load_res_scene("res://assets/Model1withanimations/" + fn)
		if src == null:
			continue
		var src_ap := _find_first_of_class(src, "AnimationPlayer") as AnimationPlayer
		if src_ap != null and not src_ap.get_animation_list().is_empty():
			var anim_src_name: StringName = src_ap.get_animation_list()[0]
			var anim := src_ap.get_animation(anim_src_name).duplicate() as Animation
			var kept: int = _retarget_to_skeleton(anim, skel, skel_rel)
			if kept > 0:
				if clip_name in ENEMY_LOOPING_CLIPS:
					anim.loop_mode = Animation.LOOP_LINEAR
				lib.add_animation(clip_name, anim)
			else:
				push_warning("Enemy clip '%s': no bones matched the character skeleton" % clip_name)
		src.queue_free()
	return ap


# Re-targets bone tracks to "<skeleton path>:<bone>" on the character. Returns tracks kept.
func _retarget_to_skeleton(anim: Animation, skel: Skeleton3D, skel_rel: String) -> int:
	for t in range(anim.get_track_count() - 1, -1, -1):
		var np: NodePath = anim.track_get_path(t)
		var bone: String = np.get_subname(0) if np.get_subname_count() > 0 else ""
		if bone.is_empty() or skel.find_bone(bone) < 0:
			anim.remove_track(t)
		else:
			anim.track_set_path(t, NodePath(skel_rel + ":" + bone))
	return anim.get_track_count()


func _find_first_of_class(root: Node, cls: String) -> Node:
	if root.is_class(cls):
		return root
	for ch in root.get_children():
		var found: Node = _find_first_of_class(ch, cls)
		if found != null:
			return found
	return null


# Play the next enemy clip (used by the N key for previewing animations)
func cycle_enemy_clip() -> String:
	if enemy_anim_player == null or enemy_clip_names.is_empty():
		return ""
	enemy_clip_index = (enemy_clip_index + 1) % enemy_clip_names.size()
	var clip: String = enemy_clip_names[enemy_clip_index]
	enemy_anim_player.play(clip)
	return clip


# ============================================================================
# UTILITY INFRASTRUCTURE (ELECTRIC POLES & STREETLAMPS ALONG HIGHWAY)
# ============================================================================

func _load_utility_infrastructure() -> void:
	var util_zip: String = ""
	for cand in [
		_project_dir.path_join("assets/Utility Infrastructure.zip"),
		_repo_root.path_join("Utility Infrastructure.zip")
	]:
		if FileAccess.file_exists(cand) and _get_file_size(cand) > 10000:
			util_zip = cand
			break

	var util_dir: String = _find_existing_dir([
		_repo_root.path_join("Utility Infrastructure"),
		_project_dir.path_join("assets/Utility Infrastructure")
	])
	if util_dir.is_empty() and not util_zip.is_empty():
		util_dir = _extract_zip_cached(util_zip, "Utility_Infrastructure")

	if util_dir.is_empty():
		return

	var poles_base: String = util_dir.path_join("Utility Infrastructure/Electric Utilities/Poles")
	if not DirAccess.dir_exists_absolute(poles_base):
		poles_base = util_dir

	var wood_pole: String = poles_base.path_join("pole_wood_b_lod_0.glb")
	var conc_pole: String = poles_base.path_join("pole_concrete_c_lod_0.glb")
	var lamp_glb: String = poles_base.path_join("prop_lamp.glb")
	var trans_glb: String = poles_base.path_join("prop_transformer.glb")

	# Place 7 Highway Utility Poles along Z = +6.4 (X = -72 to +72, every 24m)
	var pole_index: int = 0
	for x_pos in [-72.0, -48.0, -24.0, 0.0, 24.0, 48.0, 72.0]:
		pole_index += 1
		var p_file: String = conc_pole if (pole_index == 5 and FileAccess.file_exists(conc_pole)) else wood_pole
		if not FileAccess.file_exists(p_file):
			continue
		var pole_node: Node3D = _instantiate_gltf_or_fbx(p_file)
		if pole_node == null:
			continue
		pole_node.position = Vector3(x_pos, 0.0, 6.5)
		pole_node.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		var label_tag: String = "Utility Pole #%d (%s)" % [pole_index, p_file.get_file()]
		_add_trimesh_collisions_recursive(pole_node, label_tag)
		_world_root.add_child(pole_node)

		# Attach Streetlamp + Warm Sodium-Vapor SpotLight3D on key poles
		if FileAccess.file_exists(lamp_glb) and (pole_index % 2 == 0 or pole_index == 5):
			var lamp_node: Node3D = _instantiate_gltf_or_fbx(lamp_glb)
			if lamp_node != null:
				lamp_node.position = Vector3(0.0, 7.6, 0.65)
				pole_node.add_child(lamp_node)

			var street_spot := SpotLight3D.new()
			street_spot.position = Vector3(x_pos, 7.3, 4.8)
			street_spot.rotation_degrees = Vector3(-78.0, 0.0, 0.0)
			street_spot.light_color = Color(1.0, 0.74, 0.42)
			street_spot.light_energy = 5.2
			street_spot.spot_range = 22.0
			street_spot.spot_angle = 58.0
			street_spot.spot_angle_attenuation = 0.85
			street_spot.shadow_enabled = (pole_index == 4)
			_world_root.add_child(street_spot)

		# Pole #5 (X = +24m, near Campsite trail) = Story Transformer / Breaker Pole!
		if pole_index == 5 and FileAccess.file_exists(trans_glb):
			var tr_node: Node3D = _instantiate_gltf_or_fbx(trans_glb)
			if tr_node != null:
				tr_node.position = Vector3(0.0, 5.4, 0.35)
				_add_trimesh_collisions_recursive(tr_node, "Utility Transformer (prop_transformer.glb)")
				pole_node.add_child(tr_node)
			_spawn_floating_label(Vector3(x_pos, 3.2, 6.0), "STORY POLE: Transformer & Breaker Box Site", Color(1.0, 0.78, 0.35))

	# Overhead power wire spans between poles
	var wire_mat := StandardMaterial3D.new()
	wire_mat.albedo_color = Color(0.05, 0.05, 0.06)
	for x_start in [-72.0, -48.0, -24.0, 0.0, 24.0, 48.0]:
		for z_off in [6.15, 6.85]:
			var wire := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(24.0, 0.03, 0.03)
			wire.mesh = box
			wire.position = Vector3(x_start + 12.0, 9.15, z_off)
			wire.material_override = wire_mat
			_world_root.add_child(wire)

	asset_manifest.append({
		"category": "Utility Infrastructure",
		"name": "Highway Electric Poles + Streetlamps + Transformer (lod_0)",
		"size_text": "10.2m Tall",
		"meshes": 18,
		"pos": Vector3(24.0, 0.2, 11.5)
	})


# ============================================================================
# MUTUM STUDIOS 3D_RETRO_WORLD AUTO-DISCOVERY, EXTRACTION & MAP PLACEMENT
# ============================================================================

func _discover_and_load_retroworld() -> void:
	var models: Array[Dictionary] = []

	# A. Check unzipped folders in repo root or godot_game/
	var dir_candidates: Array[String] = [
		_project_dir.path_join("assets/map"),
		_repo_root.path_join("map"),
		_repo_root.path_join("3D_Retro_World 0.01"),
		_repo_root.path_join("3D_Retro_World"),
		_repo_root.path_join("retroworld"),
		_repo_root.path_join("Base Pack"),
		_repo_root.path_join("3D Assets"),
		_project_dir.path_join("assets/retroworld"),
		_project_dir.path_join("assets/3D_Retro_World")
	]
	for dc in dir_candidates:
		if DirAccess.dir_exists_absolute(dc):
			_scan_model_files_recursive(dc, "3D_Retro_World", models)

	# B. Check ZIP files in repo_root, project_dir, AND OS Downloads folder!
	if models.is_empty():
		var downloads_dir: String = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS).replace("\\", "/").trim_suffix("/")
		var zip_candidates: Array[String] = [
			_project_dir.path_join("assets/3D_Retro_World 0.01.zip"),
			_repo_root.path_join("3D_Retro_World 0.01.zip"),
			_repo_root.path_join("Base Pack.zip"),
			_repo_root.path_join("3D Assets.zip"),
			_project_dir.path_join("3D_Retro_World 0.01.zip")
		]
		if not downloads_dir.is_empty() and DirAccess.dir_exists_absolute(downloads_dir):
			zip_candidates.append(downloads_dir.path_join("3D_Retro_World 0.01.zip"))
			zip_candidates.append(downloads_dir.path_join("Base Pack.zip"))
			zip_candidates.append(downloads_dir.path_join("3D Assets.zip"))
			var dl := DirAccess.open(downloads_dir)
			if dl != null:
				dl.list_dir_begin()
				var fn: String = dl.get_next()
				while not fn.is_empty():
					var low: String = fn.to_lower()
					if low.ends_with(".zip") and ("retro" in low and "world" in low):
						zip_candidates.append(downloads_dir.path_join(fn))
					elif dl.current_is_dir() and ("retro" in low and "world" in low):
						_scan_model_files_recursive(downloads_dir.path_join(fn), "3D_Retro_World", models)
					fn = dl.get_next()
				dl.list_dir_end()

		for zc in zip_candidates:
			if not models.is_empty():
				break
			if FileAccess.file_exists(zc):
				var sz: int = _get_file_size(zc)
				if sz <= 1024:
					retroworld_lfs_pointer_detected = true
				else:
					var out_dir: String = _extract_zip_cached(zc, "3D_Retro_World_Base")
					if not out_dir.is_empty():
						_scan_model_files_recursive(out_dir, "3D_Retro_World", models)

	if models.is_empty():
		retroworld_loaded = false
		_spawn_lfs_placeholder_station()
	else:
		retroworld_loaded = true
		retroworld_lfs_pointer_detected = false
		_populate_retroworld_models(models)


func _populate_retroworld_models(raw_models: Array[Dictionary]) -> void:
	# Rebuild cleanly so dropping the pack twice never duplicates the map
	_clear_node_children(_dynamic_pack_root)
	_clear_node_children(_gallery_root)

	# Filter out lower LODs (_lod_1, _lod_2, billboard) so map & gallery show crisp LOD0 models
	var primary_models: Array[Dictionary] = []
	for item in raw_models:
		var low_rel: String = str(item["rel_path"]).to_lower()
		if "_lod_1" in low_rel or "_lod_2" in low_rel or "_lod1" in low_rel or "_lod2" in low_rel or "billboard" in low_rel:
			continue
		primary_models.append(item)
	if primary_models.is_empty():
		primary_models = raw_models

	var station_entries: Array[Dictionary] = []
	var camp_entries: Array[Dictionary] = []
	var road_entries: Array[Dictionary] = []
	var nature_entries: Array[Dictionary] = []
	var other_entries: Array[Dictionary] = []

	for m in primary_models:
		var proto: Node3D = _instantiate_gltf_or_fbx(str(m["abs_path"]))
		if proto == null:
			continue
		var aabb: AABB = compute_node_aabb(proto)
		var mesh_names: PackedStringArray = _collect_mesh_names(proto)
		var cat: String = _classify_retroworld_path(str(m["rel_path"]), aabb)

		var rec: Dictionary = {
			"abs_path": str(m["abs_path"]),
			"rel_path": str(m["rel_path"]),
			"proto": proto,
			"aabb": aabb,
			"mesh_names": mesh_names,
			"category": cat
		}
		match cat:
			"Gas Station":
				station_entries.append(rec)
			"Camping":
				camp_entries.append(rec)
			"Roads":
				road_entries.append(rec)
			"Nature (Trees & Rocks)":
				nature_entries.append(rec)
			_:
				other_entries.append(rec)

	# 1. Pieces that get ASSEMBLED by hand-measured layout (store shell, canopy, pumps, campsite)
	var named: Dictionary = {}
	for rec in station_entries:
		named[str(rec["rel_path"]).get_file().get_basename()] = rec
	for rec in camp_entries:
		named[str(rec["rel_path"]).get_file().get_basename()] = rec

	var used: Dictionary = {}
	_assemble_mile47_station(named, used)
	_assemble_campsite(named, used)

	# 2. Anything from the station/camp folders NOT in the layout goes to a labelled side row (north of the map)
	var leftover_x: float = -60.0
	for rec in station_entries + camp_entries:
		var key: String = str(rec["rel_path"]).get_file().get_basename()
		if used.has(key):
			continue
		var inst: Node3D = (rec["proto"] as Node3D).duplicate() as Node3D
		var aabb: AABB = rec["aabb"]
		var span: float = maxf(aabb.size.x, 2.5) + 3.0
		var pos := Vector3(leftover_x + span * 0.5, 0.03, -62.0)
		leftover_x += span
		_ground_and_add_node(inst, _dynamic_pack_root, pos, aabb, str(rec["rel_path"]), rec["mesh_names"])
		_spawn_floating_label(
			pos + Vector3(0.0, maxf(aabb.size.y, 1.0) + 0.6, 0.0),
			"%s\n[unassembled | %.1fm x %.1fm x %.1fm]" % [key, aabb.size.x, aabb.size.y, aabb.size.z],
			Color(1.0, 0.9, 0.55)
		)

	# 3. Road modules on a test strip south of the highway
	var road_cursor_x: float = -65.0
	for rec in road_entries:
		var inst: Node3D = (rec["proto"] as Node3D).duplicate() as Node3D
		var aabb: AABB = rec["aabb"]
		var w: float = clampf(aabb.size.x, 3.0, 28.0)
		var pos := Vector3(road_cursor_x + w * 0.5, 0.03, 34.0)
		road_cursor_x += w + 3.5
		_ground_and_add_node(inst, _dynamic_pack_root, pos, aabb, str(rec["rel_path"]), rec["mesh_names"])

	# 4. Trees & rocks around the woods (keeping station, highway & campsite clear)
	if not nature_entries.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 4709
		var total_scatter: int = 56
		for i in range(total_scatter):
			var rec: Dictionary = nature_entries[i % nature_entries.size()]
			var inst: Node3D = (rec["proto"] as Node3D).duplicate() as Node3D
			var aabb: AABB = rec["aabb"]
			var angle: float = rng.randf_range(-PI * 1.02, 0.12)
			var dist: float = rng.randf_range(44.0, 96.0)
			var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist - 14.0)
			if pos.z > -9.5 and pos.z < 11.5:
				pos.z = -14.0 - rng.randf_range(4.0, 22.0)
			if pos.distance_to(CAMP_CENTER) < 11.0:
				pos.x += 14.0
			var sc: float = rng.randf_range(0.88, 1.16)
			inst.scale = Vector3.ONE * sc
			inst.rotation.y = rng.randf_range(0.0, TAU)
			var scaled_aabb := AABB(aabb.position * sc, aabb.size * sc)
			_ground_and_add_node(inst, _dynamic_pack_root, pos, scaled_aabb, str(rec["rel_path"]), rec["mesh_names"])

	# 5. Zone 3 gallery: one labelled copy of EVERY unique asset
	var all_unique: Array[Dictionary] = []
	all_unique.append_array(station_entries)
	all_unique.append_array(camp_entries)
	all_unique.append_array(road_entries)
	all_unique.append_array(nature_entries)
	all_unique.append_array(other_entries)
	_build_gallery_grid(all_unique)

	asset_manifest.append({
		"category": "Mile 47 Station (assembled)",
		"name": "Gas & Mart shell, canopy, 4 pumps, lamps, sign, bins, pavement + Campsite (%d pieces placed)" % used.size(),
		"size_text": "Store 12m x 8m, canopy 6m x 6m, 3m walls",
		"meshes": used.size(),
		"pos": STORE_ORIGIN
	})


func _clear_node_children(n: Node) -> void:
	if n == null:
		return
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


# ============================================================================
# MILE 47 GAS & MART — hand assembled from the uploaded modular pack
# Every position below uses the measured pivots of the .glb pieces:
#   Wall_4x3_A/B, Window_4x3_B, Door_A/B, Wall_Pillar  -> pivot at centre-bottom (x/z centred)
#   Door_A -> origin = left edge (spans x 0..1), Door_B -> origin = right edge (spans x -1..0)
#   Roof_Top / Roof_Floor / GasRoof_x -> 2 m grid, centred
#   Gas_Pilar 6 m tall, Gas_Pump 2.5 m tall, Lamp_01 0.25 m tall
# Store footprint: x 6..18.0, z -25..-17 (front facade at z=-17 faces the highway)
# Canopy centre: (0, -21), 3x3 GasRoof tiles, top at 6.0 m
# ============================================================================

const STORE_ORIGIN := Vector3(6.0, 0.0, -25.0)
const STORE_W: float = 12.0
const STORE_D: float = 8.0
const STORE_WALL_COL := Color(0.60, 0.58, 0.53)
const CANOPY_CENTER := Vector3(0.0, 0.0, -21.0)
const CANOPY_Y: float = 5.0
const CAMP_CENTER := Vector3(44.0, 0.0, -36.0)


func _assemble_mile47_station(named: Dictionary, used: Dictionary) -> void:
	var o: Vector3 = STORE_ORIGIN
	var w: float = STORE_W
	var d: float = STORE_D

	# --- Store shell ----------------------------------------------------------
	# Back wall (z = 0): solid panels at x 0..4, 4..8; Door_B (backroom door) at x 9..10; filler 8..9 & 10..12
	_place(named, used, "Wall_4x3_A", o + Vector3(2.0, 0.0, 0.0), 0.0, true)
	_place(named, used, "Wall_4x3_A", o + Vector3(6.0, 0.0, 0.0), 0.0, true)
	_place(named, used, "Door_B", o + Vector3(10.0, 0.0, 0.0), 0.0, true)
	_box(Vector3(1.0, 0.9, 0.3), o + Vector3(9.5, 2.55, 0.0), STORE_WALL_COL, true)  # lintel over back door
	_box(Vector3(1.0, 3.0, 0.3), o + Vector3(8.5, 1.5, 0.0), STORE_WALL_COL, true)
	_box(Vector3(2.0, 3.0, 0.3), o + Vector3(11.0, 1.5, 0.0), STORE_WALL_COL, true)

	# Side walls (x = 0 and x = W), yaw 90 so each 4 m panel runs along Z
	for z in [2.0, 6.0]:
		_place(named, used, "Wall_4x3_A", o + Vector3(0.0, 0.0, z), 90.0, true)
		_place(named, used, "Wall_4x3_B", o + Vector3(w, 0.0, z), 90.0, true)

	# Front facade (z = D, faces the highway): solid 0..4 | front door 4..5 | window 5..8.8 | solid 8.8..12
	_place(named, used, "Wall_4x3_A", o + Vector3(2.0, 0.0, d), 0.0, true)
	_place(named, used, "Door_A", o + Vector3(4.0, 0.0, d), 0.0, true)
	_box(Vector3(1.0, 0.9, 0.3), o + Vector3(4.5, 2.55, d), STORE_WALL_COL, true)  # lintel over front door
	_place(named, used, "Window_4x3_B", o + Vector3(6.9, 0.0, d), 0.0, false)
	_box(Vector3(3.8, 1.0, 0.3), o + Vector3(6.9, 0.5, d), STORE_WALL_COL, true)     # sill under window
	_box(Vector3(3.8, 0.2, 0.3), o + Vector3(6.9, 2.9, d), STORE_WALL_COL, true)     # header above window
	_box(Vector3(3.2, 3.0, 0.3), o + Vector3(10.4, 1.5, d), STORE_WALL_COL, true)    # solid filler 8.8..12

	# Corner pillars
	for corner in [Vector3(0.0, 0.0, 0.0), Vector3(w, 0.0, 0.0), Vector3(0.0, 0.0, d), Vector3(w, 0.0, d)]:
		_place(named, used, "Wall_Pillar", o + corner, 0.0, true)

	# Floor (Roof_Floor 2 m tiles) and roof (Roof_Top 2 m tiles) + dark ceiling so you never see sky from inside
	for i in range(int(w / 2.0)):
		for j in range(int(d / 2.0)):
			var tile: Vector3 = o + Vector3(1.0 + 2.0 * float(i), 0.0, 1.0 + 2.0 * float(j))
			_place(named, used, "Roof_Floor", tile + Vector3(0.0, 0.06, 0.0), 0.0, true)
			_place(named, used, "Roof_Top", tile + Vector3(0.0, 3.0, 0.0), 0.0, false)
	_box(Vector3(w, 0.06, d), o + Vector3(w * 0.5, 2.96, d * 0.5), Color(0.14, 0.13, 0.12), true)

	# Store signage: Light_Sign on the roofline + readable Label3D
	_place(named, used, "Light_Sign", o + Vector3(w * 0.5, 3.8, d + 0.05), 0.0, false)
	_spawn_plain_label(o + Vector3(w * 0.5, 3.8, d + 0.45), "MILE 47 GAS & MART", Color(1.0, 0.85, 0.45), 150, 0.011)

	# Store interior: a dim, flickering-ready ceiling light (inside is still empty, stock comes later)
	var store_light := OmniLight3D.new()
	store_light.position = o + Vector3(w * 0.5, 2.5, d * 0.5)
	store_light.light_color = Color(0.95, 0.9, 0.78)
	store_light.light_energy = 1.1
	store_light.omni_range = 12.0
	_dynamic_pack_root.add_child(store_light)
	_place(named, used, "FireExtinguisher", o + Vector3(1.0, 0.0, 1.2), 0.0, false)

	# Outside the store: bins on the east side, pavement strip along the front
	_place(named, used, "Trash_Can", o + Vector3(w + 1.5, 0.0, 3.0), 0.0, true)
	_place(named, used, "Trash_Box", o + Vector3(w + 1.5, 0.0, 5.0), 0.0, true)
	_place(named, used, "Trash_Bag", o + Vector3(w + 1.4, 0.0, 1.5), 0.0, false)
	for i in range(13):
		_place(named, used, "Pavement_0", Vector3(6.5 + float(i), 0.05, -16.5), 0.0, false)

	# --- Canopy (3x3 GasRoof tiles, 2 m each, top at 6 m) -------------------
	var c: Vector3 = CANOPY_CENTER
	var k: int = 1
	for i in range(3):
		for j in range(3):
			var key: String = "GasRoof_0"
			if not (i == 1 and j == 1):
				key = "GasRoof_%d" % k
				k += 1
			_place(named, used, key, c + Vector3((float(i) - 1.0) * 2.0, CANOPY_Y, (float(j) - 1.0) * 2.0), 0.0, true)

	# Canopy pillars (6 m, inset from the canopy edge)
	for sx in [-2.2, 2.2]:
		for sz in [-2.2, 2.2]:
			_place(named, used, "Gas_Pilar", c + Vector3(sx, 0.0, sz), 0.0, true)

	# Two islands of two pumps: z = -19.8 (Gas_Pump) and z = -22.2 (Gas_Pump_Base), x = +-1.5
	_place(named, used, "Gas_Pump", c + Vector3(-1.5, 0.0, 1.2), 0.0, true)
	_place(named, used, "Gas_Pump", c + Vector3(1.5, 0.0, 1.2), 0.0, true)
	_place(named, used, "Gas_Pump_Base", c + Vector3(-1.5, 0.0, -1.2), 0.0, true)
	_place(named, used, "Gas_Pump_Base", c + Vector3(1.5, 0.0, -1.2), 0.0, true)

	# Canopy lamps (0.25 m tall, hung just under the roof at y 4.75) + warm lights
	for lz in [1.2, -1.2]:
		_place(named, used, "Lamp_01", c + Vector3(0.0, CANOPY_Y - 0.25, lz), 0.0, false)
		var lamp := OmniLight3D.new()
		lamp.position = c + Vector3(0.0, CANOPY_Y - 0.5, lz)
		lamp.light_color = Color(1.0, 0.86, 0.62)
		lamp.light_energy = 2.2
		lamp.omni_range = 10.0
		_dynamic_pack_root.add_child(lamp)

	# Price board + Number sign at the forecourt edge
	_place(named, used, "Sign_04", c + Vector3(-5.5, 0.0, 1.5), 0.0, false)
	_place(named, used, "Number_Sign", c + Vector3(-5.5, 1.6, -2.0), 0.0, false)

	# Forecourt Zone label
	_spawn_plain_label(c + Vector3(0.0, 6.6, 0.0), "MILE 47 GAS & MART — FORECOURT", Color(1.0, 0.9, 0.6), 110, 0.012)

	asset_manifest.append({
		"category": "Mile 47 Station (assembled)",
		"name": "Store shell (12m x 8m, 3m walls, 2 doors, window), canopy 6m x 6m, 4 pumps, 2 lamps",
		"size_text": "Store 12m x 8m | Canopy top 6.0m",
		"meshes": used.size(),
		"pos": o + Vector3(w * 0.5, 0.2, d * 0.5)
	})


func _assemble_campsite(named: Dictionary, used: Dictionary) -> void:
	var c: Vector3 = CAMP_CENTER

	# Tent (2.16 m square) with sleeping bag beside it (yaw 90 -> long side along Z)
	_place(named, used, "Tent", c, 0.0, true)
	_place(named, used, "SleepingBag", c + Vector3(-2.6, 0.0, 0.0), 90.0, false)
	_place(named, used, "Lantern", c + Vector3(-2.6, 0.0, -1.8), 0.0, false)
	_place(named, used, "Bag", c + Vector3(3.2, 0.0, -2.0), 0.0, false)
	_place(named, used, "ThermalBottle", c + Vector3(3.6, 0.0, -1.6), 0.0, false)

	# Fire pit 4.5 m south of the tent with cooker and pans
	_place(named, used, "Bonfire", c + Vector3(0.0, 0.0, 4.5), 0.0, false)
	_place(named, used, "Cooker", c + Vector3(-2.0, 0.0, 3.0), 0.0, false)
	_place(named, used, "Pan_A", c + Vector3(-2.0, 0.28, 3.0), 0.0, false)
	_place(named, used, "Pan_B", c + Vector3(-1.2, 0.0, 2.2), 0.0, false)

	# Ice box with its cover on top
	_place(named, used, "IceBox", c + Vector3(4.5, 0.0, 1.5), 0.0, true)
	_place(named, used, "IceBox_Cover", c + Vector3(4.5, 0.0, 1.5), 0.0, false)

	var fire_light := OmniLight3D.new()
	fire_light.position = c + Vector3(0.0, 1.1, 4.5)
	fire_light.light_color = Color(1.0, 0.54, 0.18)
	fire_light.light_energy = 3.4
	fire_light.omni_range = 16.0
	fire_light.shadow_enabled = true
	_dynamic_pack_root.add_child(fire_light)

	asset_manifest.append({
		"category": "Campsite (assembled)",
		"name": "Tent, bonfire, cooker+pans, sleeping bag, ice box + cover, lantern, bag, bottle",
		"size_text": "Tent 2.16m square",
		"meshes": used.size(),
		"pos": c
	})


# Place a named piece at an explicit pivot (no AABB centring), so modular pieces snap exactly.
func _place(named: Dictionary, used: Dictionary, key: String, pos: Vector3, yaw_deg: float, collide: bool) -> void:
	if not named.has(key):
		push_warning("Mile 47 layout: missing piece '%s'" % key)
		return
	var rec: Dictionary = named[key]
	var inst: Node3D = (rec["proto"] as Node3D).duplicate() as Node3D
	inst.position = pos
	inst.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	if collide:
		_add_trimesh_collisions_recursive(inst, "%s  [Mile 47 layout]" % key)
	_dynamic_pack_root.add_child(inst)
	used[key] = true


# Procedural panel for the gaps between modular pieces (same wall colour as the kit)
func _box(size: Vector3, pos: Vector3, col: Color, collide: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.95
	mi.material_override = mat
	_dynamic_pack_root.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		mi.add_child(sb)


func _spawn_plain_label(pos: Vector3, txt: String, col: Color, font: int, px: float) -> void:
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.position = pos
	lbl.font_size = font
	lbl.pixel_size = px
	lbl.modulate = col
	lbl.outline_size = 10
	_dynamic_pack_root.add_child(lbl)


func _build_gallery_grid(entries: Array[Dictionary]) -> void:
	var cursor_x: float = -56.0
	var cursor_z: float = 40.0
	var row_max_depth: float = 6.0

	for rec in entries:
		var proto: Node3D = rec["proto"]
		var aabb: AABB = rec["aabb"]
		var meshes: PackedStringArray = rec["mesh_names"]
		var rel_p: String = str(rec["rel_path"])
		var cat: String = str(rec["category"])

		var footprint_w: float = clampf(aabb.size.x, 2.5, 32.0)
		var footprint_d: float = clampf(aabb.size.z, 2.5, 32.0)

		if cursor_x + footprint_w > 58.0:
			cursor_x = -56.0
			cursor_z += row_max_depth + 7.5
			row_max_depth = 6.0

		var pad_center := Vector3(cursor_x + footprint_w * 0.5, 0.02, cursor_z + footprint_d * 0.5)
		row_max_depth = maxf(row_max_depth, footprint_d)
		cursor_x += footprint_w + 4.5

		# Pedestal pad
		var pad := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(footprint_w + 1.2, 0.05, footprint_d + 1.2)
		pad.mesh = pm
		pad.position = pad_center
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.18, 0.20, 0.24)
		pad.material_override = pmat
		_gallery_root.add_child(pad)

		_ground_and_add_node(proto, _gallery_root, pad_center + Vector3(0.0, 0.03, 0.0), aabb, rel_p, meshes)

		var preview_parts: String = ", ".join(meshes.slice(0, mini(meshes.size(), 4)))
		if meshes.size() > 4:
			preview_parts += " ..."

		_spawn_floating_label(
			pad_center + Vector3(0.0, clampf(aabb.size.y, 1.2, 12.0) + 0.85, 0.0),
			"[%s] %s\n%.2fm x %.2fm x %.2fm  |  %d mesh(es)\nParts: %s" % [
				cat, rel_p, aabb.size.x, aabb.size.y, aabb.size.z, meshes.size(), preview_parts
			],
			Color(0.72, 0.94, 1.0)
		)

		asset_manifest.append({
			"category": cat,
			"name": rel_p,
			"size_text": "%.1fm x %.1fm x %.1fm" % [aabb.size.x, aabb.size.y, aabb.size.z],
			"meshes": meshes.size(),
			"pos": pad_center + Vector3(0.0, 0.25, footprint_d * 0.5 + 3.6)
		})


func _spawn_station_inspection_lights(station_pos: Vector3, aabb: AABB) -> void:
	# Soft warm canopy/interior lights inside the Gas Station footprint so player can see if interior exists
	for z_off in [-3.0, 0.0, 3.0]:
		var l := OmniLight3D.new()
		l.position = station_pos + Vector3(0.0, clampf(aabb.size.y * 0.62, 2.2, 3.8), z_off)
		l.light_color = Color(0.95, 0.98, 1.0)
		l.light_energy = 1.85
		l.omni_range = 16.0
		_dynamic_pack_root.add_child(l)
		_station_interior_lights.append(l)


# ============================================================================
# HELPERS: ZIP EXTRACTION, GLTF/FBX LOADING, AABB & COLLISIONS
# ============================================================================

func _place_known_prop(abs_path: String, cat: String, display_label: String, world_pos: Vector3, yaw_deg: float, uniform_scale: float, add_to_manifest: bool) -> void:
	var node: Node3D = _instantiate_gltf_or_fbx(abs_path)
	if node == null:
		return
	var raw_aabb: AABB = compute_node_aabb(node)
	node.scale = Vector3.ONE * uniform_scale
	node.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	var scaled_aabb := AABB(raw_aabb.position * uniform_scale, raw_aabb.size * uniform_scale)
	var center_xz := Vector3(
		scaled_aabb.position.x + scaled_aabb.size.x * 0.5,
		scaled_aabb.position.y,
		scaled_aabb.position.z + scaled_aabb.size.z * 0.5
	).rotated(Vector3.UP, deg_to_rad(yaw_deg))
	node.position = world_pos - center_xz

	var meshes: PackedStringArray = _collect_mesh_names(node)
	_add_trimesh_collisions_recursive(node, "%s  [%.2fm x %.2fm x %.2fm | %d meshes]" % [
		display_label, scaled_aabb.size.x, scaled_aabb.size.y, scaled_aabb.size.z, meshes.size()
	])
	_world_root.add_child(node)

	_spawn_floating_label(
		world_pos + Vector3(0.0, clampf(scaled_aabb.size.y, 0.5, 5.0) + 0.55, 0.0),
		"%s\n[%.2fm x %.2fm x %.2fm]" % [display_label, scaled_aabb.size.x, scaled_aabb.size.y, scaled_aabb.size.z],
		Color(0.82, 1.0, 0.72)
	)

	if add_to_manifest:
		asset_manifest.append({
			"category": cat,
			"name": display_label,
			"size_text": "%.2fm x %.2fm x %.2fm" % [scaled_aabb.size.x, scaled_aabb.size.y, scaled_aabb.size.z],
			"meshes": meshes.size(),
			"pos": world_pos + Vector3(0.0, 0.25, maxf(scaled_aabb.size.z, 2.0) * 0.5 + 3.2)
		})


func _ground_and_add_node(node: Node3D, parent: Node3D, target_ground_pos: Vector3, aabb: AABB, rel_name: String, meshes: PackedStringArray) -> void:
	var offset := Vector3(
		aabb.position.x + aabb.size.x * 0.5,
		aabb.position.y,
		aabb.position.z + aabb.size.z * 0.5
	).rotated(Vector3.UP, node.rotation.y)
	node.position = target_ground_pos - offset
	# Trees, bushes and grass stay walk-through (a box around a whole tree would block the player)
	if not rel_name.to_lower().contains("vegetation"):
		_add_trimesh_collisions_recursive(node, "%s  [%.2fm x %.2fm x %.2fm | %d meshes]" % [
			rel_name, aabb.size.x, aabb.size.y, aabb.size.z, meshes.size()
		])
	parent.add_child(node)


func _instantiate_gltf_or_fbx(abs_path: String) -> Node3D:
	var lower: String = abs_path.to_lower()
	if lower.ends_with(".glb") or lower.ends_with(".gltf"):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err: Error = doc.append_from_file(abs_path, state)
		if err == OK:
			var generated: Node = doc.generate_scene(state)
			if generated is Node3D:
				return generated as Node3D
	elif lower.ends_with(".fbx") and ClassDB.class_exists("FBXDocument"):
		var fbx_doc: Object = ClassDB.instantiate("FBXDocument")
		var fbx_state: Object = ClassDB.instantiate("FBXState")
		if fbx_doc != null and fbx_state != null:
			var err_v: Variant = fbx_doc.call("append_from_file", abs_path, fbx_state)
			if int(err_v) == OK:
				var gen: Variant = fbx_doc.call("generate_scene", fbx_state)
				if gen is Node3D:
					return gen as Node3D
	return null


func _extract_zip_cached(zip_abs_path: String, folder_slug: String) -> String:
	var dest_dir: String = _extract_cache_root.path_join(folder_slug)
	var marker_file: String = dest_dir.path_join(".extracted_v1_ok")
	var expected_stamp: String = "%s|%d" % [zip_abs_path.get_file(), _get_file_size(zip_abs_path)]

	if FileAccess.file_exists(marker_file):
		var existing: String = FileAccess.get_file_as_string(marker_file).strip_edges()
		if existing == expected_stamp:
			return dest_dir

	var reader := ZIPReader.new()
	if reader.open(zip_abs_path) != OK:
		return ""

	DirAccess.make_dir_recursive_absolute(dest_dir)
	var files: PackedStringArray = reader.get_files()
	for rel in files:
		if rel.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(dest_dir.path_join(rel))
			continue
		var out_path: String = dest_dir.path_join(rel)
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var data: PackedByteArray = reader.read_file(rel)
		var fa := FileAccess.open(out_path, FileAccess.WRITE)
		if fa != null:
			fa.store_buffer(data)
			fa.close()
	reader.close()

	var mf := FileAccess.open(marker_file, FileAccess.WRITE)
	if mf != null:
		mf.store_string(expected_stamp)
		mf.close()
	return dest_dir


func _scan_model_files_recursive(base_dir: String, pack_name: String, out_list: Array[Dictionary], prefix: String = "") -> void:
	var d := DirAccess.open(base_dir)
	if d == null:
		return
	d.list_dir_begin()
	var entry: String = d.get_next()
	while not entry.is_empty():
		if entry != "." and entry != ".." and not entry.begins_with("."):
			var full: String = base_dir.path_join(entry)
			var rel: String = entry if prefix.is_empty() else prefix.path_join(entry)
			if d.current_is_dir():
				_scan_model_files_recursive(full, pack_name, out_list, rel)
			else:
				var low: String = entry.to_lower()
				if low.ends_with(".glb") or low.ends_with(".gltf"):
					out_list.append({
						"abs_path": full,
						"rel_path": rel,
						"pack": pack_name
					})
		entry = d.get_next()
	d.list_dir_end()


func _classify_retroworld_path(rel_path: String, aabb: AABB) -> String:
	var s: String = rel_path.to_lower()
	if _contains_any(s, ["gas", "station", "posto", "store", "shop", "convenience", "loja", "pump", "bomba", "fuel", "canopy", "totem"]):
		return "Gas Station"
	if _contains_any(s, ["camp", "tent", "barraca", "fire", "bonfire", "fogueira", "sleeping", "cooler", "lantern"]):
		return "Camping"
	if _contains_any(s, ["road", "street", "highway", "asphalt", "estrada", "rua", "pista", "curb", "sign"]):
		return "Roads"
	if _contains_any(s, ["tree", "pine", "oak", "birch", "spruce", "fir", "cedar", "bush", "shrub", "grass", "fern", "plant", "rock", "stone", "boulder", "cliff", "pedra", "arv"]):
		return "Nature (Trees & Rocks)"
	if maxf(aabb.size.x, aabb.size.z) >= 8.0 and aabb.size.y >= 2.8:
		return "Gas Station"
	return "Other RetroWorld Props"


func _contains_any(haystack: String, needles: Array[String]) -> bool:
	for k in needles:
		if k in haystack:
			return true
	return false


static func compute_node_aabb(root: Node3D) -> AABB:
	var found: bool = false
	var merged := AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.0, 1.0))
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null and mi.mesh.get_surface_count() > 0:
				var local_box: AABB = mi.mesh.get_aabb()
				var rel_xf := Transform3D.IDENTITY
				var w: Node = mi
				while w != null and w != root:
					if w is Node3D:
						rel_xf = (w as Node3D).transform * rel_xf
					w = w.get_parent()
				var transformed_box: AABB = rel_xf * local_box
				if not found:
					merged = transformed_box
					found = true
				else:
					merged = merged.merge(transformed_box)
		for ch in cur.get_children():
			stack.push_back(ch)
	return merged


func _collect_mesh_names(root: Node) -> PackedStringArray:
	var out: PackedStringArray = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null:
			out.append(cur.name)
		for ch in cur.get_children():
			stack.push_back(ch)
	return out


# Collision = one BoxShape3D per mesh part (its local AABB).
# ConcavePolygonShape3D (trimesh) is avoided on purpose: it crashed the physics engine
# (Illegal Instruction) when the inspector raycast hit the Gas_Pilar pieces.
func _add_trimesh_collisions_recursive(root: Node, label_prefix: String) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null and mi.mesh.get_surface_count() > 0:
				var box: AABB = mi.mesh.get_aabb()
				var size := Vector3(maxf(box.size.x, 0.05), maxf(box.size.y, 0.05), maxf(box.size.z, 0.05))
				var sb := StaticBody3D.new()
				sb.set_meta("asset_label", "%s  ->  part: %s" % [label_prefix, mi.name])
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = size
				cs.shape = bs
				cs.position = box.get_center()
				sb.add_child(cs)
				mi.add_child(sb)
		for ch in cur.get_children():
			stack.push_back(ch)


func _apply_psx_texture_recursive(root: Node, tex: Texture2D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.92
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			(cur as MeshInstance3D).material_override = mat
		for ch in cur.get_children():
			stack.push_back(ch)


func _spawn_zone_signpost(pos: Vector3, title: String, col: Color) -> void:
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.05
	cm.height = 2.2
	post.mesh = cm
	post.position = pos + Vector3(0.0, 1.1, 0.0)
	_world_root.add_child(post)
	_spawn_floating_label(pos + Vector3(0.0, 2.55, 0.0), title, col)


func _spawn_floating_label(pos: Vector3, txt: String, col: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.position = pos
	lbl.font_size = 28
	lbl.pixel_size = 0.0055
	lbl.modulate = col
	lbl.outline_size = 8
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_world_root.add_child(lbl)


func _find_existing_dir(candidates: Array[String]) -> String:
	for c in candidates:
		if DirAccess.dir_exists_absolute(c):
			return c
	return ""


func _get_file_size(abs_path: String) -> int:
	var fa := FileAccess.open(abs_path, FileAccess.READ)
	if fa == null:
		return 0
	var len_bytes: int = fa.get_length()
	fa.close()
	return len_bytes


func _emit_final_summary() -> void:
	var msg: String = "Loaded %d Asset Groups" % asset_manifest.size()
	if retroworld_loaded:
		msg += "  |  3D_Retro_World: LOADED"
	elif retroworld_lfs_pointer_detected:
		msg += "  |  3D_Retro_World: Drop real .zip / folder on window!"
	loading_status_updated.emit(msg, retroworld_lfs_pointer_detected and not retroworld_loaded)
