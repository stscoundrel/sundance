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
var banner_text := ""
var banner_t := 0.0
var toast_text := ""
var toast_t := 0.0


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


## A warning under the bandit count for a few seconds (the saloon empties).
func banner(t: String) -> void:
	banner_text = t
	banner_t = 4.0


## A line above the gun panel for a moment ("picked up").
func toast(t: String) -> void:
	toast_text = t
	toast_t = 3.0


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
	toast_t = maxf(0.0, toast_t - real)
	banner_t = maxf(0.0, banner_t - real)
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
	if game.innocent_t > 0.0:
		_draw_innocent()
	if eyes_on:
		_draw_eyes()
	if message != "":
		_draw_message()
	if title_alpha > 0.0:
		_draw_title()
	if game.state == "loadout":
		_draw_loadout(p)
	elif game.state == "levels":
		_draw_levels()


## "!" / "?" markers, suspicion bars and shouted lines above the bandits' (and
## townsfolk's) heads, drawn here in screen space so the text stays crisp.
func _draw_enemy_marks() -> void:
	var to_local := get_global_transform_with_canvas().affine_inverse()
	var people: Array = []
	people.append_array(game.enemies)
	people.append_array(game.civilians)
	for e in people:
		var down: bool = e is Enemy and e.downed
		if not (e.alive or down) or (e is Civilian and e.gone()):
			continue
		var head: Vector2 = to_local * (e.get_global_transform_with_canvas() * Vector2(0, -16 if down else -40))
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
		if e is Civilian:
			if e.st == Civilian.St.SNITCH and e.told_t <= 0.0:
				_text(Vector2(head.x - 3, y - 6), "!", 14, Color(0.95, 0.95, 0.85), font)   # off to tell them
			continue
		if e == game.player.knife_cand:
			_draw_knife_mark(Vector2(head.x, y - 4), game.player.knife_silent)
			y -= 12
		if not e.revealed:
			continue   # passing as townsfolk: nothing gives him away
		if e.marker_t > 0.0 and e.marker != "":
			var c := Color(1, 0.85, 0.3) if e.marker == "?" else Color(1, 0.25, 0.15)
			_text(Vector2(head.x - 3, y - 6), e.marker, 14, c, font)
		elif e.suspicion > 0.02 and e.st != Enemy.St.COMBAT:
			draw_rect(Rect2(head.x - 8, y - 6, 16, 3), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(head.x - 8, y - 6, 16 * e.suspicion, 3), Color(1, 0.8, 0.3))


## Over the man the knife would go for: a pale blade for a quiet takedown, a red
## one for a rush (he'll shoot if he can).
func _draw_knife_mark(at: Vector2, quiet: bool) -> void:
	var c := Color(0.93, 0.9, 0.82) if quiet else Color(1, 0.3, 0.2)
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 160.0)
	c.a = pulse
	draw_colored_polygon(PackedVector2Array([at + Vector2(-5, 3), at + Vector2(5, -7), at + Vector2(6, -6), at + Vector2(-3, 4)]), c)
	draw_line(at + Vector2(-6, 1), at + Vector2(-2, 5), Color(0.45, 0.3, 0.18, pulse), 2.0)   # guard and grip


