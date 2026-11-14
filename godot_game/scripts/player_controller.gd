extends CharacterBody3D
class_name HorrorPlayerController

signal inspected_target_changed(description: String)
signal mode_status_changed(noclip_on: bool, flashlight_on: bool, phone_on: bool, broom_on: bool)
# E pressed while looking at an object: the map decides what happens (door, lid, item...)
signal interact_requested(target: Node)

const WALK_SPEED: float = 4.1
const SPRINT_SPEED: float = 6.9
const CROUCH_SPEED: float = 2.15
const JUMP_VELOCITY: float = 4.4
const NOCLIP_SPEED: float = 13.5
const NOCLIP_SPRINT_SPEED: float = 32.0

const STAND_HEIGHT: float = 1.75
const CROUCH_HEIGHT: float = 0.98
const STAND_EYE_Y: float = 1.60
const CROUCH_EYE_Y: float = 0.86

const BASE_FOV: float = 73.0
const SPRINT_FOV: float = 79.0
const ZOOM_FOV: float = 42.0
const MOUSE_SENSITIVITY: float = 0.0021
# Phone poses (hand-rig space): lowered in the right hand -> raised in front of the chest
const PHONE_LOW_POS := Vector3(0.20, -0.50, -0.34)
const PHONE_LOW_ROT := Vector3(-35.0, 25.0, 0.0)
const PHONE_UP_POS := Vector3(0.0, -0.22, -0.42)
const PHONE_UP_ROT := Vector3(78.0, 0.0, 0.0)

var gravity: float = 11.5
var noclip_enabled: bool = false
var flashlight_enabled: bool = true
var phone_open: bool = false
var broom_equipped: bool = false
var ui_blocking_input: bool = false
var inspected_node: Node = null   # object under the crosshair (set by _update_raycast_inspector)

var _yaw: float = 0.0
var _pitch: float = 0.0
var _bob_time: float = 0.0
var _step_distance: float = 0.0
var _sway_offset: Vector2 = Vector2.ZERO

var _col_shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _head: Node3D
var _cam: Camera3D
var _hand_rig: Node3D

var _flashlight_pivot: Node3D
var _spot_inner: SpotLight3D
var _spot_outer: SpotLight3D
var _phone_pivot: Node3D
var _phone_light: OmniLight3D
var _phone_screen_mesh: MeshInstance3D
var _phone_t: float = 0.0
var _broom_pivot: Node3D

var _sfx_player: AudioStreamPlayer
var _sfx_playback: AudioStreamGeneratorPlayback
var _file_sfx_player: AudioStreamPlayer = null
var _click_stream: AudioStream = null
var _phone_stream: AudioStream = null
var _last_ray_text: String = ""


func _ready() -> void:
	_build_player_hierarchy()
	_yaw = rotation.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_emit_status()


func _build_player_hierarchy() -> void:
	# Capsule collider
	_col_shape = CollisionShape3D.new()
	_col_shape.name = "BodyCollider"
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.33
	_capsule.height = STAND_HEIGHT
	_col_shape.shape = _capsule
	_col_shape.position = Vector3(0.0, STAND_HEIGHT * 0.5, 0.0)
	add_child(_col_shape)

	# Head & First-Person Camera
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, STAND_EYE_Y, 0.0)
	add_child(_head)

	_cam = Camera3D.new()
	_cam.name = "FPSCamera"
	_cam.fov = BASE_FOV
	_cam.near = 0.04
	_cam.far = 450.0
	_cam.current = true
	_head.add_child(_cam)

	# Hand rig with Fears-to-Fathom lag/sway
	_hand_rig = Node3D.new()
	_hand_rig.name = "HandRig"
	_cam.add_child(_hand_rig)

	_build_flashlight_rig()
	_build_phone_rig()
	_build_broom_rig()
	_build_procedural_audio()


