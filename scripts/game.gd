extends Node2D
## Builds the town from data/town.json and assets/meta.json, owns the shared systems
## (physics queries, pathfinding, noise, bullets, effects, sound) and the match flow.

const LEVEL_PATH := "res://data/town.json"
const META_PATH := "res://assets/meta.json"
const ENEMIES_PATH := "res://data/enemies.json"
const POST_SHADER := preload("res://shaders/post.gdshader")
const LOUD := ["colt", "coach", "rifle", "bell"]
const WIND := Vector2(7, -2)   # px/s drift for smoke and dust
const VIEW_W := 1280.0 / 3.0   # world pixels across the screen: a close, detailed view

var meta: Dictionary
var enemy_data: Dictionary   # data/enemies.json: body templates, bandit types, palettes
var level: Dictionary
var size := 40

var world: Node2D
var decals: Decals
var cone_layer: Node2D
var statics: Node2D
var camera: Camera2D
var hud: Hud
var post: ColorRect

var player: Player
var enemies: Array[Enemy] = []
var buildings: Array[Dictionary] = []
var cover_points := PackedVector2Array()
var astar := AStarGrid2D.new()

var state := "title"   # title, play, won, lost
var shake := 0.0
var hurt_fx := 0.0
var alerted_once := false
var player_fired := false
var closeup_until := 0
var last_twang := -100000
var end_time := 0
var start_time := 0

var _textures := {}
var tex_scale := 0.5   # sprites carry 2x detail; world units stay 32x16 per tile
var _streams := {}
var _args := {}
var _shot_done := false
var _rattled := false
# What the gang knows about the stranger: when anyone last saw him or heard him
# fire, and where. Covering fire needs a fresh reason; stale knowledge only earns
# the odd harassing shot, and then silence.
const FRESH := 5.0       # seconds a sighting stays a reason to suppress
const HARASS_UNTIL := 12.0
const HARASS_EVERY := 3.0
var clock := 0.0         # game time in seconds (physics frames, so tests can run fast)
var seen_at := -100.0
var seen_pos := Vector2.ZERO
var harass_cd := 0.0
var stats := {}   # counts of AI events ("orders covering fire", "panic shot"...)


func _ready() -> void:
	if not Engine.has_meta("fixed_seed"):   # tests seed the RNG themselves
		randomize()
	_parse_args()
	_setup_input()
	meta = _load_json(META_PATH)
	level = _load_json(LEVEL_PATH)
	enemy_data = _load_json(ENEMIES_PATH)
	size = int(level["size"])
	tex_scale = float(meta.get("tex_scale", 1.0))
	_build_world()
	_spawn_actors()
	_build_overlay()
	start_time = Time.get_ticks_msec()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_setup_audio()
	var wind := AudioStreamPlayer.new()
	wind.stream = load(meta["sfx"]["wind"])
	wind.volume_db = -12.0
	add_child(wind)
	wind.finished.connect(wind.play)
	wind.play()
	sfx("bell", null, -4.0, 0.0)
	if _args.has("skip-title"):
		begin()
	elif _args.has("freeze"):
		hud.hide_title()   # debug: look around town with everyone standing still


## Glue and a brick-wall limiter on the master bus: gunfire can be mixed hot and
## stacked shots in a firefight stay punchy instead of clipping.
func _setup_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(bus) > 0:
		return
	var comp := AudioEffectCompressor.new()
	comp.threshold = -14.0
	comp.ratio = 3.0
	comp.attack_us = 2000.0
	comp.release_ms = 180.0
	comp.gain = 3.0
	AudioServer.add_bus_effect(bus, comp)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.3
	AudioServer.add_bus_effect(bus, lim)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var kv := s.split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


func tex(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path]


# ------------------------------------------------------------------ input