func _draw_status(p: Player) -> void:
	draw_rect(Rect2(6, 310, 44, 44), PANEL)
	draw_texture_rect(game.tex(game.meta["ui"]["portrait"]), Rect2(8, 312, 40, 40), false)
	draw_rect(Rect2(6, 310, 44, 44), Color(0.5, 0.36, 0.2), false, 1.0)
	for i in p.max_hp:
		var r := Rect2(54 + i * 7, 344, 5, 8)
		draw_rect(r, Color(0.1, 0.06, 0.05, 0.85))
		if i < p.hp:
			draw_rect(r.grow(-1), Color(0.75, 0.12, 0.08))
	# bandages: a white roll each, after the bars
	var bx := 54 + p.max_hp * 7 + 5
	for i in p.bandages:
		draw_rect(Rect2(bx + i * 9, 345, 7, 6), Color(0.92, 0.9, 0.84))
		draw_line(Vector2(bx + i * 9 + 2, 345), Vector2(bx + i * 9 + 2, 351), Color(0.7, 0.66, 0.6), 1.0)
	# and a red stick for each of dynamite he carries (G)
	var sx := bx + p.bandages * 9 + (4 if p.bandages > 0 else 0)
	for i in p.sticks:
		draw_rect(Rect2(sx + i * 6, 343, 4, 9), Color(0.7, 0.14, 0.1))
		draw_rect(Rect2(sx + i * 6, 346, 4, 1), Color(0.85, 0.78, 0.6))
		draw_line(Vector2(sx + i * 6 + 2, 343), Vector2(sx + i * 6 + 3, 341), Color(0.25, 0.2, 0.15), 1.0)
	if p.bandage_t >= 0.0:
		var f: float = p.bandage_t / (Player.STAND_BANDAGE_T if p.down else Player.BANDAGE_T)
		_text(Vector2(54, 338), "BANDAGING", 8, INK)
		draw_rect(Rect2(104, 332, 40, 5), Color(0.1, 0.06, 0.05, 0.85))
		draw_rect(Rect2(105, 333, 38 * f, 3), Color(0.92, 0.9, 0.84))
	elif p.medic and p.medic.alive and p.medic.st == Civilian.St.TREAT:   # the barber at work on him
		_text(Vector2(54, 338), "PATCHING UP", 8, INK)
		draw_rect(Rect2(114, 332, 40, 5), Color(0.1, 0.06, 0.05, 0.85))
		draw_rect(Rect2(115, 333, 38 * (1.0 - p.medic.work_t / Civilian.TREAT_T), 3), Color(0.92, 0.9, 0.84))
	elif p.down:   # the last stand: his blood running out, a bar draining
		var left: float = 1.0 - p.down_t / Player.STAND_BLEED
		var pulse := 0.7 + 0.3 * sin(Time.get_ticks_msec() / 140.0)
		_text(Vector2(54, 338), "BLEEDING OUT", 8, Color(1, 0.35, 0.25, pulse))
		draw_rect(Rect2(116, 332, 40, 5), Color(0.1, 0.06, 0.05, 0.85))
		draw_rect(Rect2(117, 333, 38 * left, 3), Color(0.75, 0.12, 0.08))
		# and a notch for each man dropped from the dirt: three and he's up
		for i in Player.STAND_RISE:
			var r := Rect2(162 + i * 8, 332, 5, 5)
			draw_rect(r, Color(0.1, 0.06, 0.05, 0.85))
			if i < p.dirt_drops:
				draw_rect(r.grow(-1), Color(0.92, 0.9, 0.84))
	elif p.crouched:
		_text(Vector2(54, 338), "CROUCHED", 8, INK)
	var n: int = game.alive_enemies()
	var label := "%s  %d" % [game.level.get("foe_count", "BANDITS"), n]   # (a map may name its own: FEDERALES)
	_text(Vector2(0, 16), label, 12, INK, font, HORIZONTAL_ALIGNMENT_CENTER, 640)
	if game.director:
		_draw_waves(game.director)
	if game.hanging:
		_draw_hanging(game.hanging, p)
	if game.captive:
		_draw_captive(game.captive, p)
	if game.cargo:
		_draw_cargo(game.cargo)
	if banner_t > 0.0:
		var a := clampf(banner_t, 0.0, 1.0)
		draw_rect(Rect2(150, 24, 340, 18), Color(0.3, 0.05, 0.03, 0.7 * a))
		_text(Vector2(0, 37), banner_text, 10, Color(1, 0.8, 0.45, a), font, HORIZONTAL_ALIGNMENT_CENTER, 640)


## The next wave's countdown under the bandit count, and, once word has come of
## them (and while they walk in), which way: a mark at the road, or at the edge of
## the screen pointing to it.
func _draw_waves(d: Director) -> void:
	var t := d.next_in()
	if t >= 0.0:
		var warn := not d.warned_from().is_empty()
		var c := Color(1, 0.8, 0.45) if warn else Color(INK, 0.8)
		_text(Vector2(0, 50 if banner_t > 0.0 else 30), "MORE COMING  %d:%02d" % [int(t) / 60, int(t) % 60], 8, c,
			null, HORIZONTAL_ALIGNMENT_CENTER, 640)
	var roads: Array = d.warned_from()
	for r in d.arriving_from():
		if not r in roads:
			roads.append(r)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 180.0)
	for r in roads:
		_pointer(r["at"], r["name"].to_upper(), Color(1, 0.55, 0.3, pulse), Color(1, 0.8, 0.45, pulse))


