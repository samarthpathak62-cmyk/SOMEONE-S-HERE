extends Node3D
class_name RetroMapLoader

# ============================================================================
# MILE 47 MAP LOADER
# The whole map is ONE pre-assembled gas station model: assets/mile47/gas_station.glb
# The GLB has no baked animation, so every object is animated from this script:
#   door / fuse-box door        -> hinged swing              [E]
#   fridge lid / dumpster lid   -> lifts open                [E]
#   security cameras            -> idle sweep (always on)
#   ceiling lamps, neon, sign   -> flicker (always on)
#   fuel pumps, machines        -> vibrate                   [E]
#   shelves, desks, boxes       -> knock                     [E]
#   small products (food etc.)  -> pick up and put back      [E]
# The old pack (Gas_Store, Gas_Station, Camp, Roads, Rocks, Vegetation, utility poles,
# the 3D_Retro_World zip and the gallery/zones) was removed on purpose.
# ============================================================================

const STATION_RES: String = "assets/mile47/gas_station.glb"
const HANDHELD_DIR_RES: String = "assets/fewitemsandmodels"
const SFX_DOOR_RES: String = "res://assets/audio/sfx_door_creak.wav"

const DOOR_OPEN_ANGLE: float = 1.66
const LID_OPEN_ANGLE: float = -1.25

# Name keywords (lower-case match). Order in _classify() decides the winner.
const SCENERY_WORDS: Array[String] = ["tree", "bush", "background", "ground", "road", "grass"]
const DOOR_WORDS: Array[String] = ["door", "fusible_d"]
const LID_WORDS: Array[String] = ["fridge_d", "dumpster_t"]
const LIGHT_WORDS: Array[String] = ["lamp", "spotlight", "logo", "sign"]
const MACHINE_WORDS: Array[String] = ["machine", "pump", "dispenser", "fusible", "ice", "others"]
const FURNITURE_WORDS: Array[String] = ["shel", "desk", "chair", "boxs", "board", "checker", "management", "fridge", "dumpster", "table", "counter", "marble", "cabinet"]

# Teleport landmarks
var landmark_station: Vector3 = Vector3(5.0, 0.25, 3.0)   # forecourt, facing the store door
var landmark_store: Vector3 = Vector3(5.0, 0.25, -18.0)   # inside the shop

var station_root: Node3D = null

var _project_dir: String = ""
var _parts: Dictionary = {}          # MeshInstance3D instance id -> info Dictionary
var _sweepers: Array[Dictionary] = []
var _flickers: Array[Dictionary] = []
var _clock: float = 0.0


func _ready() -> void:
	_project_dir = ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")


# Called once by main_map_test.gd
func build_all_and_equip_player(player: HorrorPlayerController) -> void:
	_build_floor()
	station_root = _load_station()
	if station_root != null:
		_setup_station(station_root)
		_spawn_canopy_lights()
	_load_handhelds(player)


# Text shown for the object under the crosshair (empty if it has no interaction)
func hint_for(node: Node) -> String:
	var info: Dictionary = _info_for(node)
	return str(info.get("hint", ""))


# Runs the interaction for an object. Returns its label (empty if nothing happened).
func interact_with(node: Node) -> String:
	var info: Dictionary = _info_for(node)
	if info.is_empty():
		return ""
	match str(info.get("kind", "")):
		"door":
			_toggle_door(info)
		"lid":
			_toggle_lid(info)
		"machine":
			_machine_pulse(info)
		"furniture":
			_furniture_knock(info)
		"item":
			_lift_item(info)
	return str(info.get("label", ""))


func _process(delta: float) -> void:
	_clock += delta
	# Security cameras sweep slowly
	for s in _sweepers:
		var pv: Node3D = s["pivot"] as Node3D
		if is_instance_valid(pv):
			pv.rotation.y = float(s["base"]) + sin(_clock * 0.6 + float(s["phase"])) * 0.45
	# Lamps and neon flicker, some drop out for a moment
	for f in _flickers:
		var l: OmniLight3D = f["light"] as OmniLight3D
		if not is_instance_valid(l):
			continue
		var wobble: float = 0.92 + 0.08 * sin(_clock * 9.0 + float(f["phase"]))
		if bool(f["dropper"]):
			if float(f["timer"]) > 0.0:
				f["timer"] = float(f["timer"]) - delta
				wobble = 0.12
			elif randf() < delta * 0.35:
				f["timer"] = randf_range(0.05, 0.14)
		l.light_energy = float(f["base"]) * wobble