func _setup_input() -> void:
	var keys := {
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"crouch": [KEY_C, KEY_CTRL], "reload": [KEY_R],
		"weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3],
		"restart": [KEY_ENTER], "quit": [KEY_ESCAPE],
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var buttons := {"fire": MOUSE_BUTTON_LEFT, "alt": MOUSE_BUTTON_RIGHT}
	for action in buttons:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = buttons[action]
		InputMap.action_add_event(action, mb)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quit"):
		get_tree().quit()
	elif state == "title" and (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed():
		if Time.get_ticks_msec() - start_time > 600:
			begin()
			get_viewport().set_input_as_handled()
	elif (state == "won" or state == "lost") and event.is_action_pressed("restart"):
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
	elif event is InputEventMouseButton and event.pressed and player and state == "play":
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			player.cycle_weapon(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			player.cycle_weapon(-1)


func begin() -> void:
	if state != "title":
		return
	state = "play"
	hud.hide_title()


# ------------------------------------------------------------------ world

func _build_world() -> void:
	var ground := Sprite2D.new()
	ground.texture = tex(meta["ground"]["file"])
	ground.centered = false
	ground.position = Vector2(meta["ground"]["origin"][0], meta["ground"]["origin"][1])
	ground.scale = Vector2.ONE * tex_scale
	ground.z_index = -20
	add_child(ground)

	decals = Decals.new()
	decals.z_index = -15
	add_child(decals)
	cone_layer = Node2D.new()
	cone_layer.z_index = -10
	add_child(cone_layer)
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	statics = Node2D.new()
	add_child(statics)

	astar.region = Rect2i(0, 0, size * 2, size * 2)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()

	for o in level["objects"]:
		_place_object(o["type"], Vector2(o["x"], o["y"]))

	# map boundary
	var edge := StaticBody2D.new()
	edge.collision_layer = Iso.LAYER_WALL
	edge.collision_mask = 0
	var corners := Iso.rect_poly(0.2, 0.2, size - 0.2, size - 0.2)
	for i in 4:
		var cs := CollisionShape2D.new()
		var seg := SegmentShape2D.new()
		seg.a = corners[i]
		seg.b = corners[(i + 1) % 4]
		cs.shape = seg
		edge.add_child(cs)
	statics.add_child(edge)

	# keep only cover points that are reachable and off obstacles
	var good := PackedVector2Array()
	for p in cover_points:
		var c := _cell(p)
		if astar.is_in_boundsv(c) and not astar.is_point_solid(c):
			good.append(p)
	cover_points = good

	for i in 5:
		var tw := Tumbleweed.new()
		tw.setup(self, Iso.to_screen(Vector2(randf_range(0, size), randf_range(0, size))))
		world.add_child(tw)

	camera = Camera2D.new()
	camera.zoom = Vector2.ONE * (get_viewport_rect().size.x / VIEW_W)
	add_child(camera)
	camera.make_current()
	var origin := Vector2(meta["ground"]["origin"][0], meta["ground"]["origin"][1])
	var gsize: Vector2 = tex(meta["ground"]["file"]).get_size() * tex_scale
	camera.limit_left = int(origin.x)
	camera.limit_top = int(origin.y)
	camera.limit_right = int(origin.x + gsize.x)
	camera.limit_bottom = int(origin.y + gsize.y)


func _place_object(type: String, g: Vector2) -> void:
	var m: Dictionary = meta["objects"][type]
	var fp := Vector2(m["footprint"][0], m["footprint"][1])
	var spr := Sprite2D.new()
	spr.texture = tex(m["file"])
	spr.centered = false
	spr.position = Iso.to_screen(g + fp * 0.5)
	spr.scale = Vector2.ONE * tex_scale
	spr.offset = ((Iso.to_screen(g) - spr.position) / tex_scale - Vector2(m["anchor"][0], m["anchor"][1])).round()
	world.add_child(spr)

	var collide: String = m["collide"]
	if collide != "none":
		var body := StaticBody2D.new()
		body.collision_layer = {"wall": Iso.LAYER_WALL, "cover": Iso.LAYER_COVER, "post": Iso.LAYER_POST}[collide]
		body.collision_mask = 0
		for r in m["colliders"]:
			var x0: float = g.x + r[0]
			var y0: float = g.y + r[1]
			var x1: float = g.x + r[2]
			var y1: float = g.y + r[3]
			var poly := CollisionPolygon2D.new()
			poly.polygon = Iso.rect_poly(x0, y0, x1, y1)
			body.add_child(poly)
			_block_cells(x0, y0, x1, y1, 0.22)
			if collide != "post":
				_add_cover_points(x0, y0, x1, y1, collide == "wall")
		statics.add_child(body)
	if m["fade"]:
		buildings.append({"sprite": spr, "x0": g.x, "y0": g.y, "x1": g.x + fp.x, "y1": g.y + fp.y})


func _block_cells(x0: float, y0: float, x1: float, y1: float, pad: float) -> void:
	for i in range(int(floor((x0 - pad) * 2.0)), int(ceil((x1 + pad) * 2.0))):
		for j in range(int(floor((y0 - pad) * 2.0)), int(ceil((y1 + pad) * 2.0))):
			var c := Vector2i(i, j)
			if astar.is_in_boundsv(c):
				astar.set_point_solid(c, true)


func _add_cover_points(x0: float, y0: float, x1: float, y1: float, wall: bool) -> void:
	var o := 0.55
	var cx := (x0 + x1) * 0.5
	var cy := (y0 + y1) * 0.5
	var pts := [Vector2(cx, y0 - o), Vector2(cx, y1 + o), Vector2(x0 - o, cy), Vector2(x1 + o, cy)]
	if wall:
		pts += [Vector2(x0 - o, y0 - o), Vector2(x1 + o, y0 - o), Vector2(x0 - o, y1 + o), Vector2(x1 + o, y1 + o)]
	for p in pts:
		cover_points.append(Iso.to_screen(p))


func _spawn_actors() -> void:
	player = Player.new()
	world.add_child(player)
	var start := Vector2(level["player"]["x"], level["player"]["y"])
	if _args.has("at"):
		var xy: PackedStringArray = _args["at"].split(",")
		start = Vector2(float(xy[0]), float(xy[1]))
	player.setup(self, Iso.to_screen(start))
	for e in level["enemies"]:
		var en := Enemy.new()
		world.add_child(en)
		var patrol := PackedVector2Array()
		if e.has("patrol"):
			for p in e["patrol"]:
				patrol.append(Iso.to_screen(Vector2(p[0], p[1])))
		var facing_deg: float = e.get("facing", 90.0)
		var overrides := {}
		for key in e:
			if not key in ["kind", "x", "y", "patrol", "facing"]:
				overrides[key] = e[key]
		en.setup(self, e["kind"], Iso.to_screen(Vector2(e["x"], e["y"])), patrol, facing_deg, overrides)
		en.died.connect(_on_enemy_died)
		enemies.append(en)
	player.died.connect(_on_player_died)
	camera.position = player.global_position


func _build_overlay() -> void:
	var post_layer := CanvasLayer.new()
	post_layer.layer = 5
	add_child(post_layer)
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = POST_SHADER
	post.material = mat
	post_layer.add_child(post)

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	hud_layer.scale = Vector2.ONE * (get_viewport_rect().size.x / 640.0)
	add_child(hud_layer)
	hud = Hud.new()
	hud.game = self
	hud_layer.add_child(hud)


# ------------------------------------------------------------------ frame

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	if state == "title" and now - start_time > 5500 and not _args.has("freeze"):
		begin()
	if closeup_until > 0 and now > closeup_until:
		closeup_until = 0
		if state == "play":
			Engine.time_scale = 1.0
		hud.hide_eyes()

	if player:
		var look := (get_global_mouse_position() - player.global_position) * 0.35
		var target := player.global_position + look.limit_length(130.0) + Vector2(0, -12)
		camera.position = camera.position.lerp(target, clamp(delta * 4.0, 0.0, 1.0))
	shake = max(0.0, shake - delta * 18.0)
	camera.offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)).round()

	hurt_fx = max(0.0, hurt_fx - delta * 2.0)
	var mat := post.material as ShaderMaterial
	mat.set_shader_parameter("time_s", now / 1000.0)
	mat.set_shader_parameter("hurt", hurt_fx)
	if state == "lost":
		var t: float = clamp((now - end_time) / 1500.0, 0.0, 1.0)
		mat.set_shader_parameter("desat", t * 0.8)
		if now - end_time > 1500:
			Engine.time_scale = 1.0

	_update_fades(delta)
	_maybe_screenshot(now)


func _update_fades(delta: float) -> void:
	if not player:
		return
	var g := Iso.to_grid(player.global_position)
	for b in buildings:
		var spr: Sprite2D = b["sprite"]
		var behind: bool = g.x < b["x1"] and g.y < b["y1"] and not (g.x > b["x0"] and g.y > b["y0"])
		var target := 0.35 if behind and _covers(b, player.global_position) else 1.0
		spr.modulate.a = move_toward(spr.modulate.a, target, delta * 4.0)


## Does the building's actual artwork (not its shadow) cover the hero's body?
func _covers(b: Dictionary, feet: Vector2) -> bool:
	var spr: Sprite2D = b["sprite"]
	if not b.has("image"):
		b["image"] = spr.texture.get_image()
	var img: Image = b["image"]
	var origin := spr.position + spr.offset * tex_scale
	for dy in [-4.0, -14.0, -26.0]:
		var p: Vector2 = ((feet + Vector2(0, dy)) - origin) / tex_scale
		var ip := Vector2i(p)
		if ip.x >= 0 and ip.y >= 0 and ip.x < img.get_width() and ip.y < img.get_height():
			if img.get_pixelv(ip).a > 0.9:
				return true
	return false


func _maybe_screenshot(now: int) -> void:
	if _shot_done or not _args.has("shot"):
		return
	if _args.has("alert") and state == "play" and not alerted_once and now - start_time > 800:
		on_enemy_alert(enemies[0], true)
	if _args.has("rattle") and state == "play" and now - start_time > 600 and not _rattled:
		_rattled = true
		for e in enemies:
			e.near_miss(player.global_position)
	if now - start_time > float(_args.get("shot-time", "2.5")) * 1000.0:
		_shot_done = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_args["shot"])
		get_tree().quit()


