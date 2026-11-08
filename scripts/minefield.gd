class_name Minefield
extends Node2D
## Paso Esperanza's mined ground (the map's "mines" and "plunger"): the revolution
## had time, and TNT, and dug charges in all round the breastwork a few paces out,
## where the army's thickest when it gets close, each a stick's worth, wired back
## to a blasting machine behind the bags. It's the last resort: the stranger works
## it with E, once, and every charge goes up down each run of wire one after the
## other, out from the gun's corner. They're dug in deep, so no stray round and no
## stick of the army's sets them off; none reaches the gun or the plunger, and the
## breastwork they were laid to spare. Whoever lives through it runs: the whole
## army, not only the men he can see, thinks the train's going up next, and falls
## back a few seconds before it comes on again (levas may keep running).

static var rng := RandomNumberGenerator.new()   # (the rout: its own dice)

const REACH := 22.0         # px from the plunger: near enough to work it
const PUSH := 0.3           # s from the handle going down to the first bang
const STEP := 0.16          # s from one charge to the next down a run
const ROUT_T := Vector2(4.5, 5.5)   # s they fall back for
const ROUT_RUN := 380.0     # px back the way they came, as far as they get
const ROUT_DESERTS := 0.3   # the levas who keep running
const ROUT_LINES := ["¡El tren! ¡Va a volar!", "¡Minas!", "¡Atrás, atrás!", "¡Retirada!", "¡Todo va a volar!"]

var game: Node
var at := Vector2.ZERO      # the plunger
var runs: Array = []        # each run of wire: its charges in order, {at, blown}
var fired := false
var pushed_at := 0.0        # game.clock when the handle went down
var by: Actor = null
var routed := false
var spr: Sprite2D
var ground: Node2D          # the mounds and the wire, under everyone


func setup(g: Node, level: Dictionary) -> void:
	game = g
	at = Iso.to_screen(Vector2(level["plunger"][0], level["plunger"][1]))
	position = at
	for run in level.get("mines", []):
		var charges := []
		for m in run:
			charges.append({"at": Iso.to_screen(Vector2(m[0], m[1])), "blown": false})
		runs.append(charges)
	spr = Sprite2D.new()
	spr.centered = false
	spr.scale = Vector2.ONE * g.tex_scale
	add_child(spr)
	_show(0)
	ground = Node2D.new()
	ground.z_as_relative = false
	ground.z_index = -9   # on the ground: over the view cones, under everyone
	ground.top_level = true
	ground.draw.connect(_draw_ground)
	add_child(ground)


func _show(i: int) -> void:
	var f: Dictionary = game.meta["plunger"][i]
	spr.texture = game.tex(f["file"])
	spr.offset = -Vector2(f["anchor"][0], f["anchor"][1])


## Close enough, and not yet pushed?
func can_push(p: Vector2) -> bool:
	return not fired and p.distance_to(at) < REACH


## The handle goes down: the first charge a moment later, then down each run.
func push(who: Actor) -> void:
	if fired:
		return
	fired = true
	by = who
	pushed_at = game.clock
	_show(1)
	game.sfx("cock", at, -2.0, 0.02, rng)
	game.stats["plunger"] = 1


func charges() -> int:
	var n := 0
	for run in runs:
		n += run.size()
	return n


func _physics_process(_delta: float) -> void:
	if not fired or routed:
		return
	var t: float = game.clock - pushed_at - PUSH
	var left := 0
	for run in runs:
		for i in run.size():
			var c: Dictionary = run[i]
			if c["blown"]:
				continue
			if t >= i * STEP:
				c["blown"] = true
				game.blast(c["at"], by, Dynamite.R, Dynamite.CORE, true)
				game.stats["mines blown"] = game.stats.get("mines blown", 0) + 1
			else:
				left += 1
	ground.queue_redraw()
	if left == 0:
		routed = true
		_rout()


## The last of them gone up: every man of the army still on the map falls back,
## a few of the nearest shouting it; the levas may not stop.
func _rout() -> void:
	var from := Iso.to_screen(Vector2(game.level["center"]["x"], game.level["center"]["y"]))
	var men: Array = []
	for e in game.enemies:
		if e.alive and e.visible and not e.deserting:
			men.append(e)
	men.sort_custom(func(a, b): return a.global_position.distance_to(at) < b.global_position.distance_to(at))
	var shouts := 0
	for e: Enemy in men:
		e.mine_rout(from, rng)
		if shouts < 3 and e.alive:
			e.say_line("mines", ROUT_LINES, rng)
			shouts += 1
	game.stats["routed"] = men.size()


## Each charge a patch of turned sand, and the wire run to it half buried: from the
## plunger to the first, and on from one to the next. A charge gone up takes its
## mound and its wire with it.
func _draw_ground() -> void:
	var wire := Color(0.18, 0.13, 0.09, 0.5)
	for run in runs:
		var from := at + Vector2(-3, 1)
		for c in run:
			if not c["blown"]:
				_dashes(from, c["at"], wire)
			from = c["at"]
	ground.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	for run in runs:
		for c in run:
			if c["blown"]:
				continue
			var p: Vector2 = c["at"] * Vector2(1.0, 2.0)
			ground.draw_circle(p, 8.0, Color(0.42, 0.32, 0.22, 0.28))
			ground.draw_circle(p + Vector2(-1, -1), 5.0, Color(0.7, 0.58, 0.42, 0.3))
	ground.draw_set_transform(Vector2.ZERO)


## A wire in the sand: showing a few px, then under it a while.
func _dashes(a: Vector2, b: Vector2, col: Color) -> void:
	var d := a.distance_to(b)
	var dir := (b - a) / maxf(d, 0.01)
	var s := 0.0
	while s < d:
		ground.draw_line(a + dir * s, a + dir * minf(s + 5.0, d), col, 1.0)
		s += 9.0