# ============================================================================
# FLOOR & STATION MODEL
# ============================================================================

func _build_floor() -> void:
	var sb := StaticBody3D.new()
	sb.name = "ForestFloor"
	sb.set_meta("asset_label", "Forest floor (ground collision)")
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(520.0, 1.0, 520.0)
	cs.shape = bx
	cs.position = Vector3(0.0, -0.5, 0.0)
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(520.0, 0.2, 520.0)
	mi.mesh = bm
	mi.position = Vector3(0.0, -0.1, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.095, 0.075)
	mat.roughness = 0.96
	mi.material_override = mat
	sb.add_child(mi)
	add_child(sb)


func _load_station() -> Node3D:
	var glb_path: String = _project_dir.path_join(STATION_RES)
	if not FileAccess.file_exists(glb_path):
		push_error("Mile 47 station model missing: " + glb_path)
		return null
	var root: Node3D = _instantiate_gltf_or_fbx(glb_path)
	if root == null:
		push_error("Mile 47 station model failed to load: " + glb_path)
		return null
	root.name = "Mile47FullStation"
	root.position = Vector3.ZERO
	add_child(root)
	return root


# One pass over every mesh of the station: collision, then the animation for its kind.
func _setup_station(root: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null:
			meshes.append(cur as MeshInstance3D)
		for ch in cur.get_children():
			stack.push_back(ch)

	for mi in meshes:
		var kind: String = _classify(mi)
		if kind == "scenery":
			continue
		var sz: Vector3 = mi.mesh.get_aabb().size
		var solid: bool = sz.y >= 0.3 and maxf(sz.x, sz.z) >= 0.35
		if solid or kind == "item" or kind == "machine" or kind == "furniture" or kind == "door" or kind == "lid":
			_ensure_body(mi, solid)
		match kind:
			"door":
				_setup_door(mi)
			"lid":
				_setup_lid(mi)
			"camera":
				_setup_camera(mi)
			"light":
				_setup_light(mi)
			"machine", "furniture":
				_register_nudge(mi, kind)
			"item":
				_register_item(mi)


func _classify(mi: MeshInstance3D) -> String:
	var w: Node = mi
	while w != null:
		var wl: String = str(w.name).to_lower()
		for k in SCENERY_WORDS:
			if wl.contains(k):
				return "scenery"
		w = w.get_parent()
	var low: String = str(mi.name).to_lower()
	if _has_any(low, DOOR_WORDS):
		return "door"
	if _has_any(low, LID_WORDS):
		return "lid"
	if low.begins_with("camera"):
		return "camera"
	if _has_any(low, LIGHT_WORDS):
		return "light"
	if _has_any(low, MACHINE_WORDS):
		return "machine"
	var sz: Vector3 = mi.mesh.get_aabb().size
	if maxf(sz.x, maxf(sz.y, sz.z)) < 0.6:
		return "item"
	if _has_any(low, FURNITURE_WORDS):
		return "furniture"
	return "static"


func _has_any(text: String, words: Array[String]) -> bool:
	for k in words:
		if text.contains(k):
			return true
	return false


# Box collider per mesh part. solid = blocks the player; otherwise it is only for the inspector.
func _ensure_body(mi: MeshInstance3D, solid: bool) -> void:
	for ch in mi.get_children():
		if ch is StaticBody3D:
			return
	var box: AABB = mi.mesh.get_aabb()
	var sb := StaticBody3D.new()
	if not solid:
		sb.collision_layer = 0
		sb.collision_mask = 0
	sb.set_meta("asset_label", "Mile 47 Station  ->  %s  [%.2f x %.2f x %.2f m]" % [
		str(mi.name), box.size.x, box.size.y, box.size.z])
	sb.add_to_group("inspectable")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(maxf(box.size.x, 0.05), maxf(box.size.y, 0.05), maxf(box.size.z, 0.05))
	cs.shape = bs
	cs.position = box.get_center()
	sb.add_child(cs)
	mi.add_child(sb)


func _spawn_canopy_lights() -> void:
	for p in [Vector3(5.0, 6.0, 0.0), Vector3(5.0, 6.0, 6.0)]:
		var l := OmniLight3D.new()
		l.position = p
		l.light_color = Color(0.95, 0.98, 1.0)
		l.light_energy = 1.6
		l.omni_range = 14.0
		l.shadow_enabled = false
		station_root.add_child(l)


# ============================================================================
# ANIMATION SETUP (one per kind)
# ============================================================================

# Moves the mesh under a new Node3D pivot placed at world_origin with the given basis,
# so rotating the pivot swings the mesh around that point. Keeps the world transform.
func _make_pivot(mi: MeshInstance3D, world_origin: Vector3, pivot_basis: Basis) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "Pivot_" + str(mi.name)
	station_root.add_child(pivot)
	pivot.global_transform = Transform3D(pivot_basis, world_origin)
	mi.reparent(pivot, true)
	return pivot


func _register(mi: MeshInstance3D, info: Dictionary) -> void:
	info["mi"] = mi
	_parts[mi.get_instance_id()] = info


func _setup_door(mi: MeshInstance3D) -> void:
	var aabb: AABB = mi.mesh.get_aabb()
	var long_x: bool = aabb.size.x >= aabb.size.z
	var hinge_local: Vector3 = aabb.get_center()
	if long_x:
		hinge_local.x = aabb.position.x
	else:
		hinge_local.z = aabb.position.z
	var pivot: Node3D = _make_pivot(mi, mi.global_transform * hinge_local, Basis.IDENTITY)
	_register(mi, {
		"kind": "door", "pivot": pivot, "open": false,
		"label": "Door", "hint": "[E] Open / close door",
	})


func _setup_lid(mi: MeshInstance3D) -> void:
	var aabb: AABB = mi.mesh.get_aabb()
	var long_x: bool = aabb.size.x >= aabb.size.z
	var hinge_local: Vector3 = aabb.get_center()
	if long_x:
		hinge_local.x = aabb.position.x
	else:
		hinge_local.z = aabb.position.z
	# Hinge runs across the short side of the lid
	var lid_basis: Basis = Basis(Vector3.UP, -PI * 0.5) if long_x else Basis.IDENTITY
	var pivot: Node3D = _make_pivot(mi, mi.global_transform * hinge_local, lid_basis)
	_register(mi, {
		"kind": "lid", "pivot": pivot, "base": lid_basis, "angle": 0.0, "open": false,
		"label": "Lid", "hint": "[E] Open / close lid",
	})


func _setup_camera(mi: MeshInstance3D) -> void:
	var center_world: Vector3 = mi.global_transform * mi.mesh.get_aabb().get_center()
	var pivot: Node3D = _make_pivot(mi, center_world, Basis.IDENTITY)
	_sweepers.append({"pivot": pivot, "base": 0.0, "phase": randf() * TAU})


func _setup_light(mi: MeshInstance3D) -> void:
	var pos: Vector3 = mi.global_transform * mi.mesh.get_aabb().get_center()
	var l := OmniLight3D.new()
	l.light_color = Color(0.95, 0.98, 1.0)
	l.light_energy = 1.2
	l.omni_range = 9.0
	l.shadow_enabled = false
	station_root.add_child(l)
	l.global_position = pos
	_flickers.append({
		"light": l, "base": 1.2, "phase": randf() * TAU,
		"dropper": randf() < 0.3, "timer": 0.0,
	})


func _register_nudge(mi: MeshInstance3D, kind: String) -> void:
	var is_machine: bool = kind == "machine"
	_register(mi, {
		"kind": kind,
		"base_pos": mi.position,
		"base_rot": mi.rotation,
		"label": "Machine" if is_machine else "Shop fixture",
		"hint": "[E] Use machine" if is_machine else "[E] Push / knock",
	})


func _register_item(mi: MeshInstance3D) -> void:
	_register(mi, {
		"kind": "item",
		"base_pos": mi.position,
		"base_rot": mi.rotation,
		"busy": false,
		"label": "Item: " + str(mi.name),
		"hint": "[E] Pick up / put back",
	})


# ============================================================================
# INTERACTIONS
# ============================================================================

func _info_for(node: Node) -> Dictionary:
	if node == null:
		return {}
	var mi := node.get_parent() as MeshInstance3D
	if mi == null:
		return {}
	var found: Variant = _parts.get(mi.get_instance_id(), {})
	if found is Dictionary:
		return found as Dictionary
	return {}


func _toggle_door(info: Dictionary) -> void:
	var pivot: Node3D = info["pivot"] as Node3D
	info["open"] = not bool(info["open"])
	var target: float = DOOR_OPEN_ANGLE if bool(info["open"]) else 0.0
	var tw := create_tween()
	tw.tween_property(pivot, "rotation:y", target, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_play_sfx_at(pivot.global_position, SFX_DOOR_RES)


func _toggle_lid(info: Dictionary) -> void:
	info["open"] = not bool(info["open"])
	var target: float = LID_OPEN_ANGLE if bool(info["open"]) else 0.0
	var from: float = float(info["angle"])
	info["angle"] = target
	var tw := create_tween()
	tw.tween_method(_apply_lid_angle.bind(info), from, target, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_play_sfx_at((info["pivot"] as Node3D).global_position, SFX_DOOR_RES)


func _apply_lid_angle(angle: float, info: Dictionary) -> void:
	var pivot: Node3D = info["pivot"] as Node3D
	var base: Basis = info["base"] as Basis
	pivot.transform = Transform3D(base * Basis(Vector3.RIGHT, angle), pivot.transform.origin)


func _machine_pulse(info: Dictionary) -> void:
	var mi: MeshInstance3D = info["mi"] as MeshInstance3D
	var p: Vector3 = info["base_pos"]
	var tw := create_tween()
	for i in 6:
		var off: float = 0.012 if i % 2 == 0 else -0.012
		tw.tween_property(mi, "position", p + Vector3(off, 0.0, 0.0), 0.05)
	tw.tween_property(mi, "position", p, 0.05)


func _furniture_knock(info: Dictionary) -> void:
	var mi: MeshInstance3D = info["mi"] as MeshInstance3D
	var r: Vector3 = info["base_rot"]
	var tw := create_tween()
	tw.tween_property(mi, "rotation:z", r.z + 0.04, 0.06)
	tw.tween_property(mi, "rotation:z", r.z - 0.03, 0.08)
	tw.tween_property(mi, "rotation:z", r.z, 0.12)


func _lift_item(info: Dictionary) -> void:
	if bool(info["busy"]):
		return
	info["busy"] = true
	var mi: MeshInstance3D = info["mi"] as MeshInstance3D
	var base_pos: Vector3 = info["base_pos"]
	var base_rot_y: float = (info["base_rot"] as Vector3).y
	var tw := create_tween()
	tw.tween_property(mi, "position", base_pos + Vector3(0.0, 0.12, 0.0), 0.18).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(mi, "rotation:y", base_rot_y + 0.6, 0.18)
	tw.tween_interval(0.5)
	tw.tween_property(mi, "position", base_pos, 0.3)
	tw.parallel().tween_property(mi, "rotation:y", base_rot_y, 0.3)
	tw.tween_callback(func() -> void: info["busy"] = false)


# ============================================================================
# SOUND, HANDHELDS, HELPERS
# ============================================================================

func _play_sfx_at(pos: Vector3, res_path: String) -> void:
	if res_path.is_empty() or not ResourceLoader.exists(res_path):
		return
	var stream := load(res_path) as AudioStream
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.max_distance = 25.0
	p.volume_db = -2.0
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func _load_handhelds(player: HorrorPlayerController) -> void:
	var dir_abs: String = _project_dir.path_join(HANDHELD_DIR_RES)
	var flash_hand: Node3D = _load_model_if_exists(dir_abs.path_join("flashlight.glb"))
	var phone_hand: Node3D = _load_model_if_exists(dir_abs.path_join("cell_phone.glb"))
	var broom_hand: Node3D = _load_model_if_exists(dir_abs.path_join("broom_wood_-_5mb.glb"))
	player.attach_handheld_models(flash_hand, phone_hand, broom_hand)


func _load_model_if_exists(abs_path: String) -> Node3D:
	if not FileAccess.file_exists(abs_path):
		return null
	return _instantiate_gltf_or_fbx(abs_path)


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
	return null