# ------------------------------------------------------------------ queries

func ray(from: Vector2, to: Vector2, mask: int, exclude: Array[RID] = [], areas := false) -> Dictionary:
	var q := PhysicsRayQueryParameters2D.create(from, to, mask, exclude)
	q.collide_with_areas = areas
	q.collide_with_bodies = true
	return get_world_2d().direct_space_state.intersect_ray(q)


## True if `to` can be seen from `from`. Walls always block; low cover blocks only a
## crouched (or lying) target, and is ignored right next to the viewer.
func line_of_sight(from: Vector2, to: Vector2, target_low: bool) -> bool:
	var exclude: Array[RID] = []
	for i in 6:
		var hit := ray(from, to, Iso.LAYER_WALL | Iso.LAYER_COVER, exclude)
		if hit.is_empty():
			return true
		var col: CollisionObject2D = hit["collider"]
		if col.collision_layer & Iso.LAYER_WALL:
			return false
		var hp: Vector2 = hit["position"]
		if target_low and hp.distance_to(from) > 20.0:
			return false
		exclude.append(col.get_rid())
	return true


func clear_path(a: Vector2, b: Vector2) -> bool:
	var mask := Iso.LAYER_WALL | Iso.LAYER_COVER | Iso.LAYER_POST
	var side := (b - a).orthogonal().normalized() * 4.0
	return ray(a + side, b + side, mask).is_empty() and ray(a - side, b - side, mask).is_empty()