func _build_flashlight_rig() -> void:
	_flashlight_pivot = Node3D.new()
	_flashlight_pivot.name = "FlashlightPivot"
	_flashlight_pivot.position = Vector3(0.24, -0.21, -0.34)
	_hand_rig.add_child(_flashlight_pivot)

	# Primary crisp horror beam
	_spot_inner = SpotLight3D.new()
	_spot_inner.name = "InnerBeam"
	_spot_inner.position = Vector3(0.0, 0.0, -0.28)
	_spot_inner.light_color = Color(1.0, 0.96, 0.86)
	_spot_inner.light_energy = 4.8
	_spot_inner.spot_range = 46.0
	_spot_inner.spot_attenuation = 1.15
	_spot_inner.spot_angle = 23.0
	_spot_inner.spot_angle_attenuation = 0.55
	_spot_inner.shadow_enabled = true
	_flashlight_pivot.add_child(_spot_inner)

	# Wide ambient spill halo (classic Fears to Fathom peripheral visibility)
	_spot_outer = SpotLight3D.new()
	_spot_outer.name = "OuterSpill"
	_spot_outer.position = Vector3(0.0, 0.0, -0.26)
	_spot_outer.light_color = Color(0.92, 0.94, 1.0)
	_spot_outer.light_energy = 1.15
	_spot_outer.spot_range = 20.0
	_spot_outer.spot_angle = 52.0
	_spot_outer.spot_angle_attenuation = 1.6
	_spot_outer.shadow_enabled = false
	_flashlight_pivot.add_child(_spot_outer)


func _build_phone_rig() -> void:
	_phone_pivot = Node3D.new()
	_phone_pivot.name = "PhonePivot"
	_phone_pivot.position = PHONE_LOW_POS
	_phone_pivot.rotation_degrees = PHONE_LOW_ROT
	_phone_pivot.visible = false
	_hand_rig.add_child(_phone_pivot)

	_phone_light = OmniLight3D.new()
	_phone_light.light_color = Color(0.62, 0.80, 1.0)
	_phone_light.light_energy = 0.35
	_phone_light.omni_range = 1.2
	_phone_light.position = Vector3(0.0, 0.08, 0.06)
	_phone_pivot.add_child(_phone_light)

	# Glowing screen on the phone's top face (+Y). The phone model is 8.7 x 17.3 cm.
	_phone_screen_mesh = MeshInstance3D.new()
	_phone_screen_mesh.name = "PhoneScreenGlow"
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.074, 0.142)
	_phone_screen_mesh.mesh = quad
	_phone_screen_mesh.position = Vector3(0.0, 0.0065, 0.0)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.10, 0.16, 0.20)
	glow.emission_enabled = true
	glow.emission = Color(0.55, 0.80, 1.0)
	glow.emission_energy_multiplier = 1.4
	_phone_screen_mesh.material_override = glow
	_phone_screen_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_phone_pivot.add_child(_phone_screen_mesh)


func _build_broom_rig() -> void:
	_broom_pivot = Node3D.new()
	_broom_pivot.name = "BroomPivot"
	_broom_pivot.position = Vector3(0.30, -0.58, -0.42)
	_broom_pivot.rotation_degrees = Vector3(14.0, -18.0, 8.0)
	_broom_pivot.visible = false
	_hand_rig.add_child(_broom_pivot)


func attach_handheld_models(flashlight_node: Node3D, phone_node: Node3D, broom_node: Node3D) -> void:
	if flashlight_node != null:
		_disable_viewmodel_shadows(flashlight_node)
		# flashlight.glb: lens (steklo) sits at +Z in the file, so turn it 180 deg -> lens points forward (-Z), button stays on top
		flashlight_node.scale = Vector3(0.55, 0.55, 0.55)
		flashlight_node.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		flashlight_node.position = Vector3(0.0, -0.005, -0.076)
		_flashlight_pivot.add_child(flashlight_node)
	else:
		# Fallback sleek cylinder torch if model missing
		var fallback := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.028
		cyl.bottom_radius = 0.022
		cyl.height = 0.22
		fallback.mesh = cyl
		fallback.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		fallback.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flashlight_pivot.add_child(fallback)

	if phone_node != null:
		_disable_viewmodel_shadows(phone_node)
		# cell_phone.glb is already real size (17.3 cm), flat, top face = +Y; the pivot does the orientation
		phone_node.scale = Vector3.ONE
		phone_node.rotation_degrees = Vector3.ZERO
		_phone_pivot.add_child(phone_node)

	if broom_node != null:
		_disable_viewmodel_shadows(broom_node)
		# broom_wood_-_5mb.glb is ~219.8 units tall -> 0.0062 scale = ~1.36m real broom
		broom_node.scale = Vector3(0.0062, 0.0062, 0.0062)
		broom_node.position = Vector3(0.0, -0.35, 0.0)
		_broom_pivot.add_child(broom_node)


