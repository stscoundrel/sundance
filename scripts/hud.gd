class_name Hud
extends Control
## Portrait and health, the gun's state (Colt cylinder, coach gun barrels, Yellow Boy
## tube), bandit count, crosshair, title card, the eyes close-up and end messages.

const BRASS := Color(0.84, 0.68, 0.3)
const BRASS_DARK := Color(0.45, 0.34, 0.14)
const SHELL := Color(0.72, 0.16, 0.12)
const INK := Color(0.93, 0.86, 0.7)
const PANEL := Color(0.08, 0.05, 0.04, 0.78)

var game: Node
var font: Font
var small: Font
var title_alpha := 1.0
var title_fading := false
var eyes_on := false
var eyes_t := 0.0
var message := ""
var sub := ""
var msg_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Rockwell", "American Typewriter", "Georgia", "Serif"])
	sf.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	sf.hinting = TextServer.HINTING_NONE
	font = sf
	small = ThemeDB.fallback_font


func hide_title() -> void:
	title_fading = true


func show_eyes() -> void:
	eyes_on = true
	eyes_t = 0.0


func hide_eyes() -> void:
	eyes_on = false


func show_message(m: String, s: String) -> void:
	message = m
	sub = s
	msg_t = 0.0


func _process(delta: float) -> void:
	var real: float = delta / max(Engine.time_scale, 0.01)
	if title_fading:
		title_alpha = max(0.0, title_alpha - real * 1.5)
	if eyes_on:
		eyes_t += real
	if message != "":
		msg_t += real
	queue_redraw()


