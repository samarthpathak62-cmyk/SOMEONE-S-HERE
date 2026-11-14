extends Node3D

# Mile 47 map test scene: one gas station model, first-person controls, scripted animations.

var _world_env: WorldEnvironment
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun_moon: DirectionalLight3D

var _player: HorrorPlayerController
var _phone_ui: PhoneScreenUI
var _map_loader: RetroMapLoader

var _vhs_rect: ColorRect
var _hud_card: PanelContainer
var _hud_lbl: Label
var _ray_lbl: Label
var _prompt_lbl: Label

var _daylight_inspector_on: bool = false
var _vhs_enabled: bool = true
var _hud_visible: bool = true
var _last_prompt: String = ""


func _ready() -> void:
	_setup_environment_and_lighting()
	_setup_map_loader_and_player()
	_setup_ui_and_vhs_overlay()
	_setup_ambience()
	_map_loader.build_all_and_equip_player(_player)
	_refresh_hud_text()


func _process(_delta: float) -> void:
	var hint: String = _map_loader.hint_for(_player.inspected_node)
	if hint != _last_prompt:
		_last_prompt = hint
		_prompt_lbl.text = hint


# Night ambience: wind + crickets loops from res://assets/audio (skipped if missing)
func _setup_ambience() -> void:
	_add_loop_player("res://assets/audio/amb_wind_loop.wav", -12.0, "AmbWind")
	_add_loop_player("res://assets/audio/amb_night_crickets_loop.wav", -16.0, "AmbCrickets")


func _add_loop_player(res_path: String, volume_db: float, node_name: String) -> void:
	if not ResourceLoader.exists(res_path):
		return
	var stream := load(res_path) as AudioStreamWAV
	if stream == null:
		return
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = int(stream.get_length() * float(stream.mix_rate))
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.stream = stream
	p.volume_db = volume_db
	add_child(p)
	p.play()


func _setup_environment_and_lighting() -> void:
	_world_env = WorldEnvironment.new()
	_world_env.name = "WorldEnvironment"
	_env = Environment.new()

	_sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = true
	_env.glow_intensity = 0.55

	_world_env.environment = _env
	add_child(_world_env)

	_sun_moon = DirectionalLight3D.new()
	_sun_moon.name = "MoonOrSunLight"
	_sun_moon.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	_sun_moon.shadow_enabled = true
	add_child(_sun_moon)

	_apply_lighting_mode()


func _apply_lighting_mode() -> void:
	if _daylight_inspector_on:
		# Bright inspection lighting so every shop shelf and item is visible
		_sky_mat.sky_top_color = Color(0.32, 0.52, 0.78)
		_sky_mat.sky_horizon_color = Color(0.64, 0.74, 0.86)
		_sky_mat.ground_bottom_color = Color(0.18, 0.20, 0.18)
		_sky_mat.ground_horizon_color = Color(0.45, 0.48, 0.46)
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.ambient_light_color = Color(0.88, 0.90, 0.95)
		_env.ambient_light_energy = 0.95
		_env.fog_enabled = false
		_sun_moon.light_color = Color(1.0, 0.97, 0.90)
		_sun_moon.light_energy = 1.65
	else:
		# Night horror atmosphere
		_sky_mat.sky_top_color = Color(0.015, 0.022, 0.042)
		_sky_mat.sky_horizon_color = Color(0.045, 0.055, 0.082)
		_sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.015)
		_sky_mat.ground_horizon_color = Color(0.03, 0.035, 0.05)
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.ambient_light_color = Color(0.13, 0.16, 0.24)
		_env.ambient_light_energy = 0.36
		_env.fog_enabled = true
		_env.fog_light_color = Color(0.045, 0.055, 0.075)
		_env.fog_density = 0.012
		_sun_moon.light_color = Color(0.58, 0.68, 0.90)
		_sun_moon.light_energy = 0.28


func _setup_map_loader_and_player() -> void:
	_map_loader = RetroMapLoader.new()
	_map_loader.name = "Mile47Map"
	add_child(_map_loader)

	var player_scene: PackedScene = load("res://scenes/player.tscn") as PackedScene
	if player_scene != null:
		_player = player_scene.instantiate() as HorrorPlayerController
	else:
		_player = HorrorPlayerController.new()
	_player.name = "Player"
	_player.position = _map_loader.landmark_station
	add_child(_player)

	_player.inspected_target_changed.connect(_on_inspected_target_changed)
	_player.interact_requested.connect(_on_interact_requested)

	_phone_ui = PhoneScreenUI.new()
	_phone_ui.name = "PhoneScreenUI"
	add_child(_phone_ui)
	_player.mode_status_changed.connect(func(_a: bool, _b: bool, phone_on: bool, _d: bool) -> void:
		_phone_ui.set_open(phone_on)
		_refresh_hud_text()
	)