func _disable_viewmodel_shadows(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for ch in n.get_children():
			stack.push_back(ch)


func _build_procedural_audio() -> void:
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "ProceduralSFX"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.25
	_sfx_player.stream = gen
	_sfx_player.volume_db = -8.0
	add_child(_sfx_player)
	_sfx_player.play()
	_sfx_playback = _sfx_player.get_stream_playback() as AudioStreamGeneratorPlayback
	_load_file_sfx()


# Real .wav sfx from res://assets/audio (falls back to synth bursts if the file is missing)
func _load_file_sfx() -> void:
	_file_sfx_player = AudioStreamPlayer.new()
	_file_sfx_player.name = "FileSFX"
	_file_sfx_player.volume_db = -3.0
	add_child(_file_sfx_player)
	_click_stream = _load_stream_if_exists("res://assets/audio/sfx_flashlight_click.wav")
	_phone_stream = _load_stream_if_exists("res://assets/audio/sfx_phone_sms_beep.wav")


func _load_stream_if_exists(res_path: String) -> AudioStream:
	if not ResourceLoader.exists(res_path):
		return null
	return load(res_path) as AudioStream


func _play_file_sfx(stream: AudioStream) -> bool:
	if stream == null or _file_sfx_player == null:
		return false
	_file_sfx_player.stream = stream
	_file_sfx_player.play()
	return true


func _play_synth_burst(duration_sec: float, freq_hz: float, noise_mix: float, amp: float) -> void:
	if _sfx_playback == null:
		return
	var count: int = mini(int(duration_sec * 22050.0), _sfx_playback.get_frames_available())
	for i in range(count):
		var t: float = float(i) / 22050.0
		var env: float = exp(-t / maxf(duration_sec * 0.32, 0.004))
		var tone: float = sin(TAU * freq_hz * t)
		var nz: float = randf_range(-1.0, 1.0)
		var sample: float = lerpf(tone, nz, noise_mix) * env * amp
		_sfx_playback.push_frame(Vector2(sample, sample))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not ui_blocking_input:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not ui_blocking_input:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - mm.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-87.0), deg_to_rad(87.0))
		rotation.y = _yaw
		_head.rotation.x = _pitch
		_sway_offset.x = clampf(_sway_offset.x - mm.relative.x * 0.00055, -0.045, 0.045)
		_sway_offset.y = clampf(_sway_offset.y + mm.relative.y * 0.00055, -0.045, 0.045)

	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		match ke.keycode:
			KEY_F:
				flashlight_enabled = not flashlight_enabled
				_spot_inner.visible = flashlight_enabled
				_spot_outer.visible = flashlight_enabled
				if not _play_file_sfx(_click_stream):
					_play_synth_burst(0.045, 1350.0, 0.55, 0.35)
				_emit_status()
			KEY_P:
				phone_open = not phone_open
				if not _play_file_sfx(_phone_stream):
					_play_synth_burst(0.05, 880.0, 0.25, 0.25)
				_emit_status()
			KEY_B:
				broom_equipped = not broom_equipped
				_broom_pivot.visible = broom_equipped
				_play_synth_burst(0.07, 240.0, 0.65, 0.28)
				_emit_status()
			KEY_E:
				if not noclip_enabled:
					interact_requested.emit(inspected_node)
			KEY_V:
				noclip_enabled = not noclip_enabled
				velocity = Vector3.ZERO
				_col_shape.disabled = noclip_enabled
				_play_synth_burst(0.06, 520.0, 0.2, 0.25)
				_emit_status()


func _physics_process(delta: float) -> void:
	if ui_blocking_input:
		_update_raycast_inspector()
		return

	var raw_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		raw_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		raw_dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		raw_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		raw_dir.y += 1.0
	if raw_dir.length_squared() > 1.0:
		raw_dir = raw_dir.normalized()

	var sprinting: bool = Input.is_key_pressed(KEY_SHIFT)
	var crouching: bool = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C)
	var zooming: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	if noclip_enabled:
		_process_noclip(delta, raw_dir, sprinting)
	else:
		_process_walking(delta, raw_dir, sprinting, crouching)

	_update_camera_and_hands(delta, raw_dir, sprinting, crouching, zooming)
	_update_raycast_inspector()


