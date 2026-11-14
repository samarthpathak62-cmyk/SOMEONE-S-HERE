extends Node3D

var _world_env: WorldEnvironment
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _sun_moon: DirectionalLight3D

var _player: HorrorPlayerController
var _phone_ui: PhoneScreenUI
var _map_loader: RetroMapLoader

var _vhs_rect: ColorRect
var _hud_card: PanelContainer
var _status_lbl: Label
var _ray_lbl: Label
var _banner_panel: PanelContainer
var _banner_lbl: Label
var _manifest_panel: PanelContainer
var _manifest_vbox: VBoxContainer

var _daylight_inspector_on: bool = false
var _vhs_enabled: bool = true
var _hud_visible: bool = true
var _manifest_open: bool = false


func _ready() -> void:
	_setup_environment_and_lighting()
	_setup_map_loader_and_player()
	_setup_ui_and_vhs_overlay()
	_setup_ambience()

	get_window().files_dropped.connect(_on_files_dropped)

	# Build map & equip player handhelds
	_map_loader.build_all_and_equip_player(_player)
	_refresh_hud_text()


# Night ambience: wind + crickets loops from res://assets/audio (silently skipped if missing)
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
		# Bright clear inspection lighting so shop interiors & meshes are 100% visible
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
		# Authentic Fears-to-Fathom Highway Midnight Horror Atmosphere
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
	_map_loader.name = "RetroMapLoader"
	add_child(_map_loader)

	var player_scene: PackedScene = load("res://scenes/player.tscn") as PackedScene
	if player_scene != null:
		_player = player_scene.instantiate() as HorrorPlayerController
	else:
		_player = HorrorPlayerController.new()
	_player.name = "Player"
	_player.position = Vector3(5.0, 0.25, 3.0)
	add_child(_player)

	_player.inspected_target_changed.connect(_on_inspected_target_changed)
	_phone_ui = PhoneScreenUI.new()
	_phone_ui.name = "PhoneScreenUI"
	add_child(_phone_ui)
	_player.mode_status_changed.connect(func(_a: bool, _b: bool, phone_on: bool, _d: bool) -> void:
		_phone_ui.set_open(phone_on)
		_refresh_hud_text()
	)
	_map_loader.loading_status_updated.connect(_on_loading_status_updated)
	_map_loader.manifest_updated.connect(_rebuild_manifest_rows)


func _setup_ui_and_vhs_overlay() -> void:
	# Layer 1: VHS Post-Processing Shader
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

	# Layer 2: Crisp HUD & Interactive Asset Manifest
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "HUDLayer"
	ui_layer.layer = 2
	add_child(ui_layer)

	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(root_ctrl)

	# Minimal Fears-to-Fathom center dot crosshair
	var crosshair := ColorRect.new()
	crosshair.custom_minimum_size = Vector2(4.0, 4.0)
	crosshair.size = Vector2(4.0, 4.0)
	crosshair.color = Color(1.0, 1.0, 1.0, 0.78)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-2.0, -2.0)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(crosshair)

	# Top-Left Controls & Status Card
	_hud_card = _make_styled_panel(Color(0.04, 0.05, 0.07, 0.80))
	_hud_card.position = Vector2(16.0, 16.0)
	_hud_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(_hud_card)

	_status_lbl = Label.new()
	_status_lbl.add_theme_font_size_override("font_size", 14)
	_status_lbl.add_theme_color_override("font_color", Color(0.90, 0.93, 0.96))
	_hud_card.add_child(_status_lbl)

	# Top-Right / Top-Center Drag & Drop Notice Banner (hidden when RetroWorld loads)
	_banner_panel = _make_styled_panel(Color(0.28, 0.14, 0.04, 0.92))
	_banner_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner_panel.offset_left = 430.0
	_banner_panel.offset_right = -20.0
	_banner_panel.offset_top = 16.0
	_banner_panel.offset_bottom = 86.0
	_banner_panel.visible = false
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(_banner_panel)

	_banner_lbl = Label.new()
	_banner_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_lbl.add_theme_font_size_override("font_size", 14)
	_banner_lbl.add_theme_color_override("font_color", Color(1.0, 0.91, 0.62))
	_banner_panel.add_child(_banner_lbl)

	# Bottom Raycast Target Inspector Bar
	var bottom_box := _make_styled_panel(Color(0.03, 0.04, 0.06, 0.78))
	bottom_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_box.offset_left = 260.0
	bottom_box.offset_right = -260.0
	bottom_box.offset_top = -54.0
	bottom_box.offset_bottom = -14.0
	bottom_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ctrl.add_child(bottom_box)

	_ray_lbl = Label.new()
	_ray_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ray_lbl.text = "Point crosshair at any 3D object to inspect file name, size & mesh part"
	_ray_lbl.add_theme_font_size_override("font_size", 15)
	_ray_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.62))
	bottom_box.add_child(_ray_lbl)

	# Tab Modal: Full Loaded Asset Manifest + Teleport Buttons
	_manifest_panel = _make_styled_panel(Color(0.05, 0.06, 0.09, 0.95))
	_manifest_panel.set_anchors_preset(Control.PRESET_CENTER)
	_manifest_panel.offset_left = -460.0
	_manifest_panel.offset_right = 460.0
	_manifest_panel.offset_top = -310.0
	_manifest_panel.offset_bottom = 310.0
	_manifest_panel.visible = false
	root_ctrl.add_child(_manifest_panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 10)
	_manifest_panel.add_child(outer_vbox)

	var header := Label.new()
	header.text = "LOADED 3D ASSET MANIFEST  (Click [Teleport] to jump right in front of any model  |  Press TAB to close)"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(0.65, 0.92, 1.0))
	outer_vbox.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(880.0, 520.0)
	outer_vbox.add_child(scroll)

	_manifest_vbox = VBoxContainer.new()
	_manifest_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_manifest_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(_manifest_vbox)


