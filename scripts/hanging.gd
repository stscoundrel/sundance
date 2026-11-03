class_name Hanging
extends Node
## A hanging in the plaza (a level's "hanging": {"at": seconds, "condemned": kind,
## "hangman": bandit kind}). The gang has a man up on the gallows, an innocent one,
## noose round his neck, and they mean to drop him at the hour. The hangman keeps
## to the foot of the steps till it's done, whatever the town gets up to; only if he
## sees the stranger with his own eyes does he go for the lever early, and a shot in
## the moment it takes him stops it. Once the trap goes the man kicks a few seconds:
## a round through the rope (or the stranger's knife) and he's down and away into
## the nearest building. Cut loose before the hour (hold E at the gallows), the same.
## Hanged or shot, the fight goes on: the end card says the stranger failed him.

const LEVER_T := 2.0      # s from the hangman spotting him to the trap going
const KICK_T := 7.0       # s he kicks on the rope, then it's over
const CUT_T := 1.0        # s of the stranger's knife at the ropes
const CUT_REACH := 50.0   # px from the trap: close enough to cut him loose from the platform's edge
const ROPE_R := 5.0       # px: the rope, a thin thing to hit (a Colt's round finds it at 150 px, mostly)
const MAN_R := 7.0        # (and the man on the trap, before it goes)
const OVER := 70.0        # px into the platform a round can fly at either and not stop at its edge
const PLATFORM := 1.5     # m: the gallows' floor, where he stands
const DROP := 0.8         # m he falls through the trap
const NOOSE := 3.05       # m: where the gallows' rope ends, over the trap
const NECK := 1.5         # m up from his feet
const STEPS := Vector2(4.6, 1.6)   # tiles from the gallows' corner: the foot of its steps
const POST := Vector2(4.4, 0.6)    # and the hangman's place beside them
const PLEA := ["¡Soy inocente!", "I didn't do nothing!", "¡Piedad!", "Somebody... please!"]
const THANKS := ["¡Gracias, señor!", "God bless you!", "¡Me salvó!"]
const LEVER_LINES := ["¡Ahora!", "Drop him!", "¡Que cuelgue!"]

static var rng := RandomNumberGenerator.new()   # the condemned man's own dice

var game: Node
var at := 300.0            # game.clock when they drop him
var man: Civilian
var hangman: Enemy
var trap := Vector2.ZERO   # the trap, on the ground plane (where the rope comes down)
var steps := Vector2.ZERO
# "waiting" (on the trap, the hour not come), "lever" (the hangman's going for it),
# "hanging" (kicking), then "freed", "hanged" or "shot".
var state := "waiting"
var lever_t := 0.0
var kick_t := 0.0
var cut_t := 0.0
var plea_t := 6.0
var pleas := 0
var told := false
var rope: StaticBody2D
var hole: Polygon2D
var line_up: Line2D       # the rope down to his neck, once he's fallen


func setup(g: Node, data: Dictionary) -> void:
	game = g
	at = float(data.get("at", at))
	var corner := Vector2.INF
	for o in g.level["objects"]:
		if o["type"] == "gallows":
			corner = Vector2(o["x"], o["y"])
	var fp: Array = g.meta["objects"]["gallows"]["footprint"]
	trap = Iso.to_screen(corner + Vector2(fp[0], fp[1]) * 0.5)
	steps = Iso.to_screen(corner + STEPS)
	hangman = g._add_enemy(data.get("hangman", "hangman"), Iso.to_screen(corner + POST), PackedVector2Array(), 135.0,
		{"hangman": true})
	man = Civilian.new()
	g.world.add_child(man)
	man.setup(g, data.get("condemned", "captive"), trap, 45.0, {"role": "condemned"})
	hangman.died.connect(_on_hangman_died)
	man.died.connect(_on_man_died)
	man.died.connect(g._on_civilian_died)
	g.civilians.append(man)
	man.bound = true
	man.z_index = 2   # (up on the platform: over the gallows, whose middle he shares)
	man.lift = Vector2(0, -PLATFORM * Actor.PZ)
	man.set_deferred("collision_layer", 0)
	man.set_deferred("collision_mask", 0)


