extends CanvasLayer
class_name PhoneScreenUI

# Phone messages overlay: shown while the phone is raised (P). Fears to Fathom style:
# texts from the manager / people in the story pop up on the phone screen.
# Placeholder texts for the Act 1 SMS flow; the real script comes in the story phase.
const MESSAGES: Array[Dictionary] = [
	{"time": "10:58 PM", "from": "Vikram (Manager)", "text": "Kabir, aaj raat tera shift hai. Pumps check kar lena, cooler on rakhna."},
	{"time": "11:31 PM", "from": "Vikram (Manager)", "text": "Register ka cash count karke drawer band kar. Bahar wala pole light flicker kar raha hai, dhyan rakhna."},
	{"time": "12:50 AM", "from": "Vikram (Manager)", "text": "Koi camper aaye to counter se hi baat karna. Gaadi ke paas mat jaana."},
]

var _panel: PanelContainer
var _clock_lbl: Label
var _list: VBoxContainer


func _ready() -> void:
	layer = 5

	_panel = PanelContainer.new()
	_panel.name = "PhonePanel"
	# Anchored bottom-centre, sized like a phone screen (about 340 x 530 px)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -170.0
	_panel.offset_right = 170.0
	_panel.offset_top = -560.0
	_panel.offset_bottom = -30.0
	_panel.add_theme_stylebox_override("panel", _style(Color(0.03, 0.05, 0.07, 0.94), 26, Color(0.28, 0.30, 0.34), 4))
	_panel.visible = false
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)

	# Status bar
	var status := HBoxContainer.new()
	col.add_child(status)
	_clock_lbl = Label.new()
	_clock_lbl.add_theme_font_size_override("font_size", 16)
	_clock_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	_clock_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(_clock_lbl)
	var bars := Label.new()
	bars.text = "||| 1 BAR"
	bars.add_theme_font_size_override("font_size", 16)
	bars.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	status.add_child(bars)

	var header := Label.new()
	header.text = "Messages"
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	col.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	for m in MESSAGES:
		_list.add_child(_make_bubble(m))

	var footer := Label.new()
	footer.text = "[P] Put phone away"
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color(0.55, 0.58, 0.62))
	col.add_child(footer)


func set_open(open_state: bool) -> void:
	if _panel == null:
		return
	_panel.visible = open_state
	if open_state:
		_clock_lbl.text = "11:14 PM"


func _make_bubble(m: Dictionary) -> PanelContainer:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _style(Color(0.13, 0.17, 0.21), 14, Color(0, 0, 0, 0), 0))
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	box.add_child(inner)

	var who := Label.new()
	who.text = "%s   %s" % [str(m["from"]), str(m["time"])]
	who.add_theme_font_size_override("font_size", 12)
	who.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
	inner.add_child(who)

	var body := Label.new()
	body.text = str(m["text"])
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(290.0, 0.0)
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
	inner.add_child(body)
	return box


func _style(bg: Color, radius: int, border: Color, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	return sb