func _make_styled_panel(bg_color: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = Color(0.35, 0.40, 0.48, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	pc.add_theme_stylebox_override("panel", sb)
	return pc


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		match ke.keycode:
			KEY_ESCAPE:
				if _manifest_open:
					_toggle_manifest(false)
				elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			KEY_TAB:
				_toggle_manifest(not _manifest_open)
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
				_player.teleport_to(_map_loader.landmark_campsite, 0.0)
			KEY_3:
				_player.teleport_to(_map_loader.landmark_gallery, 180.0)
			KEY_4:
				_player.teleport_to(_map_loader.landmark_showcase, 0.0)
			KEY_N:
				var clip: String = _map_loader.cycle_enemy_clip()
				if not clip.is_empty():
					_refresh_hud_text("Enemy clip: " + clip)


func _toggle_manifest(open_state: bool) -> void:
	_manifest_open = open_state
	_manifest_panel.visible = _manifest_open
	_player.ui_blocking_input = _manifest_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _manifest_open else Input.MOUSE_MODE_CAPTURED


func _rebuild_manifest_rows(entries: Array) -> void:
	for ch in _manifest_vbox.get_children():
		ch.queue_free()

	if entries.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No external models detected yet. Drag & drop '3D_Retro_World 0.01.zip' onto this window!"
		_manifest_vbox.add_child(empty_lbl)
		return

	for item in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.text = "[%s]  %s   (%s | %d meshes)" % [
			str(item.get("category", "")),
			str(item.get("name", "")),
			str(item.get("size_text", "")),
			int(item.get("meshes", 1))
		]
		info.add_theme_font_size_override("font_size", 14)
		row.add_child(info)

		var btn := Button.new()
		btn.text = "Teleport"
		var target_pos: Vector3 = item.get("pos", Vector3(0.0, 0.5, 8.0))
		btn.pressed.connect(func() -> void:
			_toggle_manifest(false)
			_player.teleport_to(target_pos, 0.0)
		)
		row.add_child(btn)
		_manifest_vbox.add_child(row)


func _on_inspected_target_changed(desc: String) -> void:
	if desc.is_empty():
		_ray_lbl.text = "Sky / Distance  (Press [V] Noclip Fly to inspect inside walls/roofs, [L] Bright Light)"
	else:
		_ray_lbl.text = "Target: " + desc


func _on_loading_status_updated(summary_text: String, show_lfs_banner: bool) -> void:
	_banner_panel.visible = show_lfs_banner
	if show_lfs_banner:
		_banner_lbl.text = "NOTE: '3D_Retro_World 0.01.zip' in repo is a 134B Git LFS pointer. Simply DRAG & DROP your real '3D_Retro_World 0.01.zip' (or unzipped folder) onto this game window to spawn the entire pack!"
	_refresh_hud_text(summary_text)


func _on_files_dropped(files: PackedStringArray) -> void:
	_map_loader.load_dropped_paths(files)


func _refresh_hud_text(_extra: String = "") -> void:
	if _status_lbl == null or _player == null:
		return
	var move_mode: String = "NOCLIP FLY (Pass Through Walls!)" if _player.noclip_enabled else "FIRST-PERSON WALK"
	var light_mode: String = "BRIGHT INSPECTOR DAYLIGHT" if _daylight_inspector_on else "NIGHT HORROR (Fears to Fathom)"
	var rw_state: String = "LOADED" if (_map_loader != null and _map_loader.retroworld_loaded) else "WAITING FOR .ZIP / FOLDER DROP"

	_status_lbl.text = (
		"SOMEONE'S HERE — MAP & CONTROLS TEST\n"
		+ "----------------------------------------\n"
		+ "3D_Retro_World: %s\n" % rw_state
		+ "Movement [V]: %s\n" % move_mode
		+ "Lighting [L]: %s   |   VHS [G]: %s\n" % [light_mode, "ON" if _vhs_enabled else "OFF"]
		+ "Flashlight [F]: %s  |  Phone [P]: %s  |  Broom [B]: %s\n" % [
			"ON" if _player.flashlight_enabled else "OFF",
			"UP" if _player.phone_open else "DOWN",
			"HELD" if _player.broom_equipped else "OFF"
		]
		+ "----------------------------------------\n"
		+ "WASD: Move | Shift: Sprint | Ctrl/C: Crouch | RMB: Zoom\n"
		+ "[1] Station  [2] Campsite  [3] All Models Grid  [4] Cars/Props\n"
		+ "[TAB] Full Asset List & Teleport | [H] Hide HUD | [ESC] Mouse"
	)