func _process_noclip(delta: float, raw_dir: Vector2, sprinting: bool) -> void:
	var cam_basis: Basis = _cam.global_transform.basis
	var move_vec: Vector3 = (cam_basis.x * raw_dir.x) + (cam_basis.z * raw_dir.y)
	if Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_E):
		move_vec.y += 1.0
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_Q):
		move_vec.y -= 1.0
	if move_vec.length_squared() > 1.0:
		move_vec = move_vec.normalized()
	var spd: float = NOCLIP_SPRINT_SPEED if sprinting else NOCLIP_SPEED
	global_position += move_vec * spd * delta


func _process_walking(delta: float, raw_dir: Vector2, sprinting: bool, crouching: bool) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_key_pressed(KEY_SPACE) and not crouching:
		velocity.y = JUMP_VELOCITY
		_play_synth_burst(0.08, 130.0, 0.75, 0.30)

	var target_speed: float = WALK_SPEED
	if crouching:
		target_speed = CROUCH_SPEED
	elif sprinting and raw_dir.y < 0.0:
		target_speed = SPRINT_SPEED

	var wish_dir: Vector3 = (transform.basis * Vector3(raw_dir.x, 0.0, raw_dir.y))
	if wish_dir.length_squared() > 0.0001:
		wish_dir = wish_dir.normalized()
		velocity.x = move_toward(velocity.x, wish_dir.x * target_speed, 22.0 * delta)
		velocity.z = move_toward(velocity.z, wish_dir.z * target_speed, 22.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)

	# Smooth capsule crouch height
	var goal_h: float = CROUCH_HEIGHT if crouching else STAND_HEIGHT
	_capsule.height = lerpf(_capsule.height, goal_h, 11.0 * delta)
	_col_shape.position.y = _capsule.height * 0.5

	move_and_slide()

	# Procedural footsteps
	var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horiz_speed > 0.45:
		_step_distance += horiz_speed * delta
		var stride: float = 1.55 if not sprinting else 2.05
		if _step_distance >= stride:
			_step_distance = 0.0
			_play_synth_burst(0.065, randf_range(95.0, 135.0), 0.82, 0.24 if crouching else 0.40)

	# Safety respawn if player falls below map boundary
	if global_position.y < -40.0:
		teleport_to(Vector3(0.0, 0.5, 8.0), 0.0)


func _update_camera_and_hands(delta: float, raw_dir: Vector2, sprinting: bool, crouching: bool, zooming: bool) -> void:
	var base_eye_y: float = CROUCH_EYE_Y if (crouching and not noclip_enabled) else STAND_EYE_Y
	var horiz_vel: float = Vector2(velocity.x, velocity.z).length()

	var bob_y: float = 0.0
	var bob_x: float = 0.0
	if not noclip_enabled and is_on_floor() and horiz_vel > 0.35:
		var freq: float = 12.5 if sprinting else (6.8 if crouching else 9.2)
		var amp: float = 0.048 if sprinting else (0.020 if crouching else 0.032)
		_bob_time += delta * freq
		bob_y = sin(_bob_time) * amp
		bob_x = cos(_bob_time * 0.5) * amp * 0.65
	else:
		_bob_time += delta * 1.4
		bob_y = sin(_bob_time) * 0.005

	_head.position.y = lerpf(_head.position.y, base_eye_y + bob_y, 12.0 * delta)
	_head.position.x = lerpf(_head.position.x, bob_x, 10.0 * delta)

	# Fears-to-Fathom Right-Click Zoom / Sprint FOV
	var target_fov: float = BASE_FOV
	if zooming:
		target_fov = ZOOM_FOV
	elif sprinting and raw_dir.y < -0.1 and not crouching:
		target_fov = SPRINT_FOV
	_cam.fov = lerpf(_cam.fov, target_fov, 10.0 * delta)

	# Smooth hand sway
	_sway_offset = _sway_offset.lerp(Vector2.ZERO, 9.0 * delta)
	_hand_rig.position = Vector3(_sway_offset.x, _sway_offset.y + bob_y * 0.35, 0.0)

	# Flashlight drops out of the way while the phone is up
	var flash_goal_y: float = -0.21 if (flashlight_enabled and not phone_open) else -0.42
	_flashlight_pivot.position.y = lerpf(_flashlight_pivot.position.y, flash_goal_y, 10.0 * delta)

	# Phone: raise / lower between the hand pose and the face pose
	_phone_t = move_toward(_phone_t, 1.0 if phone_open else 0.0, delta * 3.4)
	var e: float = smoothstep(0.0, 1.0, _phone_t)
	_phone_pivot.position = PHONE_LOW_POS.lerp(PHONE_UP_POS, e)
	_phone_pivot.rotation_degrees = PHONE_LOW_ROT.lerp(PHONE_UP_ROT, e)
	_phone_pivot.visible = _phone_t > 0.002