func _cell(p: Vector2) -> Vector2i:
	var g := Iso.to_grid(p) * 2.0
	return Vector2i(clampi(int(floor(g.x)), 0, size * 2 - 1), clampi(int(floor(g.y)), 0, size * 2 - 1))


func _cell_center(c: Vector2i) -> Vector2:
	return Iso.to_screen(Vector2(c.x + 0.5, c.y + 0.5) * 0.5)


func _nearest_free(c: Vector2i) -> Vector2i:
	if not astar.is_point_solid(c):
		return c
	for r in range(1, 8):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if astar.is_in_boundsv(n) and not astar.is_point_solid(n):
					return n
	return c


## A walkable route. `avoid` is a list of routes to steer clear of: cells along them
## (away from both ends) cost more, so the pathfinder prefers another way round.
func find_path(from: Vector2, to: Vector2, avoid: Array = [], penalty := 3.5) -> PackedVector2Array:
	var a := _nearest_free(_cell(from))
	var b := _nearest_free(_cell(to))
	var touched: Array[Vector2i] = []
	for route in avoid:
		_weigh_route(route, from, to, touched, penalty)
	var ids := astar.get_id_path(a, b)
	for c in touched:
		astar.set_point_weight_scale(c, 1.0)
	var pts := PackedVector2Array()
	for id in ids:
		pts.append(_cell_center(id))
	if pts.size() > 0 and b == _cell(to):
		pts[pts.size() - 1] = to
	# string-pull: skip points we can walk to directly
	var out := PackedVector2Array()
	var cur := from
	var i := 0
	while i < pts.size():
		var j := pts.size() - 1
		while j > i and not clear_path(cur, pts[j]):
			j -= 1
		out.append(pts[j])
		cur = pts[j]
		i = j + 1
	return out


func _weigh_route(route: PackedVector2Array, from: Vector2, to: Vector2, touched: Array[Vector2i], penalty: float) -> void:
	var prev := from
	for p in route:
		var steps := int(prev.distance_to(p) / 6.0) + 1
		for k in steps:
			var q := prev.lerp(p, float(k) / steps)
			if q.distance_to(from) < 40.0 or q.distance_to(to) < 50.0:
				continue
			var c := _cell(q)
			# a wide band, so a parallel lane down the same street still counts as taken
			for dx in range(-3, 4):
				for dy in range(-3, 4):
					var n := c + Vector2i(dx, dy)
					if astar.is_in_boundsv(n) and not astar.is_point_solid(n) and astar.get_point_weight_scale(n) < 2.0:
						astar.set_point_weight_scale(n, penalty)
						touched.append(n)
		prev = p