## An arrow at a place in the world (or, off screen, on the edge pointing out to
## it), named.
func _pointer(world_at: Vector2, name: String, col: Color, ink: Color, above := false) -> void:
	var to_local := get_global_transform_with_canvas().affine_inverse()
	var view := get_viewport().get_canvas_transform()
	var mid := Vector2(320, 180)
	var at: Vector2 = to_local * (view * world_at)
	var inset := Rect2(24, 66, 592, 236)   # (clear of the count, the banner and the countdown)
	var dir := (at - mid).normalized()
	var tip := at
	if not inset.has_point(at):   # off screen: on the edge, pointing out to it
		var k := INF
		for axis in 2:
			if absf(dir[axis]) > 0.001:
				var lim: float = (inset.end[axis] if dir[axis] > 0.0 else inset.position[axis]) - mid[axis]
				k = minf(k, lim / dir[axis])
		tip = mid + dir * k
	elif above:
		dir = Vector2.DOWN   # on screen: over it, pointing down
		tip = at + Vector2(0, -30)
	var side := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([tip + dir * 8.0, tip - dir * 4.0 + side * 6.0, tip - dir * 4.0 - side * 6.0]), col)
	_text(tip - dir * 14.0 + Vector2(-60, 3), name, 8, ink, null, HORIZONTAL_ALIGNMENT_CENTER, 120)


## The cargo's count under the bandit count; with it all in, the wagon marked.
func _draw_cargo(c: Cargo) -> void:
	var y := (64.0 if banner_t > 0.0 else 44.0) if game.director else (50.0 if banner_t > 0.0 else 30.0)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 180.0)
	if c.done:
		_text(Vector2(0, y), "ALL LOADED  -  GET TO THE WAGON", 8, Color(1, 0.8, 0.45, pulse), null, HORIZONTAL_ALIGNMENT_CENTER, 640)
		if game.state == "play":
			_pointer(c.wagon_at(), "THE WAGON", Color(1, 0.55, 0.3, pulse), Color(1, 0.8, 0.45, pulse), true)
		return
	_text(Vector2(0, y), "LOADED  %d / %d     CARRIERS  %d" % [c.loaded, c.goal, c.carriers_alive()], 8, Color(INK, 0.85),
		null, HORIZONTAL_ALIGNMENT_CENTER, 640)


func _draw_weapon(p: Player) -> void:
	# his guns by key: the one in hand outlined, ones he hasn't got dark
	for i in Player.ORDER.size():
		var k: String = Player.ORDER[i]
		var r := Rect2(592 + i * 14, 290, 11, 11)
		var have: bool = k in p.owned
		draw_rect(r, PANEL if have else Color(0.08, 0.05, 0.04, 0.35))
		draw_rect(r, BRASS if k == p.current else (Color(0.5, 0.36, 0.2) if have else Color(0.3, 0.24, 0.18, 0.5)), false, 1.0)
		_text(r.position + Vector2(3, 9), str(i + 1), 8, INK if have else Color(INK, 0.3))
	if toast_t > 0.0:
		_text(Vector2(0, 286), toast_text, 8, Color(0.95, 0.75, 0.35, clampf(toast_t, 0.0, 1.0)), null, HORIZONTAL_ALIGNMENT_RIGHT, 634)
	_draw_take(p)
	var w := p.weapon
	var box := Rect2(510, 304, 124, 50)
	draw_rect(box, PANEL)
	draw_rect(box, Color(0.5, 0.36, 0.2), false, 1.0)
	_text(Vector2(516, 316), w.d["name"], 8, INK)
	var c := Vector2(536, 336)
	match w.action:
		"revolver":
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
		"breech":
			var n := w.barrels.size()
			for i in n:
				var pos := c + Vector2(-8 * (n - 1) + i * 16, 0)
				draw_circle(pos, 8, Color(0.22, 0.22, 0.24))
				match w.barrels[i]:
					1:
						draw_circle(pos, 6, BRASS if not w.d.get("muzzle", false) else Color(0.62, 0.6, 0.58))
						draw_circle(pos, 4.5, SHELL if not w.d.get("muzzle", false) else Color(0.1, 0.09, 0.08))
					2:
						draw_circle(pos, 6, BRASS_DARK)
						draw_circle(pos, 3, Color(0.05, 0.04, 0.03))
					_:
						draw_circle(pos, 6, Color(0.04, 0.04, 0.04))
		"lever":
			var ch := Rect2(c.x - 14, c.y - 8, 5, 16)
			draw_rect(ch, BRASS if w.chambered else Color(0.1, 0.1, 0.1))
			draw_rect(Rect2(ch.position.x, ch.position.y - 2, 5, 3), Color(0.5, 0.45, 0.4) if w.chambered else Color(0.1, 0.1, 0.1))
			for i in w.cap():
				var r := Rect2(c.x - 6 + i * 4, c.y - 6, 3, 12)
				draw_rect(r, BRASS if i < w.tube else Color(0.12, 0.1, 0.08))
	_text(Vector2(box.position.x + 70 if w.action != "lever" else box.position.x + 4, box.position.y + 47), "+%d" % w.reserve, 8, INK)
	var st := w.status()
	if st != "":
		_text(Vector2(box.position.x, box.position.y - 4), st, 8, Color(1, 0.8, 0.4), null, HORIZONTAL_ALIGNMENT_RIGHT, box.size.x)
	if w.kind == "colt" and w.fanning:
		_text(Vector2(box.position.x + 66, box.position.y + 34), "FANNING", 8, Color(1, 0.5, 0.3))


