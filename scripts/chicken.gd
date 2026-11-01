class_name Chicken
extends Node2D
## A hen, for Corbucci: pecks about her yard, and at gunfire (or anyone stomping
## up) bolts in a flapping zigzag, squawking, straight through whatever's going
## on; then settles and pecks wherever she ends up. Nothing can hit her: she isn't
## a target, only a nuisance. A hen woman shoos strays back home to a coop.

enum S { PECK, WALK, BOLT, HERD }

const WALK := 9.0
const BOLT := 72.0
const HERDED := 22.0        # px/s, shooed along
const SPOOK := 26.0         # px: anyone this close sends her off
const LOOK_EVERY := 0.35
const FRAMES := {"stand": 0, "walk": [1, 2], "peck": 3, "flap": [4, 5]}

static var rng := RandomNumberGenerator.new()   # her own dice, so the town's stay as seeded

var game: Node
var sprite: Sprite2D
var color := 0
var st := S.PECK
var facing := Vector2.RIGHT
var vel := Vector2.ZERO
var home := Vector2.ZERO
var threat := Vector2.ZERO
var t := 0.0
var wait := 0.0
var look_t := 0.0
var zig := 0.0
var pecking := false
var hard := false            # bolting from gunfire (not just from someone's boots)
var herder: Node = null      # the hen woman seeing her home
var coop: Dictionary = {}
var route := PackedVector2Array()   # round the houses to it
var route_i := 0
var reroute := 0.0


func setup(g: Node, pos: Vector2) -> void:
	game = g
	position = pos
	home = pos
	var m: Dictionary = g.meta["hens"]
	color = rng.randi() % int(m["colors"])
	sprite = Sprite2D.new()
	sprite.texture = g.tex(m["file"])
	sprite.hframes = int(m["frames"])
	sprite.vframes = int(m["colors"]) * 8
	sprite.scale = Vector2.ONE * g.tex_scale
	sprite.centered = false
	sprite.offset = -Vector2(m["anchor"][0], m["anchor"][1])
	add_child(sprite)
	facing = Vector2.from_angle(rng.randf() * TAU)
	wait = rng.randf_range(0.5, 4.0)
	t = rng.randf() * 10.0
	look_t = rng.randf() * LOOK_EVERY


## Gunfire, a blast, a stranger's boots: off she goes, away from it.
## Shooed along ahead of the broom, home to that coop.
func herd(to: Dictionary) -> void:
	coop = to
	st = S.HERD
	wait = 30.0
	reroute = 0.0


## Where she's headed next, being shooed home: the next turn of the way, or the coop.
func heading() -> Vector2:
	if st == S.HERD and route_i < route.size():
		return route[route_i]
	return coop["at"] if not coop.is_empty() else position


func scare(from: Vector2, hard := true) -> void:
	if st == S.HERD and not hard:
		return   # the woman behind her with the broom: she knows where she's going
	threat = from
	if st != S.BOLT and hard and rng.randf() < 0.35:
		game.sfx("squawk", position, -10.0, 0.15)
	if st != S.BOLT and hard and rng.randf() < 0.5:
		game.feathers(position, 3)
	st = S.BOLT
	self.hard = hard
	wait = rng.randf_range(2.0, 3.5) if hard else rng.randf_range(0.6, 1.0)
	var away := (position - from).normalized()
	facing = (away if away != Vector2.ZERO else Vector2.from_angle(rng.randf() * TAU)).rotated(rng.randf_range(-0.6, 0.6))
	zig = rng.randf() * TAU


func _physics_process(delta: float) -> void:
	if game.state == "title" or game.state == "loadout":
		return
	t += delta
	wait -= delta
	match st:
		S.PECK:
			vel = Vector2.ZERO
			if int(t * 1.6) != int((t - delta) * 1.6):
				pecking = rng.randf() < 0.55
			if wait <= 0.0:
				st = S.WALK
				wait = rng.randf_range(0.6, 1.6)
				var to_home := home - position
				facing = (to_home.normalized() if to_home.length() > 40.0 else Vector2.from_angle(rng.randf() * TAU))
			elif rng.randf() < delta * 0.05:
				game.sfx("cluck", position, -16.0, 0.15)
		S.WALK:
			vel = facing * WALK
			if wait <= 0.0:
				st = S.PECK
				wait = rng.randf_range(1.5, 5.0)
		S.HERD:
			reroute -= delta
			if reroute <= 0.0:
				reroute = 2.0
				route = game.find_path(position, coop["at"])
				route_i = 0
			while route_i < route.size() and position.distance_to(route[route_i]) < 5.0:
				route_i += 1
			facing = (heading() - position).normalized()
			vel = facing.rotated(sin(t * 5.0) * 0.3) * HERDED
			if position.distance_to(coop["at"]) < 18.0 or wait <= 0.0:
				st = S.PECK
				wait = rng.randf_range(1.0, 3.0)
				game.hen_home(self, coop)
				return
		S.BOLT:
			# a panicked zigzag, wings going
			zig += delta * 9.0
			var dir := facing.rotated(sin(zig) * 0.7)
			vel = dir * BOLT * clampf(wait, 0.4, 1.0)
			if wait <= 0.0:
				st = S.PECK
				if hard:
					home = position   # run clean off: this is her yard now
				wait = rng.randf_range(1.0, 3.0)
	_spook()
	_move(delta)
	_animate()


func _spook() -> void:
	look_t -= get_physics_process_delta_time()
	if look_t > 0.0 or st == S.BOLT or st == S.HERD:
		return
	look_t = LOOK_EVERY
	var who: Array = [game.player]
	who.append_array(game.enemies)
	who.append_array(game.civilians)
	for a in who:
		if a is Civilian and a.henwife:
			continue   # she's used to her
		if a.alive and a.visible and a.velocity.length() > 5.0 and a.global_position.distance_to(position) < SPOOK:
			scare(a.global_position, false)
			return


func _move(delta: float) -> void:
	if vel == Vector2.ZERO:
		return
	var next := position + vel * delta
	if _clear(next):
		position = next
		return
	# a wall in the way: veer off and try another way
	for a in [0.9, -0.9, 1.8, -1.8, PI]:
		var d: Vector2 = vel.rotated(a)
		if _clear(position + d * delta):
			facing = d.normalized()
			position += d * delta
			return


## Nothing solid between here and there (she's small: she can hug a wall where a
## man can't), and still in town.
func _clear(p: Vector2) -> bool:
	return _in_town(p) and game.ray(position, p, Iso.LAYER_WALL | Iso.LAYER_COVER | Iso.LAYER_POST).is_empty()


func _in_town(p: Vector2) -> bool:
	var g := Iso.to_grid(p)
	return g.x > 0.5 and g.y > 0.5 and g.x < game.size - 0.5 and g.y < game.size - 0.5


func _animate() -> void:
	var d := facing if vel == Vector2.ZERO else vel.normalized()
	var f: int
	match st:
		S.BOLT:
			f = FRAMES["flap"][int(t * 12.0) % 2]
		S.WALK, S.HERD:
			f = FRAMES["walk"][int(t * 6.0) % 2]
		_:
			f = FRAMES["peck"] if pecking else FRAMES["stand"]
	sprite.frame = (color * 8 + Iso.dir8(d)) * sprite.hframes + f
	sprite.position.y = -round(absf(sin(t * 14.0)) * 2.0) if st == S.BOLT else 0.0