# Who is hunting the stranger, by which route: {target, path, hunter, role, at}.
var hunts: Array = []


## A bandit setting off after the stranger's last position. If comrades who set
## off from near him are already going in the way he would, he may (by his type's
## `flank` chance) go round to come in from another side, to a point just past the
## spot, cutting off the escape, rather than follow them in single file. Detours much
## longer than the straight route aren't worth it.
func plan_hunt(e: Enemy, target: Vector2) -> Dictionary:
	hunts = hunts.filter(func(h): return is_instance_valid(h["hunter"]) and h["hunter"].alive \
		and h["hunter"] != e and clock - float(h["at"]) < 12.0)
	var me := e.global_position
	var direct := find_path(me, target)
	var my_side := approach_dir(direct, target)
	var ahead := hunts.filter(func(h): return h["target"].distance_to(target) < 100.0 \
		and h["from"].distance_to(me) < 220.0 \
		and abs(my_side.angle_to(approach_dir(h["path"], target))) < deg_to_rad(50.0))
	var route := direct
	var role := "direct"
	var goal := target
	if not ahead.is_empty() and randf() < float(e.tdata.get("flank", 0.6)):
		goal = target - my_side.rotated(randf_range(-0.5, 0.5)) * 65.0   # the far side
		var g := Iso.to_grid(goal)
		if g.x < 1.0 or g.y < 1.0 or g.x > size - 1.0 or g.y > size - 1.0 or not is_free(goal):
			goal = free_point_near(goal, 30.0)
		var avoid: Array = [direct]
		for h in ahead:
			avoid.append(h["path"])
		# a gentle nudge first, then harder; only a way in from another side counts
		for penalty in [3.5, 9.0]:
			var round_ := find_path(me, goal, avoid, penalty)
			if abs(approach_dir(round_, target).angle_to(my_side)) > deg_to_rad(50.0) \
					and _length(me, round_) < _length(me, direct) * 1.8 + 60.0:
				route = round_
				role = "flank"
				break
		if role != "flank":
			goal = target
	hunts.append({"target": target, "from": me, "path": route, "hunter": e, "role": role, "at": clock})
	return {"path": route, "role": role, "goal": goal}


## The direction a route closes in on its target from.
func approach_dir(route: PackedVector2Array, target: Vector2) -> Vector2:
	for k in range(route.size() - 1, -1, -1):
		if route[k].distance_to(target) > 55.0:
			return (route[k] - target).normalized()
	return Vector2.ZERO


func _length(from: Vector2, route: PackedVector2Array) -> float:
	var total := 0.0
	var prev := from
	for p in route:
		total += prev.distance_to(p)
		prev = p
	return total


func free_point_near(p: Vector2, radius: float) -> Vector2:
	for i in 12:
		var q := p + Vector2.from_angle(randf() * TAU) * randf_range(radius * 0.3, radius)
		var c := _cell(q)
		if not astar.is_point_solid(c):
			return q
	return p


func find_cover(from: Vector2, threat: Vector2) -> Vector2:
	var best := Vector2.INF
	var bd := 1e9
	for c in cover_points:
		var d := from.distance_to(c)
		if d > 170.0 or d >= bd or c.distance_to(threat) < 70.0:
			continue
		if line_of_sight(threat, c, true):
			continue
		bd = d
		best = c
	return best


func enemy_under(screen_point: Vector2) -> Enemy:
	var best: Enemy = null
	var bd := 1e9
	for e in enemies:
		if not e.alive:
			continue
		var r := Rect2(e.global_position + Vector2(-8, -36), Vector2(16, 38))
		if r.has_point(screen_point):
			var d := e.global_position.distance_to(screen_point)
			if d < bd:
				bd = d
				best = e
	return best


# ------------------------------------------------------------------ events

const FLANKS := [0.0, 0.7, -0.7, 1.2, -1.2, 0.35, -0.35, 0.95, -0.95]
var _flank_i := 0


## Flank angles handed out in turn, so bandits joining a fight fan out to the sides.
func next_flank() -> float:
	_flank_i += 1
	return FLANKS[(_flank_i - 1) % FLANKS.size()]


func ally_in_line(shooter: Enemy, a: Vector2, b: Vector2) -> bool:
	return blocking_ally(shooter, a, b) != null


## The comrade standing in the line of fire from a to b, if any.
func blocking_ally(shooter: Enemy, a: Vector2, b: Vector2) -> Enemy:
	for e in enemies:
		if e == shooter or not e.alive:
			continue
		var p := Geometry2D.get_closest_point_to_segment(e.global_position, a, b)
		if p.distance_to(e.global_position) < 12.0 and p.distance_to(b) > 8.0:
			return e
	return null