func _setup_ui_and_vhs_overlay() -> void:
	# VHS / PSX post-processing overlay
	var vhs_layer := CanvasLayer.new()
	vhs_layer.name = "VHSOverlayLayer"
	vhs_layer.layer = 1
	add_child(vhs_layer)

	_vhs_rect = ColorRect.new()
	_vhs_rect.name = "VHSShaderRect"
	_vhs_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vhs_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh: Shader = load("res://shaders/vhs_psx_overlay.gdshader") as Shader
	if sh != null:
		var sm := ShaderMaterial.new()
		sm.shader = sh
		_vhs_rect.material = sm
	vhs_layer.add_child(_vhs_rect)

	# HUD layer
	var hud_layer := CanvasLayer.new()
	hud_layer.name = "HUDLayer"
	hud_layer.layer = 2
	add_child(hud_layer)

	_hud_card = _make_styled_panel(Color(0.02, 0.03, 0.04, 0.72))
	_hud_card.position = Vector2(16.0, 16.0)
	hud_layer.add_child(_hud_card)
	_hud_lbl = Label.new()
	_hud_lbl.add_theme_font_size_override("font_size", 14)
	_hud_lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 0.9))
	_hud_card.add_child(_hud_lbl)

	# Crosshair
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 22)
	cross.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 0.7))
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(-6.0, -16.0)
	hud_layer.add_child(cross)

	# Inspector target (bottom centre)
	_ray_lbl = Label.new()
	_ray_lbl.add_theme_font_size_override("font_size", 15)
	_ray_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_ray_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ray_lbl.position = Vector2(-300.0, -90.0)
	_ray_lbl.custom_minimum_size = Vector2(600.0, 0.0)
	_ray_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_layer.add_child(_ray_lbl)

	# Interaction prompt (just above the target line)
	_prompt_lbl = Label.new()
	_prompt_lbl.add_theme_font_size_override("font_size", 18)
	_prompt_lbl.add_theme_color_override("font_color", Color(0.85, 1.0, 0.75))
	_prompt_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_prompt_lbl.add_theme_constant_override("outline_size", 6)
	_prompt_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_lbl.position = Vector2(-300.0, -130.0)
	_prompt_lbl.custom_minimum_size = Vector2(600.0, 0.0)
	_prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_layer.add_child(_prompt_lbl)


func _make_styled_panel(bg_color: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	pc.add_theme_stylebox_override("panel", sb)
	return pc


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		match ke.keycode:
			KEY_ESCAPE:
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			KEY_L:
				_daylight_inspector_on = not _daylight_inspector_on
				_apply_lighting_mode()
				_refresh_hud_text()
			KEY_G:
				_vhs_enabled = not _vhs_enabled
				_vhs_rect.visible = _vhs_enabled
				_refresh_hud_text()
			KEY_H:
				_hud_visible = not _hud_visible
				_hud_card.visible = _hud_visible
			KEY_1:
				_player.teleport_to(_map_loader.landmark_station, 0.0)
			KEY_2:
				_player.teleport_to(_map_loader.landmark_store, 0.0)


func _on_interact_requested(target: Node) -> void:
	var what: String = _map_loader.interact_with(target)
	if not what.is_empty():
		_refresh_hud_text("Used: " + what)


func _on_inspected_target_changed(desc: String) -> void:
	_ray_lbl.text = ("Target: " + desc) if not desc.is_empty() else ""


func _refresh_hud_text(extra: String = "") -> void:
	var move_mode: String = "NOCLIP (fly, pass walls)" if _player.noclip_enabled else "WALK"
	var light_mode: String = "DAYLIGHT INSPECT" if _daylight_inspector_on else "NIGHT HORROR"
	var lines: PackedStringArray = PackedStringArray()
	lines.append("SOMEONE'S HERE: Mile 47 Gas & Mart (map test)")
	lines.append("----------------------------------------")
	lines.append("Map: gas_station.glb  (animations scripted)")
	lines.append("Move [V]: %s   Light [L]: %s   VHS [G]: %s" % [
		move_mode, light_mode, "ON" if _vhs_enabled else "OFF"])
	lines.append("Flashlight [F]: %s   Phone [P]: %s   Broom [B]: %s" % [
		"ON" if _player.flashlight_enabled else "OFF",
		"UP" if _player.phone_open else "DOWN",
		"HELD" if _player.broom_equipped else "OFF"])
	lines.append("----------------------------------------")
	lines.append("WASD move | Shift sprint | Ctrl crouch | RMB zoom | E interact")
	lines.append("[1] Forecourt   [2] Inside the shop   [H] hide HUD   [ESC] mouse")
	if not extra.is_empty():
		lines.append(">> " + extra)
	_hud_lbl.text = "\n".join(lines)
