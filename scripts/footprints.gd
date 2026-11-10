class_name Footprints
extends Node2D
## Boot prints in the snow (Silencio's, with its weather: see Snowfall). Everyone
## leaves them: the stranger, both gangs. Not on the trodden streets, where one
## more set is nothing among the rest, and not on the ice. They fill in as the snow
## comes down, in half a minute of the steady snow, fading as they go. A squall
## blows them over fast, the oldest first (the steady snow's had longer at those).
##
## The stranger's are a trail the gang can follow, as they follow his blood: each
## of his prints goes into `game.trails` too (marked "print", the same dictionary,
## so it fills there as it fills here), and a print half filled in is no lead any
## more. Theirs are only to look at.

const STRIDE := 8.0       # px between one boot's print and the other's
const FILL_T := 30.0      # s for a print to fill in the steady snow (a lead for half of it: a man
                          # tracking him has to keep up, or lose him)
const STORM_FILL := 15.0  # s: the worst of a squall alone blows a fresh print over in this
                          # (10 s with the steady snow on top)...
const STORM_AGE := 30.0   # ...and every this many seconds older it is, it fills as fast again over
const LEAD := 0.5         # a print filled further than this is no lead to follow
const TICK := 0.2         # s between fillings (and redraws)
const MAX := 6000         # prints kept, the oldest filling first anyway
const INK := Color(0.3, 0.34, 0.44)

var game: Node
var prints: Array[Dictionary] = []   # {at, t, dir, side, depth, player, print}
var _last := {}                       # actor -> where his last print is, and which boot
var _tick := 0.0
var _streets: Array[Rect2] = []
var _ice: Array = []


func setup(g: Node) -> void:
	game = g
	z_index = -14   # (in the snow: under everyone, over the ground)
	for r in g.level.get("streets", []):
		_streets.append(Rect2(r[0], r[1], r[2] - r[0], r[3] - r[1]))
	_ice = g.level.get("ice", [])


## Does the snow take a print here? Not on a street, not on the ice.
func takes_print(at: Vector2) -> bool:
	var gp := Iso.to_grid(at)
	for r in _streets:
		if r.has_point(gp):
			return false
	for e in _ice:
		if Vector2((gp.x - e[0]) / e[2], (gp.y - e[1]) / e[3]).length() < 1.0:
			return false
	return true


func _physics_process(delta: float) -> void:
	_step(game.player)
	for e in game.enemies:
		_step(e)
	_tick -= delta
	if _tick > 0.0:
		return
	var dt := TICK - _tick
	var storm: float = game.snowfall.storm if game.snowfall else 0.0
	_tick = TICK
	for p in prints:
		var blow: float = storm / STORM_FILL * (1.0 + (game.clock - float(p["t"])) / STORM_AGE)
		p["depth"] -= dt * (1.0 / FILL_T + blow)
	if not prints.is_empty() and prints.any(func(p): return p["depth"] <= 0.0):
		prints = prints.filter(func(p): return p["depth"] > 0.0)   # (the oldest mostly, but a squall's fast on the old)
	queue_redraw()


## A man on his feet and moving leaves a print every stride.
func _step(a: Actor) -> void:
	if a == null or not a.alive or (a is Enemy and (a.downed or not a.revealed or a.indoors)) or (a is Player and a.down):
		return
	var at := a.global_position
	if not _last.has(a):
		_last[a] = [at, 1.0]
		return
	var last: Array = _last[a]
	if at.distance_to(last[0]) < STRIDE:
		return
	var side := -float(last[1])
	_last[a] = [at, side]
	if takes_print(at):
		add_print(at, (at - last[0]).normalized(), side, a is Player)


func add_print(at: Vector2, dir: Vector2, side: float, player: bool) -> Dictionary:
	var p := {"at": at, "t": game.clock, "dir": dir, "side": side, "depth": 1.0, "player": player, "print": true}
	prints.append(p)
	if prints.size() > MAX:
		prints.pop_front()
	if player:
		game.trails.append(p)
		if game.trails.size() > 400:
			game.trails.pop_front()
	return p


## Prints the stranger left near here, still deep enough to read.
func fresh_near(at: Vector2, r: float) -> int:
	var n := 0
	for p in prints:
		if p["player"] and p["depth"] > LEAD and p["at"].distance_to(at) < r:
			n += 1
	return n


func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	var view := Rect2(Vector2.ZERO, get_viewport_rect().size)
	if cam:
		var size := get_viewport_rect().size / cam.zoom
		view = Rect2(cam.get_screen_center_position() - size * 0.5, size).grow(8.0)
	for p in prints:
		var at: Vector2 = p["at"]
		if not view.has_point(at):
			continue
		var dir: Vector2 = p["dir"]
		var off := dir.orthogonal() * float(p["side"]) * 2.5
		var c := Color(INK.r, INK.g, INK.b, 0.8 * clampf(p["depth"], 0.0, 1.0))
		var heel := (at + off).floor()
		draw_rect(Rect2(heel + Vector2(-1, -1), Vector2(3, 2)), c)                # the heel and sole
		draw_rect(Rect2((heel + dir * 3.0).floor() + Vector2(-1, -1), Vector2(3, 2)), c)   # the toe