# Inspector: finds the prop under the crosshair.
# It does NOT use physics ray queries (get_world_3d().direct_space_state.intersect_ray).
# Both crashes (Gas_Pilar, Utility Pole) happened inside that query, so we test the
# "inspectable" box colliders with plain ray-vs-OBB maths instead. Movement still uses physics.
const INSPECT_RANGE: float = 65.0
const INSPECT_INTERVAL: float = 0.08
var _inspect_timer: float = 0.0


func _update_raycast_inspector() -> void:
	if _cam == null or get_tree() == null:
		return
	_inspect_timer -= get_physics_process_delta_time()
	if _inspect_timer > 0.0:
		return
	_inspect_timer = INSPECT_INTERVAL

	var from: Vector3 = _cam.global_position
	var dir: Vector3 = -_cam.global_transform.basis.z
	var best_t: float = INF
	var best_node: Node = null

	for n in get_tree().get_nodes_in_group("inspectable"):
		var sb := n as StaticBody3D
		if sb == null or not sb.is_inside_tree():
			continue
		var cs: CollisionShape3D = null
		for ch in sb.get_children():
			if ch is CollisionShape3D:
				cs = ch as CollisionShape3D
				break
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var half: Vector3 = (cs.shape as BoxShape3D).size * 0.5
		var box_xf: Transform3D = sb.global_transform * cs.transform
		if box_xf.origin.distance_to(from) > INSPECT_RANGE + half.length():
			continue
		var inv: Transform3D = box_xf.affine_inverse()
		var t: float = _ray_box_fraction(inv * from, inv.basis * (dir * INSPECT_RANGE), half)
		if t >= 0.0 and t < best_t:
			best_t = t
			best_node = sb

	inspected_node = best_node
	var text: String = ""
	if best_node != null:
		var dist: float = best_t * INSPECT_RANGE
		if best_node.has_meta("asset_label"):
			text = "%s  [%.1fm]" % [str(best_node.get_meta("asset_label")), dist]
		else:
			text = "%s  [%.1fm]" % [str(best_node.name), dist]
	if text != _last_ray_text:
		_last_ray_text = text
		inspected_target_changed.emit(text)


# Slab test: ray origin o, direction d (already scaled to range), box half-size h, box centred at 0.
# Returns the fraction t in [0, 1] of the first hit, or -1.0 when there is no hit.
static func _ray_box_fraction(o: Vector3, d: Vector3, h: Vector3) -> float:
	var tmin: float = 0.0
	var tmax: float = 1.0
	for axis in 3:
		var oa: float = o[axis]
		var da: float = d[axis]
		var ha: float = h[axis]
		if absf(da) < 0.000001:
			if oa < -ha or oa > ha:
				return -1.0
		else:
			var t1: float = (-ha - oa) / da
			var t2: float = (ha - oa) / da
			if t1 > t2:
				var tmp: float = t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	return tmin


func teleport_to(world_pos: Vector3, face_yaw_deg: float = 0.0) -> void:
	velocity = Vector3.ZERO
	global_position = world_pos
	_yaw = deg_to_rad(face_yaw_deg)
	_pitch = 0.0
	rotation.y = _yaw
	if _head != null:
		_head.rotation.x = 0.0


func _emit_status() -> void:
	mode_status_changed.emit(noclip_enabled, flashlight_enabled, phone_open, broom_equipped)