## The hour of the hanging under the bandit count, red while the hangman's at the
## lever; then the man kicking on the rope. And, at the gallows, the knife's prompt.
func _draw_hanging(h: Hanging, p: Player) -> void:
	var y := 50.0 if banner_t > 0.0 else 30.0
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 120.0)
	match h.state:
		"waiting":
			var t := maxf(0.0, h.seconds_left())
			var c := Color(1, 0.8, 0.45) if t < 60.0 else Color(INK, 0.8)
			_text(Vector2(0, y), "HANGING AT NOON  %d:%02d" % [int(t) / 60, int(t) % 60], 8, c, null,
				HORIZONTAL_ALIGNMENT_CENTER, 640)
		"lever":
			_text(Vector2(0, y), "THE HANGMAN'S AT THE LEVER!", 8, Color(1, 0.35, 0.25, pulse), null,
				HORIZONTAL_ALIGNMENT_CENTER, 640)
		"hanging":
			_text(Vector2(0, y), "HE'S HANGING  -  SHOOT THE ROPE", 8, Color(1, 0.35, 0.25, pulse), null,
				HORIZONTAL_ALIGNMENT_CENTER, 640)
	_draw_cut(h, h.man, p)


## Whoever's counting over the man at the pole, under the wave countdown; and, at
## the pole, the knife's prompt.
func _draw_captive(c: Captive, p: Player) -> void:
	var t := c.seconds_left()
	if t >= 0.0:
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 120.0)
		var who := "THE GUARD" if c.state == "guard" else "EL GENERAL"
		_text(Vector2(0, 64 if banner_t > 0.0 else 44), "%s: ¡ALTO O LO MATO!  %d" % [who, ceili(t)], 8,
			Color(1, 0.35, 0.25, pulse), null, HORIZONTAL_ALIGNMENT_CENTER, 640)
	_draw_cut(c, c.man, p)


## The knife's prompt for a tied man: over his head, faint once the stranger's near
## enough to see it's meant for him, bright (and spelled out by the gun panel) once
## he's in reach of the ropes.
func _draw_cut(r: Node, man: Civilian, p: Player) -> void:
	if game.state != "play" or not man.alive or not man.bound:
		return
	var close: bool = r.can_cut(p.global_position)
	if not close and p.global_position.distance_to(man.global_position) > 140.0:
		return
	var to_local := get_global_transform_with_canvas().affine_inverse()
	var view := get_viewport().get_canvas_transform()
	var at: Vector2 = to_local * (view * (man.global_position + man.lift + Vector2(0, -36)))
	var a := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 150.0) if close else 0.4
	draw_rect(Rect2(at + Vector2(-6, -7), Vector2(12, 12)), Color(0.12, 0.07, 0.05, 0.75 * a))
	draw_rect(Rect2(at + Vector2(-6, -7), Vector2(12, 12)), Color(0.95, 0.75, 0.35, a), false, 1.0)
	_text(at + Vector2(-6, 3), "E", 8, Color(0.95, 0.75, 0.35, a), null, HORIZONTAL_ALIGNMENT_CENTER, 12)
	if close:
		_text(Vector2(0, 286), "[hold E]  cut him loose", 8, Color(0.95, 0.75, 0.35), null, HORIZONTAL_ALIGNMENT_RIGHT, 634)


