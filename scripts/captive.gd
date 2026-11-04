class_name Captive
extends Node
## A man tied to a pole by the well (a level's "captive": {"kind", "pole": [x, y],
## "guard": [x, y], "count": seconds}): one of the stranger's own, caught and kept
## for an example. One of the garrison stands over him (the man placed nearest
## "guard", taken off his rounds for it). Nothing happens while all is quiet; the
## first shot fired, whoever fires it, and the guard puts his gun to the man's head
## and shouts: stop, or he dies. He counts it out ("count" seconds), and doesn't
## turn his gun on anyone else while he does; kill him (or drop him) in time and the
## man lives, for now. El General, the moment he's out of his house, makes straight
## for the pole if the man's still tied there, and does the same: he's desperate,
## half his men outside the walls. The stranger's own rounds never touch the man
## (he'd never aim at him); anyone else's can. Hold E at the pole and he's loose: he
## runs for the chapel and hides there. He's fought the revolution's battles as long
## as the stranger has: dynamite going off about the fort doesn't touch him, only a
## stick landing right on him. Killed, and the stranger is told to make
## the fort pay for it; either way the fight goes on, and the end card says so.
## With the count nearly out he starts a line from the song ("Hay que ganar muriendo,
## pistoleros"), and the shot cuts it off where it finds him; drop the man counting
## in time and he gets to the end of it.

const COUNT := 10.0        # s the guard (or El General) gives the stranger
const SAY_EVERY := 2.5     # s between threats
const CUT_T := 1.0         # s of the stranger's knife at the ropes
const CUT_REACH := 40.0    # px from the man (feet to feet): beside him, as it looks on screen
const BLAST_ON := 12.0     # px: an old guerrilla, bangs all round him don't trouble him; only one right on him
const BESIDE := [Vector2(-0.75, 0.55), Vector2(0.55, 0.95)]   # tiles from the pole: the guard's place, El General's
const GUARD_LINES := ["¡Alto o lo mato!", "One more step, gringo, and he's dead!", "¡Suelta el arma o se muere!",
	"I'll do it! I swear I'll do it!"]
const GENERAL_LINES := ["¡Diez segundos, gringo!", "Show yourself, or your amigo dies!", "¡Ríndete o lo mato!",
	"He pays for every one of my men!"]
const THANKS := "¡Gracias, compadre!"
const LAST_WORDS := "Hay que ganar muriendo, pistoleros"
const LAST_FROM := 2.0     # s left on the count when he starts it
const LAST_RATE := 10.0    # letters a second: the shot comes at "Hay que ganar murien"

static var rng := RandomNumberGenerator.new()   # (for finding his guards their footing)

var game: Node
var count := COUNT
var man: Civilian
var guard: Enemy
var general: Enemy
var pole := Vector2.ZERO   # the pole, on the ground plane
var spots := PackedVector2Array()   # where the guard stands, and El General
var chapel := Vector2.INF  # the door he runs for once he's loose
# "tied" (nobody counting), "guard" (the guard counting it out), "coming" (El
# General on his way), "general" (El General counting), then "freed" or "dead".
var state := "tied"
var count_t := 0.0
var say_t := 0.0
var said := 0
var cut_t := 0.0
var roused := false   # the first shot's been fired
var told := false


func setup(g: Node, data: Dictionary) -> void:
	game = g
	count = float(data.get("count", COUNT))
	var corner := Vector2(data["pole"][0], data["pole"][1])
	g._place_object("pole", corner)
	var fp: Array = g.meta["objects"]["pole"]["footprint"]
	var c := corner + Vector2(fp[0], fp[1]) * 0.5
	pole = Iso.to_screen(c)
	for b in BESIDE:
		var at := Iso.to_screen(c + b)
		spots.append(at if g.is_free(at) else g.free_point_near(at, 24.0, rng))   # (clear of the well)
	var near := Iso.to_screen(Vector2(data["guard"][0], data["guard"][1]))
	for e in g.enemies:
		if guard == null or e.global_position.distance_to(near) < guard.global_position.distance_to(near):
			guard = e
	guard.captor = true
	guard.patrol = PackedVector2Array()
	guard.st = Enemy.St.GUARD
	guard.global_position = spots[0]
	guard.home = spots[0]
	guard.home_facing = (pole - spots[0]).normalized()
	guard.facing = guard.home_facing
	guard.desired = guard.facing
	man = Civilian.new()
	g.world.add_child(man)
	man.setup(g, data.get("kind", "captive"), pole + Iso.to_screen(Vector2(0.3, 0.3)), 90.0, {"role": "condemned"})
	man.died.connect(_on_man_died)
	man.died.connect(g._on_civilian_died)
	g.civilians.append(man)
	man.bound = true
	man.set_deferred("collision_layer", 0)
	man.set_deferred("collision_mask", 0)
	for o in g.level["objects"]:
		if o["type"] == "chapel":
			var mid := Iso.to_screen(Vector2(o["x"], o["y"]) + Vector2(2.5, 3.0))
			for d in g.doors:
				if chapel == Vector2.INF or d.distance_to(mid) < chapel.distance_to(mid):
					chapel = d