## A reachable spot about `dist` away from the threat, for a bandit running off.
func point_away(from: Vector2, threat: Vector2, dist: float) -> Vector2:
	var away := (from - threat).normalized()
	if away == Vector2.ZERO:
		away = Vector2.from_angle(randf() * TAU)
	for a in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5]:
		var p := from + away.rotated(a + randf_range(-0.2, 0.2)) * dist
		var g := Iso.to_grid(p)
		if g.x > 1.0 and g.y > 1.0 and g.x < size - 1.0 and g.y < size - 1.0 and is_free(p):
			return p
	return free_point_near(from, dist * 0.5)


## A cover point near `near` that hides a crouching man from `threat` but lets
## him shoot standing up: the place to duck behind and pop up from.
func find_fighting_cover(me: Vector2, threat: Vector2, near: Vector2, keep: Vector2, taken: Array) -> Vector2:
	var best := Vector2.INF
	var bd := 1e9
	for c in cover_points:
		var dt := c.distance_to(threat)
		if dt < keep.x * 0.8 or dt > keep.y * 1.2:
			continue
		var score := c.distance_to(near) + c.distance_to(me) * 0.5
		if score > 220.0 or score >= bd:
			continue
		var clash := false
		for o in taken:
			if o.distance_to(c) < 24.0:
				clash = true
				break
		if clash:
			continue
		if line_of_sight(threat, c, true) or not line_of_sight(c, threat, false):
			continue
		bd = score
		best = c
	return best


func taken_positions(except: Enemy) -> Array:
	var out := []
	for e in enemies:
		if e != except and e.alive and e.fight_pos != Vector2.INF:
			out.append(e.fight_pos)
	return out


func report_sighting(pos: Vector2) -> void:
	seen_at = clock
	seen_pos = pos


## Seconds since anyone in the gang saw or heard the stranger.
func staleness() -> float:
	return clock - seen_at


func _physics_process(delta: float) -> void:
	if state != "play":
		return
	clock += delta
	# Knowledge gone stale: the shooting dies down to the odd harassing shot at his
	# last known position from one bandit at a time, then stops altogether.
	var stale := staleness()
	if stale < FRESH or stale > HARASS_UNTIL:
		return
	harass_cd -= delta
	if harass_cd > 0.0:
		return
	harass_cd = HARASS_EVERY * randf_range(0.8, 1.3)
	var shooters: Array[Enemy] = []
	for e in enemies:
		if e.alive and e.st == Enemy.St.COMBAT and e.reaction == "" and not e.weapon.is_reloading() \
				and e.global_position.distance_to(seen_pos) < e.weapon.d["range"] * 0.8 \
				and not ally_in_line(e, e.global_position, seen_pos):
			shooters.append(e)
	if not shooters.is_empty():
		shooters.pick_random().harass(seen_pos)


func is_free(p: Vector2) -> bool:
	return not astar.is_point_solid(_cell(p))


## A bandit type: the defaults, then the type, then any per-placement overrides.
func enemy_type(kind: String, overrides := {}) -> Dictionary:
	var t: Dictionary = enemy_data["defaults"].duplicate(true)
	t.merge(enemy_data["types"][kind], true)
	t.merge(overrides, true)
	return t


func make_noise(pos: Vector2, radius: float, kind: String, source: Node) -> void:
	if kind == "shot":
		player_fired = true
		report_sighting(pos)   # his muzzle flash and the crack give him away
	for e in enemies:
		if e.alive:
			e.hear(pos, radius, kind, source)


func alert_allies(caller: Enemy, radius: float, target: Vector2) -> void:
	for e in enemies:
		if e != caller and e.alive and e.global_position.distance_to(caller.global_position) < radius:
			e.alert_to(target)


## The close-up is the stand-off moment: a bandit lays eyes on the stranger before a
## single shot has been fired. Alerts caused by the hero's own gunfire skip it.
func on_enemy_alert(_e: Enemy, spotted: bool) -> void:
	var now := Time.get_ticks_msec()
	if not alerted_once and spotted and not player_fired:
		alerted_once = true
		Engine.time_scale = 0.3
		closeup_until = now + 1700
		hud.show_eyes()
		sfx("sting", null, -2.0, 0.0)
		last_twang = now
	elif now - last_twang > 7000:
		last_twang = now
		sfx("twang", null, -6.0, 0.0)