## The gun at his feet he could swap for (F): its name and what's in it, there being
## no telling one from another in a heap of the dead.
func _draw_take(p: Player) -> void:
	var g: Dictionary = game.at_feet
	if g.is_empty() or game.state != "play" or toast_t > 0.0:
		return
	var slot: String = Player.SLOT[g["kind"]]
	var name: String = Weapon.DATA[g["kind"]]["name"]
	var w = g.get("weapon")
	var held := "%d loaded" % w.loaded() if w else "part fired"
	var line := "[F]  %s  (%s)" % [name, held]
	if slot in p.owned:
		line += "  for your %s" % p.weapons[slot].d["name"]
	_text(Vector2(0, 286), line, 8, Color(0.95, 0.75, 0.35), null, HORIZONTAL_ALIGNMENT_RIGHT, 634)


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


## The town's verdict when the hero shoots one of its own.
func _draw_innocent() -> void:
	var a: float = clamp(game.innocent_t, 0.0, 1.0)
	_text(Vector2(0, 52), "AN INNOCENT", 14, Color(0.9, 0.3, 0.22, a), font, HORIZONTAL_ALIGNMENT_CENTER, 640)
	_text(Vector2(0, 64), "the town will remember", 8, Color(INK, a * 0.9), null, HORIZONTAL_ALIGNMENT_CENTER, 640)


func _draw_message() -> void:
	var a: float = clamp(msg_t * 1.5, 0.0, 1.0)
	draw_rect(Rect2(0, 140, 640, 70), Color(0, 0, 0, 0.6 * a))
	_text(Vector2(0, 180), message, 26, Color(0.95, 0.75, 0.35, a), font, HORIZONTAL_ALIGNMENT_CENTER, 640)
	_text(Vector2(0, 200), sub, 8, Color(INK, a), null, HORIZONTAL_ALIGNMENT_CENTER, 640)


# ------------------------------------------------------------------ levels

const ROW := Rect2(150, 104, 340, 30)


func _row(i: int) -> Rect2:
	return Rect2(ROW.position + Vector2(0, i * (ROW.size.y + 6)), ROW.size)


## Which level row is under the cursor on the picker, or -1.
func level_hit(pos: Vector2) -> int:
	for i in game.levels.size():
		if _row(i).has_point(pos):
			return i
	return -1


func _draw_levels() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color(0.03, 0.02, 0.02, 0.86))
	_text(Vector2(0, 62), "WHERE TO, STRANGER?", 20, Color(0.95, 0.75, 0.35), font, HORIZONTAL_ALIGNMENT_CENTER, 640)
	_text(Vector2(0, 84), "Pick where to ride.", 8,
		Color(0.8, 0.74, 0.62), null, HORIZONTAL_ALIGNMENT_CENTER, 640)
	var mouse := get_local_mouse_position()
	var over := level_hit(mouse)
	for i in game.levels.size():
		var l: Dictionary = game.levels[i]
		var r := _row(i)
		var on: bool = i == game.level_pick or i == over
		draw_rect(r, Color(0.16, 0.1, 0.07, 0.95) if on else PANEL)
		draw_rect(r, BRASS if on else Color(0.3, 0.22, 0.15), false, 2.0 if i == game.level_pick else 1.0)
		_text(r.position + Vector2(10, 13), "[%d]  %s" % [i + 1, l["name"]], 12, Color(0.95, 0.75, 0.35) if on else INK, font)
		_text(r.position + Vector2(36, 25), l.get("note", ""), 8, Color(INK, 0.85 if on else 0.55))
	_text(Vector2(0, 340), "up / down and Enter, a number, or a click", 8, Color(INK, 0.5), null, HORIZONTAL_ALIGNMENT_CENTER, 640)
	draw_colored_polygon(PackedVector2Array([mouse, mouse + Vector2(0, 11), mouse + Vector2(3, 8), mouse + Vector2(7, 8)]), BRASS)


# ------------------------------------------------------------------ loadout