## The stranger's knife at the ropes, from the platform's edge: close enough?
func can_cut(from: Vector2) -> bool:
	return state in ["waiting", "lever", "hanging"] and man.alive and from.distance_to(trap) < CUT_REACH


## Holding E there: once he's been at it long enough, the man is loose.
func cutting(delta: float) -> bool:
	cut_t += delta
	if cut_t >= CUT_T:
		cut_t = 0.0
		_free(game.player.global_position)
		return true
	return false


## The cursor on him (standing on the trap or hanging through it) or on the rope:
## they're drawn well up off the trap, which is where a shot at them has to go.
func under(m: Vector2) -> bool:
	if not man.alive or not state in ["waiting", "lever", "hanging"]:
		return false
	var top := NOOSE + 0.2 if state == "hanging" else PLATFORM + 1.8
	return absf(m.x - trap.x) < 8.0 and m.y < trap.y - (PLATFORM - DROP) * Actor.PZ and m.y > trap.y - top * Actor.PZ


## The hangman keeps to his place while there's still a man to hang.
func holds(e: Enemy) -> bool:
	return e == hangman and state in ["waiting", "lever"] and e.alive


## The hangman has the stranger in his own sights: he goes for the lever.
func spotted(by: Enemy) -> void:
	if state != "waiting":
		return
	state = "lever"
	lever_t = LEVER_T
	by._say(LEVER_LINES[0])
	game.stats["hangman saw him"] = true


func seconds_left() -> float:
	return at - game.clock


## A round's path from `p` along `v`: does it carry on over the platform to the man
## on the trap (or the rope he hangs from)? Heights don't count, so without this the
## gallows' edge would stop every one.
func over_gallows(p: Vector2, v: Vector2) -> bool:
	if not man.alive or not state in ["waiting", "lever", "hanging"]:
		return false
	var r := ROPE_R if state == "hanging" else MAN_R
	var d := v.normalized()
	var along := (trap - p).dot(d)
	return along > 0.0 and along < OVER and (p + d * along).distance_to(trap) < r


## A round through the rope: he drops into the dirt under the trap, and runs. The
## stranger's rounds that find the man himself on the gallows count as this too: he'd
## never aim at him, and a round lined up on one is lined up on the other. (A bandit's
## stray round is another matter.)
func rope_shot(by: Actor) -> void:
	if not state in ["waiting", "lever", "hanging"]:
		return
	game.stats["rope shot"] = by.is_player
	game.sfx("tear", trap, -2.0, 0.1)
	game.impact(trap, 40.0, Vector2.RIGHT, true, false)
	_free(by.global_position)


func _physics_process(delta: float) -> void:
	if game.state != "play" or not man.alive and state != "hanged":
		return
	if not told:
		told = true
		game.hud.banner("They hang an innocent man in the plaza at noon!")
	match state:
		"waiting":
			plea_t -= delta
			if plea_t <= 0.0:
				plea_t = 9.0
				man._say(PLEA[pleas % PLEA.size()])
				pleas += 1
			if game.clock >= at and hangman.alive and not hangman.downed:
				_drop()   # the hour: dead or alive, the stranger has to stop him first
		"lever":
			if not hangman.alive:
				state = "waiting"   # he didn't get there
				return
			lever_t -= delta
			if lever_t <= 0.0:
				_drop()
		"hanging":
			kick_t -= delta
			man.velocity = man.facing * 60.0   # (not going anywhere: his legs, kicking)
			man.pose = "struggle"
			if kick_t <= 0.0:
				_hanged()
		"hanged":
			# still now, turning a little on the rope
			var sway := sin(game.clock * 1.1) * 1.2
			man.legs_spr.position.x = sway
			man.upper_spr.position.x = sway