func _on_enemy_died(e: Actor) -> void:
	for o in enemies:
		if o.alive and o.global_position.distance_to(e.global_position) < 180.0:
			o.witness_death(e.global_position, player.global_position)
	if _args.has("bot"):
		print("%.1fs  %s down, %d left" % [(Time.get_ticks_msec() - start_time) / 1000.0, e.kind, alive_enemies()])
	if player.weapons.has(e.weapon.kind):   # nothing to take from a derringer
		var p := Pickup.new()
		p.setup(self, e.global_position + Vector2(randf_range(-6, 6), 4), e.weapon.kind)
		world.add_child.call_deferred(p)
	if alive_enemies() == 0 and state == "play":
		state = "won"
		end_time = Time.get_ticks_msec()
		hud.show_message("THE TOWN IS QUIET", "press Enter to ride again")
		sfx("win", null, -2.0, 0.0)


func _on_player_died(_p: Actor) -> void:
	if state != "play":
		return
	state = "lost"
	end_time = Time.get_ticks_msec()
	Engine.time_scale = 0.35
	hud.show_message("ADIOS, AMIGO", "press Enter to ride again")
	sfx("lose", null, -2.0, 0.0)


func on_player_hurt() -> void:
	if _args.has("bot"):
		print("%.1fs  hero hit, hp %d" % [(Time.get_ticks_msec() - start_time) / 1000.0, player.hp])
	hurt_fx = 1.0
	add_shake(4.0)


func alive_enemies() -> int:
	var n := 0
	for e in enemies:
		if e.alive:
			n += 1
	return n


# ------------------------------------------------------------------ effects

func add_shake(amount: float) -> void:
	shake = max(shake, amount)


func spawn_bullet(origin: Vector2, vel: Vector2, range_px: float, damage: int, shooter: Actor, height: float, pellet: bool) -> void:
	var b := Bullet.new()
	b.setup(self, origin, vel, range_px, damage, shooter, height, pellet)
	world.add_child(b)


func muzzle_flash(holder: Actor, dir: Vector2) -> void:
	var m: Dictionary = meta["muzzle"]
	var s := Sprite2D.new()
	s.texture = tex(m["file"])
	s.hframes = int(m["frames"])
	s.frame = randi() % 2
	s.centered = true
	s.position = holder.global_position + Vector2(0, 1)
	s.scale = Vector2.ONE * tex_scale
	var tip: Vector2 = holder.muzzle_offset() + dir * 2.0
	s.offset = (tip / tex_scale).round()
	world.add_child(s)
	get_tree().create_timer(0.05, false).timeout.connect(s.queue_free)
	# Black powder: every shot leaves a cloud that hangs and drifts off on the wind.
	var puff := Puff.new()
	puff.position = holder.global_position + Vector2(0, 2)
	var base := tip + Vector2(0, -1)
	var n: int = holder.weapon.d.get("smoke", 9)
	var push: float = holder.weapon.d.get("smoke_push", 1.0)
	for i in n:
		var shade := randf_range(0.78, 0.95)
		puff.smoke(base + dir * randf_range(0, 8), dir.rotated(randf_range(-0.5, 0.5)) * randf_range(10, 50) * push + Vector2(0, -randf_range(2, 10)),
			randf_range(2.5, 4.5), randf_range(1.5, 3.0), Color(shade, shade * 0.97, shade * 0.93, 0.42), randf_range(2.5, 4.5),
			WIND + Vector2(randf_range(-3, 3), randf_range(-3, 0)))
	world.add_child(puff)