const CARD_W := 150.0
const CARD := Vector2(75, 104)
const CARD_H := 160.0
const RIDE := Rect2(250, 286, 140, 26)
const KIT_BOX := {"bandage": Rect2(75, 286, 150, 26), "dynamite": Rect2(415, 286, 150, 26)}
const KIT_NAME := {"bandage": "A BANDAGE  [B]", "dynamite": "A STICK OF DYNAMITE  [G]"}
const SLOT_NAME := {"colt": "SIDEARM", "coach": "SHOTGUN", "rifle": "RIFLE"}
const BLURB := {"colt": "six, quick to load, fanned", "schofield": "six, all out and in at once",
	"navy": "six, weak, slow to load",
	"pistola": "one ball, then the ramrod", "coach": "two barrels, or both at once",
	"sawnoff": "two short barrels, murder up close",
	"champion": "one barrel, reaches further",
	"escopeta": "one barrel, a long reload", "rifle": "thirteen, a quick lever",
	"spencer": "seven, lever and hammer", "springfield": "one hard shot, slow to load",
	"rollingblock": "one hard shot, short, quick to load", "remington": "one hard shot, far, quick to load"}
const OPTION_Y := 118.0   # the first of a card's guns to pick from, and 12 px apart


func _card(i: int) -> Rect2:
	return Rect2(CARD.x + i * (CARD_W + 20), CARD.y, CARD_W, CARD_H)


func _option(i: int, j: int) -> Rect2:
	var r := _card(i)
	return Rect2(r.position.x + 20, r.position.y + OPTION_Y + j * 12.0 - 9.0, CARD_W - 40, 12)


## What's under the cursor on the loadout screen: a gun's name, a slot's card
## ("slot:colt"), a piece of kit ("kit:bandage"), "ride", or nothing.
func loadout_hit(pos: Vector2) -> String:
	for i in Player.ORDER.size():
		var slot: String = Player.ORDER[i]
		var options := Player.choices(slot)
		for j in options.size():
			if _option(i, j).has_point(pos):
				return options[j]
		if _card(i).has_point(pos):
			return "slot:" + slot
	for k in game.kit_offered():
		if KIT_BOX[k].has_point(pos):
			return "kit:" + k
	return "ride" if RIDE.has_point(pos) else ""


func _draw_loadout(_p: Player) -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color(0.03, 0.02, 0.02, 0.86))
	_text(Vector2(0, 52), "CHOOSE YOUR IRONS", 20, Color(0.95, 0.75, 0.35), font, HORIZONTAL_ALIGNMENT_CENTER, 640)
	_text(Vector2(0, 72), "One gun a slot, or none, as far as your money goes. Any other you'll have to take off a dead man.", 8,
		Color(0.8, 0.74, 0.62), null, HORIZONTAL_ALIGNMENT_CENTER, 640)
	var left: int = game.budget() - game.spent()
	_text(Vector2(0, 93), "%d OF %d POINTS LEFT" % [left, game.budget()], 10,
		Color(0.95, 0.75, 0.35) if left > 0 else Color(INK, 0.6), font, HORIZONTAL_ALIGNMENT_CENTER, 640)
	var mouse := get_local_mouse_position()
	for i in Player.ORDER.size():
		var slot: String = Player.ORDER[i]
		var k: String = game.picked_for(slot)
		var on := k != ""
		var r := _card(i)
		draw_rect(r, Color(0.16, 0.1, 0.07, 0.95) if on else PANEL)
		draw_rect(r, BRASS if on else (Color(0.5, 0.36, 0.2) if r.has_point(mouse) else Color(0.3, 0.22, 0.15)), false, 2.0 if on else 1.0)
		_text(Vector2(r.position.x, r.position.y + 14), "%s  [%d]" % [SLOT_NAME[slot], i + 1], 10,
			Color(0.95, 0.75, 0.35) if on else Color(INK, 0.5), font, HORIZONTAL_ALIGNMENT_CENTER, CARD_W)
		if on:
			var t: Texture2D = game.tex(game.meta["ui"]["guns"][k])
			var sz := t.get_size()
			sz *= minf(2.0, 124.0 / sz.x)
			draw_texture_rect(t, Rect2(r.position + Vector2(CARD_W / 2 - sz.x / 2, 50 - sz.y / 2), sz), false)
			_text(Vector2(r.position.x, r.position.y + 88), Weapon.DATA[k]["name"], 8, INK, null, HORIZONTAL_ALIGNMENT_CENTER, CARD_W)
			_text(Vector2(r.position.x, r.position.y + 100), BLURB[k], 8, Color(0.8, 0.74, 0.62), null, HORIZONTAL_ALIGNMENT_CENTER, CARD_W)
		else:
			_text(Vector2(r.position.x, r.position.y + 88), "NONE", 8, Color(INK, 0.45), null, HORIZONTAL_ALIGNMENT_CENTER, CARD_W)
		var options := Player.choices(slot)
		for j in options.size():
			var o: String = options[j]
			var orr := _option(i, j)
			var col := Color(0.95, 0.75, 0.35) if o == k else (INK if orr.has_point(mouse) else Color(INK, 0.5))
			if o != k and not game.affords(slot, o):
				col = Color(INK, 0.18)   # too dear, with what else he's taken
			_text(Vector2(orr.position.x, orr.position.y + 9), ("> " if o == k else "") + Weapon.DATA[o]["name"], 8, col,
				null, HORIZONTAL_ALIGNMENT_CENTER, orr.size.x)
			_text(Vector2(orr.end.x, orr.position.y + 9), str(Player.cost([o])), 8, col, null, HORIZONTAL_ALIGNMENT_RIGHT, 16)
	for kk in game.kit_offered():
		var kr: Rect2 = KIT_BOX[kk]
		var has: bool = kk in game.kit
		var can: bool = has or left >= Player.KIT[kk]
		draw_rect(kr, Color(0.16, 0.1, 0.07, 0.95) if has else PANEL)
		draw_rect(kr, BRASS if has else (Color(0.5, 0.36, 0.2) if kr.has_point(mouse) and can else Color(0.3, 0.22, 0.15)), false, 2.0 if has else 1.0)
		var kc := Color(0.95, 0.75, 0.35) if has else (Color(INK, 0.6) if can else Color(INK, 0.18))
		_text(Vector2(kr.position.x + 8, kr.position.y + 17), ("> " if has else "") + KIT_NAME[kk], 8, kc, null, HORIZONTAL_ALIGNMENT_LEFT, kr.size.x - 30)
		_text(Vector2(kr.position.x, kr.position.y + 17), str(Player.KIT[kk]), 8, kc, null, HORIZONTAL_ALIGNMENT_RIGHT, kr.size.x - 8)
	var ready: bool = not game.picked.is_empty()
	draw_rect(RIDE, Color(0.22, 0.12, 0.08, 0.95) if ready else PANEL)
	draw_rect(RIDE, BRASS if ready and RIDE.has_point(mouse) else Color(0.5, 0.36, 0.2), false, 1.0)
	_text(Vector2(RIDE.position.x, RIDE.position.y + 18), "RIDE IN  [Enter]", 12,
		Color(0.95, 0.75, 0.35) if ready else Color(INK, 0.35), font, HORIZONTAL_ALIGNMENT_CENTER, RIDE.size.x)
	# the mouse is hidden in town; here it gets a small brass pointer
	draw_colored_polygon(PackedVector2Array([mouse, mouse + Vector2(0, 11), mouse + Vector2(3, 8), mouse + Vector2(7, 8)]), BRASS)