## The trap goes.
func _drop() -> void:
	state = "hanging"
	kick_t = KICK_T
	game.sfx("wood_break", trap, 0.0, 0.0)
	game.sfx("bell", null, -6.0, 0.0)
	game.hud.banner("The trap's gone! Shoot the rope!")
	man.hurtbox.set_deferred("collision_layer", 0)   # (the rope takes the rounds now)
	man.lift = Vector2(0, -(PLATFORM - DROP) * Actor.PZ)
	man.clip_below(trap.y - PLATFORM * Actor.PZ + 3.0)   # his legs down through the hole
	hole = Polygon2D.new()   # the open trap
	var c := Iso.to_grid(trap)
	var poly := Iso.rect_poly(c.x - 0.45, c.y - 0.45, c.x + 0.45, c.y + 0.45)
	for i in poly.size():
		poly[i] += Vector2(0, -PLATFORM * Actor.PZ)
	hole.polygon = poly
	hole.color = Color(0.08, 0.05, 0.04)
	hole.z_index = 1
	game.world.add_child(hole)
	line_up = Line2D.new()
	line_up.points = PackedVector2Array([trap + Vector2(0, -NOOSE * Actor.PZ),
		trap + Vector2(0, -(PLATFORM - DROP + NECK) * Actor.PZ)])
	line_up.width = 1.0
	line_up.default_color = Color(0.67, 0.59, 0.43)
	line_up.z_index = 3
	game.world.add_child(line_up)
	rope = StaticBody2D.new()
	rope.collision_layer = Iso.LAYER_FRAGILE
	rope.collision_mask = 0
	rope.position = trap
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = ROPE_R
	cs.shape = circle
	rope.add_child(cs)
	rope.set_meta("rope", self)
	game.statics.add_child(rope)


func _hanged() -> void:
	state = "hanged"
	man.velocity = Vector2.ZERO
	man.pose = "hang"   # his head fallen forward
	man.update_anim(0.0)
	man.still = true
	game.stats["condemned"] = "hanged"
	if rope:
		rope.queue_free()
		rope = null


## Loose: down off the gallows and into the nearest building, out of it.
func _free(from: Vector2) -> void:
	var was := state
	state = "freed"
	game.stats["condemned"] = "saved"
	if rope:
		rope.queue_free()
		rope = null
	man.lift = Vector2.ZERO
	man.clip_below(1e9)
	man.z_index = 0
	man.hurtbox.set_deferred("collision_layer", Iso.LAYER_HURT)
	if line_up:
		line_up.queue_free()
		line_up = null
	man.global_position = steps   # (out from under the trap, or down the steps)
	man.set_deferred("collision_layer", Iso.LAYER_ACTOR)
	man.set_deferred("collision_mask", Iso.LAYER_WALL | Iso.LAYER_COVER | Iso.LAYER_POST | Iso.LAYER_ACTOR)
	man.set_free(from, THANKS[0] if was != "hanging" else THANKS[1])


## Down before he's dropped him: nobody else will (the stranger had better know it,
## the hangman looking like any other of the gang).
func _on_hangman_died(_a: Actor) -> void:
	if state in ["waiting", "lever"]:
		state = "waiting"
		game.hud.banner("The hangman's dead! Nobody left to drop him.")


func _on_man_died(_a: Actor) -> void:
	if state != "hanged":
		state = "shot"
		game.stats["condemned"] = "shot"
	if rope:
		rope.queue_free()
		rope = null


## For the end card.
func line() -> String:
	match state:
		"freed":
			return "the condemned man: saved   -   "
		"hanged":
			return "the condemned man: hanged, you failed him   -   "
		"shot":
			return "the condemned man: shot dead, you failed him   -   "
	return "the condemned man: saved   -   "   # (alive on the trap, and nobody left to drop him)