func _text(pos: Vector2, s: String, sz: int, c: Color, f: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var fnt := f if f else small
	draw_string(fnt, pos + Vector2(1, 1), s, align, width, sz, Color(0, 0, 0, c.a * 0.8))
	draw_string(fnt, pos, s, align, width, sz, c)


func _draw() -> void:
	var p: Player = game.player
	if p == null:
		return
	if title_alpha < 1.0:
		_draw_enemy_marks()
		_draw_status(p)
		_draw_weapon(p)
		_draw_crosshair(p)
	if eyes_on:
		_draw_eyes()
	if message != "":
		_draw_message()
	if title_alpha > 0.0:
		_draw_title()


## "!" / "?" markers, suspicion bars and shouted lines above the bandits' heads,
## drawn here in screen space so the text stays crisp.
func _draw_enemy_marks() -> void:
	var to_local := get_global_transform_with_canvas().affine_inverse()
	for e in game.enemies:
		if not e.alive:
			continue
		var head: Vector2 = to_local * (e.get_global_transform_with_canvas() * Vector2(0, -40))
		if head.x < -50 or head.x > 690 or head.y < -20 or head.y > 380:
			continue
		var y := head.y
		if e.shout_t > 0.0:
			var a: float = clamp(e.shout_t * 2.0, 0.0, 1.0)
			var sz := font.get_string_size(e.shout, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
			var r := Rect2(head.x - sz.x / 2 - 4, y - 22, sz.x + 8, 14)
			draw_rect(r, Color(0.95, 0.9, 0.78, 0.9 * a))
			draw_rect(r, Color(0.2, 0.12, 0.08, a), false, 1.0)
			draw_colored_polygon(PackedVector2Array([Vector2(head.x - 3, y - 8), Vector2(head.x + 3, y - 8), Vector2(head.x, y - 4)]), Color(0.95, 0.9, 0.78, 0.9 * a))
			draw_string(font, Vector2(r.position.x + 4, y - 11), e.shout, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.25, 0.08, 0.05, a))
			y -= 16
		if e.marker_t > 0.0 and e.marker != "":
			var c := Color(1, 0.85, 0.3) if e.marker == "?" else Color(1, 0.25, 0.15)
			_text(Vector2(head.x - 3, y - 6), e.marker, 14, c, font)
		elif e.suspicion > 0.02 and e.st != Enemy.St.COMBAT:
			draw_rect(Rect2(head.x - 8, y - 6, 16, 3), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(head.x - 8, y - 6, 16 * e.suspicion, 3), Color(1, 0.8, 0.3))


func _draw_status(p: Player) -> void:
	draw_rect(Rect2(6, 310, 44, 44), PANEL)
	draw_texture_rect(game.tex(game.meta["ui"]["portrait"]), Rect2(8, 312, 40, 40), false)
	draw_rect(Rect2(6, 310, 44, 44), Color(0.5, 0.36, 0.2), false, 1.0)
	for i in p.max_hp:
		var r := Rect2(54 + i * 7, 344, 5, 8)
		draw_rect(r, Color(0.1, 0.06, 0.05, 0.85))
		if i < p.hp:
			draw_rect(r.grow(-1), Color(0.75, 0.12, 0.08))
	if p.crouched:
		_text(Vector2(54, 338), "CROUCHED", 8, INK)
	var n: int = game.alive_enemies()
	var label := "BANDITS  %d" % n
	_text(Vector2(0, 16), label, 12, INK, font, HORIZONTAL_ALIGNMENT_CENTER, 640)


func _draw_weapon(p: Player) -> void:
	var w := p.weapon
	var box := Rect2(510, 304, 124, 50)
	draw_rect(box, PANEL)
	draw_rect(box, Color(0.5, 0.36, 0.2), false, 1.0)
	_text(Vector2(516, 316), w.d["name"], 8, INK)
	var c := Vector2(536, 336)
	match w.kind:
		"colt":
			draw_circle(c, 15, Color(0.2, 0.2, 0.22))
			draw_circle(c, 3, Color(0.12, 0.12, 0.13))
			for i in 6:
				var idx := (w.cur + i) % 6
				var pos := c + Vector2.from_angle(-PI / 2 + i * TAU / 6.0) * 9.5
				match w.chambers[idx]:
					1:
						draw_circle(pos, 3.5, BRASS)
						draw_circle(pos, 1.3, BRASS_DARK)
					2:
						draw_circle(pos, 3.5, BRASS_DARK)
						draw_circle(pos, 2.0, Color(0.05, 0.04, 0.03))
					_:
						draw_circle(pos, 3.5, Color(0.04, 0.04, 0.04))
			var hammer := Color(0.8, 0.8, 0.82) if w.cocked else Color(0.35, 0.35, 0.38)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-3, -21), c + Vector2(3, -21), c + Vector2(0, -17)]), hammer)
		"coach":
			for i in 2:
				var pos := c + Vector2(-8 + i * 16, 0)
				draw_circle(pos, 8, Color(0.22, 0.22, 0.24))
				match w.barrels[i]:
					1:
						draw_circle(pos, 6, BRASS)
						draw_circle(pos, 4.5, SHELL)
					2:
						draw_circle(pos, 6, BRASS_DARK)
						draw_circle(pos, 3, Color(0.05, 0.04, 0.03))
					_:
						draw_circle(pos, 6, Color(0.04, 0.04, 0.04))
		"rifle":
			var ch := Rect2(c.x - 14, c.y - 8, 5, 16)
			draw_rect(ch, BRASS if w.chambered else Color(0.1, 0.1, 0.1))
			draw_rect(Rect2(ch.position.x, ch.position.y - 2, 5, 3), Color(0.5, 0.45, 0.4) if w.chambered else Color(0.1, 0.1, 0.1))
			for i in Weapon.TUBE_CAP:
				var r := Rect2(c.x - 6 + i * 4, c.y - 6, 3, 12)
				draw_rect(r, BRASS if i < w.tube else Color(0.12, 0.1, 0.08))
	_text(Vector2(box.position.x + 70 if w.kind != "rifle" else box.position.x + 4, box.position.y + 47), "+%d" % w.reserve, 8, INK)
	var st := w.status()
	if st != "":
		_text(Vector2(box.position.x, box.position.y - 4), st, 8, Color(1, 0.8, 0.4), null, HORIZONTAL_ALIGNMENT_RIGHT, box.size.x)
	if w.kind == "colt" and w.fanning:
		_text(Vector2(box.position.x + 66, box.position.y + 34), "FANNING", 8, Color(1, 0.5, 0.3))


