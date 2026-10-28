class_name DeadZoneHUD
extends CanvasLayer

# HUD built in code: HP bar, round + enemies, ammo + gear counts, crosshair,
# announcements, damage vignette, win / lose overlays.

var _hp_fill: ColorRect
var _hp_label: Label
var _round_label: Label
var _ammo_label: Label
var _gear_label: Label
var _msg_label: Label
var _msg_timer: float = 0.0
var _vignette: ColorRect
var _overlay: Panel
var _overlay_title: Label
var _overlay_sub: Label
var _crosshair: Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

var touch_mode: bool = false
var _hp_bg: ColorRect
var _vp := Vector2(1280, 720)
var _ui: float = 1.0

func _build() -> void:
	touch_mode = TouchControls.is_touch_device()
	_ui = 1.3 if touch_mode else 1.0
	var fs := func(n: int) -> int: return int(round(n * _ui))
	# --- HP bar (top-left) ---
	_hp_bg = ColorRect.new()
	_hp_bg.color = Color(0, 0, 0, 0.6)
	add_child(_hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.7, 0.18, 0.12)
	add_child(_hp_fill)
	_hp_label = _label("HP 100", Vector2.ZERO, fs.call(18), Color(1, 1, 1))
	# --- Round (top-center) ---
	_round_label = _label("ROUND 1 / 3", Vector2.ZERO, fs.call(24), Color(1, 0.8, 0.3))
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# --- Ammo + gear (top-right) ---
	_ammo_label = _label("30 / 30", Vector2.ZERO, fs.call(30), Color(1, 1, 1))
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gear_label = _label("", Vector2.ZERO, fs.call(17), Color(0.8, 0.85, 0.8))
	_gear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# --- Crosshair (center) ---
	_crosshair = Control.new()
	_crosshair.size = Vector2(2, 2)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)
	for rect in [
		[Vector2(-1, -14), Vector2(2, 10)], [Vector2(-1, 4), Vector2(2, 10)],
		[Vector2(-14, -1), Vector2(10, 2)], [Vector2(4, -1), Vector2(10, 2)],
	]:
		var bar := ColorRect.new()
		bar.color = Color(1, 1, 1, 0.9)
		bar.position = rect[0]
		bar.size = rect[1]
		_crosshair.add_child(bar)
	var dot := ColorRect.new()
	dot.color = Color(1, 0.85, 0.2)
	dot.position = Vector2(-2, -2)
	dot.size = Vector2(4, 4)
	_crosshair.add_child(dot)
	# --- Message (above the bottom controls) ---
	_msg_label = _label("", Vector2.ZERO, fs.call(22), Color(1, 0.85, 0.3))
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# --- Damage vignette ---
	_vignette = ColorRect.new()
	_vignette.color = Color(0.8, 0.05, 0.05, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)
	# --- Win / lose overlay ---
	_overlay = Panel.new()
	_overlay.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.04, 0.92)
	style.border_color = Color(0.9, 0.7, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	_overlay.add_theme_stylebox_override("panel", style)
	add_child(_overlay)
	_overlay_title = _label("", Vector2(0, 30), 44, Color(1, 0.8, 0.3), _overlay)
	_overlay_title.size = Vector2(600, 60)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_sub = _label("", Vector2(0, 110), 20, Color(0.9, 0.9, 0.9), _overlay)
	_overlay_sub.size = Vector2(600, 100)
	_overlay_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	get_viewport().size_changed.connect(_layout)
	_layout()

# Positions follow the live viewport size (stretch "expand" widens it on
# phones with wide screens), so nothing is clipped on any landscape aspect.
func _layout() -> void:
	_vp = get_viewport().get_visible_rect().size
	var w := _vp.x
	var m := 16.0 * _ui
	var bar_w := 260.0 * _ui
	_hp_bg.position = Vector2(m, m)
	_hp_bg.size = Vector2(bar_w, 26)
	_hp_fill.position = _hp_bg.position + Vector2(2, 2)
	_hp_label.position = Vector2(m + 4, m + 28)
	_round_label.size = Vector2(w * 0.42, 40)
	_round_label.position = Vector2((w - _round_label.size.x) * 0.5, 12)
	_ammo_label.size = Vector2(300, 44)
	_ammo_label.position = Vector2(w - 300 - m, 10)
	_gear_label.size = Vector2(340, 28)
	_gear_label.position = Vector2(w - 340 - m, 10 + 44 * _ui * 0.85)
	_crosshair.position = _vp * 0.5
	_msg_label.size = Vector2(w * 0.5, 34)
	_msg_label.position = Vector2((w - _msg_label.size.x) * 0.5, _vp.y * (0.25 if touch_mode else 0.88))
	_vignette.position = Vector2.ZERO
	_vignette.size = _vp
	_overlay.size = Vector2(600, 260)
	_overlay.position = (_vp - _overlay.size) * 0.5
	set_hp_fill()

var _hp_frac: float = 1.0

func set_hp_fill() -> void:
	_hp_fill.size = Vector2((_hp_bg.size.x - 4.0) * _hp_frac, 22)

func _label(text: String, pos: Vector2, size: int, color: Color, parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	(parent if parent != null else self).add_child(l)
	return l

func _process(delta: float) -> void:
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			_msg_label.text = ""
	if _vignette.color.a > 0.0:
		var c := _vignette.color
		c.a = maxf(0.0, c.a - delta * 1.6)
		_vignette.color = c

func set_hp(hp: float, max_hp: float) -> void:
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	_hp_frac = frac
	set_hp_fill()
	_hp_fill.color = Color(0.7, 0.18, 0.12) if frac > 0.3 else Color(0.9, 0.1, 0.05)
	_hp_label.text = "HP %d" % int(hp)

func set_round(round_num: int, total: int, enemies_left: int) -> void:
	_round_label.text = "ROUND %d / %d   —   BOMBIES LEFT: %d" % [round_num, total, enemies_left]

func set_ammo(mag: int, mag_size: int, grenades: int, mines: int, traps: int) -> void:
	_ammo_label.text = "%d / %d" % [mag, mag_size]
	_gear_label.text = "GND %d   ·   MIN %d   ·   ACID %d" % [grenades, mines, traps]

func show_message(text: String, hold: float = 2.5) -> void:
	_msg_label.text = text
	_msg_timer = hold

func damage_flash() -> void:
	var c := _vignette.color
	c.a = 0.45
	_vignette.color = c

func show_win() -> void:
	_overlay_title.text = "DEAD ZONE CLEARED"
	_overlay_title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	_overlay_sub.text = "Round 3 survived. The exit stairwell is open — the garage is yours.\n%s" % _restart_hint("run it back")
	_overlay.visible = true
	_crosshair.visible = false

func show_lose() -> void:
	_overlay_title.text = "SQUAD DOWN"
	_overlay_title.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	_overlay_sub.text = "The hazmat engineer is down and the horde keeps coming.\n%s" % _restart_hint("try again")
	_overlay.visible = true
	_crosshair.visible = false

func _restart_hint(what: String) -> String:
	return ("TAP ANYWHERE to %s." if touch_mode else "Press R to %s.") % what