func _draw_title() -> void:
	var a := title_alpha
	draw_rect(Rect2(0, 0, 640, 360), Color(0.03, 0.02, 0.02, a))
	var t: Texture2D = game.tex(game.meta["ui"]["title"])
	var sz := t.get_size()
	sz *= game.tex_scale
	draw_texture_rect(t, Rect2(Vector2(round(320 - sz.x / 2), 110), sz), false, Color(1, 1, 1, a))
	var town: String = game.level.get("name", "")
	_text(Vector2(0, 100), "~ un western all'italiana ~", 10, Color(0.85, 0.7, 0.5, a), font, HORIZONTAL_ALIGNMENT_CENTER, 640)
	_text(Vector2(0, 196), "%s.  %d bandits.  One stranger." % [town, game.enemies.size() + (game.director.indoors() if game.director else 0)], 12, Color(INK, a), font, HORIZONTAL_ALIGNMENT_CENTER, 640)
	var lines := [
		"WASD move   MOUSE aim   LMB fire   C crouch   R reload   E knife (hold: drag a body)   B bandage   1 2 3 guns",
		"RMB: fan the Colt's hammer  /  fire both barrels of a double gun",
		"Stay out of their sight. Crouch behind cover. Kill them all.",
	]
	for i in lines.size():
		_text(Vector2(0, 250 + i * 14), lines[i], 8, Color(0.8, 0.74, 0.62, a), null, HORIZONTAL_ALIGNMENT_CENTER, 640)
	_text(Vector2(0, 320), "click to ride in", 10, Color(0.95, 0.75, 0.35, a * (0.6 + 0.4 * sin(Time.get_ticks_msec() / 300.0))), font, HORIZONTAL_ALIGNMENT_CENTER, 640)