## A dead man's gun falls from his hand and lands in the dirt beside him.
func drop_gun(a: Actor) -> void:
	var kind: String = a.weapon.kind
	var g: Dictionary = meta["guns"][kind].pick_random()
	var s := Sprite2D.new()
	s.texture = tex(g["file"])
	s.centered = false
	s.scale = Vector2.ONE * tex_scale
	s.offset = -Vector2(g["anchor"][0], g["anchor"][1])
	var side := a.facing.orthogonal() * randf_range(-10.0, 10.0) - a.facing * randf_range(2.0, 8.0)
	s.position = a.global_position + side + Vector2(0, 2)
	world.add_child(s)
	var drop := -a.gun_height()
	var spr_offset := s.offset
	s.offset = spr_offset + Vector2(0, drop / tex_scale)
	var tw := create_tween()
	tw.tween_property(s, "offset", spr_offset, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


## Animation events: brass flicking out of a Winchester or Colt, shells out of the
## coach gun.
func anim_event(a: Actor, ev: String) -> void:
	if ev == "brass" and a.weapon and a.weapon.kind == "rifle" and not a.weapon.ejecting:
		return   # working the lever on an empty chamber: nothing to throw out
	var puff := Puff.new()
	puff.position = a.global_position + Vector2(0, 2)
	var at: Vector2 = a.muzzle_offset() - a.facing * 6.0
	var side := a.facing.orthogonal()
	var n := 2 if ev == "shells" else 1
	for i in n:
		var c := Color(0.72, 0.16, 0.12) if ev == "shells" else Color(0.9, 0.72, 0.3)
		puff.add(at, side * randf_range(15, 35) * (1 if randf() < 0.5 else -1) + Vector2(0, -randf_range(25, 45)),
			randf_range(1.5, 2.5), 1.0, c, 0.0, 200.0)
	world.add_child(puff)


func impact(pos: Vector2, height: float, vel: Vector2, wall: bool) -> void:
	var puff := Puff.new()
	var back := -vel.normalized()
	if wall:
		# Splinters and plaster fly off, a dust cloud hangs, and a hole stays in the wall.
		puff.position = pos + Vector2(0, 6)
		var at := Vector2(0, -height * 0.7 - 6)
		for i in 7:
			puff.add(at, back.rotated(randf_range(-0.9, 0.9)) * randf_range(30, 80) + Vector2(0, -randf_range(10, 40)),
				randf_range(0.5, 0.9), randf_range(0.8, 1.2), Color(0.86, 0.74, 0.56), 0.0, 220.0)
		for i in 5:
			puff.smoke(at, back.rotated(randf_range(-0.6, 0.6)) * randf_range(8, 25), randf_range(1.0, 1.8),
				randf_range(1.5, 2.5), Color(0.84, 0.72, 0.56, 0.5), 5.0, WIND * 0.5)
		puff.add(at, back * 20.0, 0.07, 1.6, Color(1, 0.92, 0.6, 1))
		puff.mark(at, 25.0, 1.4, Color(0.13, 0.09, 0.07, 0.95))
		if randf() < 0.3:
			sfx("ricochet", pos, -8.0, 0.15)
	else:
		# Dirt kicked up where the round strikes the street.
		puff.position = pos
		for i in 9:
			puff.add(Vector2.ZERO, Vector2(randf_range(-18, 18), -randf_range(40, 95)), randf_range(0.5, 0.9),
				randf_range(0.8, 1.3), Color(0.42, 0.31, 0.21), 0.0, 230.0)
		for i in 5:
			puff.smoke(Vector2(randf_range(-2, 2), -randf_range(0, 3)), Vector2(randf_range(-10, 10), -randf_range(6, 18)),
				randf_range(1.0, 2.0), randf_range(1.5, 2.5), Color(0.8, 0.66, 0.48, 0.5), 5.0, WIND * 0.5)
		decals.add(pos, 1.3, Color(0.27, 0.19, 0.13, 0.7))
	world.add_child(puff)


func blood(pos: Vector2, dir: Vector2, height: float) -> void:
	var puff := Puff.new()
	puff.position = pos + Vector2(0, 1)
	for i in 8:
		puff.add(Vector2(0, -height * 0.8), dir.rotated(randf_range(-0.6, 0.6)) * randf_range(20, 60) + Vector2(0, -randf_range(0, 20)),
			randf_range(0.25, 0.5), randf_range(0.8, 1.6), Color(0.55, 0.06, 0.04, 1.0), 0.0, 120.0)
	world.add_child(puff)
	for i in 3:
		decals.add(pos + dir * randf_range(4, 18) + Vector2(randf_range(-4, 4), randf_range(-2, 2)), randf_range(1.0, 2.5), Color(0.38, 0.05, 0.04, 0.85))


func sfx(name: String, pos: Variant = null, vol := 0.0, pitch_var := 0.06) -> void:
	if not _streams.has(name):
		var takes: Array[AudioStream] = [load(meta["sfx"][name])]
		for i in range(2, 6):
			var k := "%s_%d" % [name, i]
			if meta["sfx"].has(k):
				takes.append(load(meta["sfx"][k]))
		_streams[name] = takes
	var stream: AudioStream = _streams[name].pick_random()
	var p: Node
	if pos == null:
		var ap := AudioStreamPlayer.new()
		ap.stream = stream
		ap.volume_db = vol
		ap.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
		p = ap
	else:
		var ap2 := AudioStreamPlayer2D.new()
		ap2.stream = stream
		ap2.volume_db = vol
		ap2.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
		ap2.position = pos
		if name in LOUD:
			# gunfire carries right across town
			ap2.max_distance = 4000.0
			ap2.attenuation = 0.5
		else:
			ap2.max_distance = 1200.0
			ap2.attenuation = 1.2
		p = ap2
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