func _draw_crosshair(p: Player) -> void:
	if game.state != "play":
		return
	var m := get_local_mouse_position().round()
	var col := Color(1, 0.3, 0.2) if p.aim_target else Color(0.98, 0.94, 0.82)
	var r: float = clamp(p.spread_radius(), 3.0, 60.0)
	draw_arc(m, r, 0, TAU, 24, Color(col, 0.55), 1.0)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(m + d * 2, m + d * 5, col, 1.0)
	if p.weapon.is_reloading():
		_text(m + Vector2(-20, 16), "RELOADING", 8, Color(1, 0.8, 0.4))
	elif p.weapon.needs_reload():
		_text(m + Vector2(-14, 16), "EMPTY - R", 8, Color(1, 0.5, 0.3))


func _draw_eyes() -> void:
	var a: float = clamp(eyes_t * 6.0, 0.0, 1.0)
	var bar: float = 116.0 * a
	draw_rect(Rect2(0, 0, 640, bar), Color.BLACK)
	draw_rect(Rect2(0, 360 - bar, 640, bar), Color.BLACK)
	var slide := (1.0 - a) * 640.0
	draw_texture_rect(game.tex(game.meta["ui"]["eyes"]), Rect2(slide, 116, 640, 128), false, Color(1, 1, 1, a))


func _draw_message() -> void:
	var a: float = clamp(msg_t * 1.5, 0.0, 1.0)
	draw_rect(Rect2(0, 140, 640, 70), Color(0, 0, 0, 0.6 * a))
	_text(Vector2(0, 180), message, 26, Color(0.95, 0.75, 0.35, a), font, HORIZONTAL_ALIGNMENT_CENTER, 640)
	_text(Vector2(0, 200), sub, 8, Color(INK, a), null, HORIZONTAL_ALIGNMENT_CENTER, 640)


func _draw_title() -> void:
	var a := title_alpha
	draw_rect(Rect2(0, 0, 640, 360), Color(0.03, 0.02, 0.02, a))
	var t: Texture2D = game.tex(game.meta["ui"]["title"])
	var sz := t.get_size()
	sz *= game.tex_scale
	draw_texture_rect(t, Rect2(Vector2(round(320 - sz.x / 2), 110), sz), false, Color(1, 1, 1, a))
	var town: String = game.level.get("name", "")
	_text(Vector2(0, 100), "~ un western all'italiana ~", 10, Color(0.85, 0.7, 0.5, a), font, HORIZONTAL_ALIGNMENT_CENTER, 640)
	_text(Vector2(0, 196), "%s.  %d bandits.  One stranger." % [town, game.enemies.size()], 12, Color(INK, a), font, HORIZONTAL_ALIGNMENT_CENTER, 640)
	var lines := [
		"WASD move   MOUSE aim   LMB fire   C crouch   R reload   1 2 3 guns",
		"RMB: fan the Colt's hammer  /  fire both barrels of the coach gun",
		"Stay out of their sight. Crouch behind cover. Kill them all.",
	]
	for i in lines.size():
		_text(Vector2(0, 250 + i * 14), lines[i], 8, Color(0.8, 0.74, 0.62, a), null, HORIZONTAL_ALIGNMENT_CENTER, 640)
	_text(Vector2(0, 320), "click to ride in", 10, Color(0.95, 0.75, 0.35, a * (0.6 + 0.4 * sin(Time.get_ticks_msec() / 300.0))), font, HORIZONTAL_ALIGNMENT_CENTER, 640)