## Standing over him with a gun to his head: he's going nowhere else, and shooting
## at nobody else, till it's done.
func holds(e: Enemy) -> bool:
	return e.alive and (e == guard and state == "guard" or e == general and state in ["coming", "general"])


## Where each of them stands over him.
func spot_for(e: Enemy) -> Vector2:
	return spots[0] if e == guard else spots[1]


func can_cut(from: Vector2) -> bool:
	return state in ["tied", "guard", "coming", "general"] and man.alive and from.distance_to(man.global_position) < CUT_REACH


func cutting(delta: float) -> bool:
	cut_t += delta
	if cut_t >= CUT_T:
		cut_t = 0.0
		_free()
		return true
	return false


## Seconds left on whoever's counting, or -1.
func seconds_left() -> float:
	return count_t if state in ["guard", "general"] else -1.0


func _physics_process(delta: float) -> void:
	if game.state != "play" or state in ["freed", "dead"]:
		return
	if not told:
		told = true
		game.hud.banner("Cut your compañero loose by the well: hold E!")
	if not roused and game.last_gunfire > -1e8:
		roused = true
		if _up(guard):
			_start("guard", guard)
	match state:
		"tied":
			if general == null:
				for e in game.enemies:
					if e.kind == "general":
						general = e
			if roused and _up(general):
				state = "coming"
				general.say_line("spot", ["¡El prisionero! ¡Ahora!"])
		"coming":
			if not _up(general):
				state = "tied"
			elif general.global_position.distance_to(spots[1]) < 10.0:
				_start("general", general)
		"guard", "general":
			var by := guard if state == "guard" else general
			if not _up(by):
				state = "tied"   # dead or down before he could: the man lives, for now
				if count_t <= LAST_FROM:
					man.shout = LAST_WORDS   # (and gets to finish it)
					man.shout_t = 3.0
				if by == guard:
					game.hud.banner("His guard's down! Cut him loose!")
				return
			count_t -= delta
			if count_t <= LAST_FROM:
				man.shout = LAST_WORDS.left(ceili((LAST_FROM - maxf(count_t, 0.0)) * LAST_RATE))
				man.shout_t = 1.0
			say_t -= delta
			if say_t <= 0.0:
				say_t = SAY_EVERY
				var lines: Array = GUARD_LINES if by == guard else GENERAL_LINES
				by._say(lines[said % lines.size()])
				said += 1
			if count_t <= 0.0:
				_execute(by)


func _up(e: Enemy) -> bool:
	return e != null and e.alive and not e.downed


func _start(s: String, by: Enemy) -> void:
	state = s
	count_t = count
	say_t = 0.0
	said = 0
	game.stats["captive threatened by"] = by.kind


## Time's up: point-blank, the man's head.
func _execute(by: Enemy) -> void:
	var dir := (man.global_position - by.global_position).normalized()
	by.facing = dir
	by.desired = dir
	by.play_action("fire")
	game.muzzle_flash(by, dir)
	game.sfx(by.weapon.d["sfx"], by.global_position, 0.0, 0.1)
	game.make_noise(by.global_position, by.weapon.d["noise"], "enemy_shot", by)
	man.take_hit(5, dir, by)
	game.stats["captive executed by"] = by.kind


func _free() -> void:
	state = "freed"
	game.stats["captive"] = "saved"
	man.set_deferred("collision_layer", Iso.LAYER_ACTOR)
	man.set_deferred("collision_mask", Iso.LAYER_WALL | Iso.LAYER_COVER | Iso.LAYER_POST | Iso.LAYER_ACTOR)
	man.refuge = chapel
	man.set_free(game.player.global_position, THANKS)


func _on_man_died(_a: Actor) -> void:
	if man.shout_t > 0.0 and man.shout != "" and man.shout != LAST_WORDS and LAST_WORDS.begins_with(man.shout):
		man.shout += "—"   # cut off
		man.shout_t = 2.0
		man.last_words = true
	state = "dead"
	game.stats["captive"] = "dead"
	game.hud.banner("They've killed him! Make the whole fort pay for it.")


## For the end card.
func line() -> String:
	if state == "dead":
		return "the prisoner: shot dead, you failed him   -   "
	return "the prisoner: saved   -   "   # (loose, or alive at the pole with the fort taken)
