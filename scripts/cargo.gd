class_name Cargo
extends Node
## Paso Esperanza's clock: the revolution carrying the train's arms off to its wagons
## (a level's "cargo", the map's "cargo"). The carriers (Civilian, "role": "carrier")
## take a load at a time from the piles (cases stacked by the doors, rifles heaped
## where the cases broke, the boxcars themselves) to whichever wagon is loading; a
## full wagon drives off the map, kicking up dust, and the next one loads. A carrier
## shot down drops what he had where he fell, for the next to pick up, and a
## replacement or two comes up from the wagons. Every load in, and the last wagon
## waits for the stranger: he gets to it and he's away, and so is the level. Every
## carrier dead, and nobody's left to carry them: it's lost.

static var rng := RandomNumberGenerator.new()   # (the dust: its own dice)

const BOARD := 34.0       # px from the last wagon's tail: close enough to climb on
const LEAVE_T := 8.0      # s for a wagon to drive off the map
const SPARE_AFTER := 8.0  # s after a carrier falls before his replacement comes up
const CLAIM_COST := 140.0 # px: a pile someone's already going to counts as this much further
const WORTH := {"mg": 3}  # loads a load counts for: a machine gun's worth three of anything else

var game: Node
var goal := 40
var loaded := 0
var spare := 2
var pending := 0          # replacements on their way
var sources: Array[Dictionary] = []   # {kind, at, count, claims, rec}
var wagons: Array[Dictionary] = []    # {recs, at, corner, cap, n, gone}
var carriers: Array = []
var leader: Civilian
var done := false         # every load in: the last wagon waits for him
var over := false
var lost_carriers := 0
var _dust_t := 0.0


func setup(g: Node, cfg: Dictionary) -> void:
	game = g
	goal = int(cfg.get("loads", 40))
	spare = int(cfg.get("spare", 2))
	var m: Dictionary = g.level["cargo"]
	for s in m["sources"]:
		var src := {"kind": s["kind"], "at": Iso.to_screen(Vector2(s["x"], s["y"])), "count": int(s["count"]),
			"claims": 0, "rec": {}}
		if s.has("object"):
			src["rec"] = g.placed_near(s["object"][0], Vector2(s["object"][1], s["object"][2]))
		sources.append(src)
	var ws: Array = m["wagons"]
	var left := goal
	for i in ws.size():
		var corner := Vector2(ws[i]["x"], ws[i]["y"])
		var recs := []
		for k in 2:   # (the carreta's two pieces: the team, then the wagon)
			var rec: Dictionary = g.placed_near("carreta_%d" % k, corner + Vector2(2.5 * k, 0.0))
			if not rec.is_empty():
				recs.append(rec)
		var cap := left if i == ws.size() - 1 else goal / ws.size()
		left -= cap
		wagons.append({"recs": recs, "corner": corner, "at": Iso.to_screen(corner + Vector2(5.4, 0.65)),
			"cap": cap, "n": 0, "gone": false})
	for c in g.civilians:
		if c.carrier:
			_take_on(c)
		elif c.leader:
			leader = c


func _take_on(c: Civilian) -> void:
	carriers.append(c)
	c.died.connect(_on_carrier_died.bind(c))


## The wagon loading now (or, with everything in, the one waiting for him).
func wagon() -> Dictionary:
	for w in wagons:
		if not w["gone"] and (w["n"] < w["cap"] or w == wagons[-1]):
			return w
	return wagons[-1]


func wagon_at() -> Vector2:
	return wagon()["at"]


## The pile for this carrier: of the kind he carries, near him and not too far from
## the wagon, and not one everybody's already making for.
func source_for(c: Civilian) -> Dictionary:
	var best := {}
	var score := INF
	var to: Vector2 = wagon_at()
	for s in sources:
		if s["kind"] != c.carries or s["count"] - s["claims"] <= 0:
			continue
		var d: float = c.global_position.distance_to(s["at"]) + s["at"].distance_to(to) * 0.5 + s["claims"] * CLAIM_COST
		if d < score:
			score = d
			best = s
	if not best.is_empty():
		best["claims"] += 1
	return best


func release(s: Dictionary) -> void:
	if not s.is_empty():
		s["claims"] = maxi(0, s["claims"] - 1)


## One load off the pile, if there's one left. An empty pile is gone from the map.
func take(s: Dictionary) -> bool:
	release(s)
	if not sources.has(s) or s["count"] <= 0:
		return false
	s["count"] -= 1
	if s["count"] <= 0:
		sources.erase(s)
		if not s["rec"].is_empty():
			game.lift_object(s["rec"])
	return true


## A load into the wagon. A full one drives off; with every load in, it's done.
func stow(c: Civilian) -> void:
	if done:
		return   # (one more on top: it's all in already)
	var w := wagon()
	var worth: int = WORTH.get(c.load_kind, 1)
	w["n"] += worth
	loaded = mini(goal, loaded + worth)
	game.stats["loads"] = loaded
	if loaded >= goal:
		_all_in()
	elif w["n"] >= w["cap"] and w != wagons[-1]:
		_drive_off(w)
		game.hud.toast("A wagon's away, loaded")


## Shot down with a load in his arms: it falls where he does.
func drop(at: Vector2, kind: String) -> void:
	var g: Vector2 = Iso.to_grid(at)
	var type: String = {"case": "rifle_crate", "rifles": "rifle_pile", "mg": "mgun_pile"}[kind]
	var fp: Vector2 = Vector2(game.meta["objects"][type]["footprint"][0], game.meta["objects"][type]["footprint"][1])
	game._place_object(type, g - fp * 0.5)
	sources.append({"kind": kind, "at": at + Vector2(0, 6), "count": 1, "claims": 0, "rec": game.placed[-1]})


func _on_carrier_died(_a: Actor, c: Civilian) -> void:
	lost_carriers += 1
	if c.load_kind != "":
		drop(c.global_position, c.load_kind)
		c.load_kind = ""
	if c.src:
		release(c.src)
		c.src = {}
	if done or over:
		return
	if spare > 0:
		spare -= 1
		pending += 1
		get_tree().create_timer(SPARE_AFTER, false).timeout.connect(_replace.bind(c.kind))
	elif carriers_alive() == 0 and pending == 0:
		_lose()


func _replace(k: String) -> void:
	pending -= 1
	if over or game.state != "play":
		return
	var w := wagon()
	var cv := Civilian.new()
	game.world.add_child(cv)
	cv.setup(game, k, w["at"] + Vector2(10, 4), 0.0, {})
	cv.died.connect(game._on_civilian_died)
	cv.make_ghost(game.ghost_layer, game.GHOST_TOWN)
	game.civilians.append(cv)
	_take_on(cv)
	game.hud.toast("Another carrier comes up from the wagons")


## Where the stranger's wanted, for the HUD's arrows: the carriers, at the comandante's
## heap by the cab, till it's all loaded (then the wagon has its own arrow).
func marks() -> Array:
	if done or over:
		return []
	return [[leader.global_position if leader and leader.alive else wagon_at(), "THE CARRIERS"]]


func carriers_alive() -> int:
	var n := 0
	for c in carriers:
		if c.alive:
			n += 1
	return n


func _all_in() -> void:
	done = true
	game.hud.banner("That's the lot! Get to the wagon, compañero!")
	if leader and leader.alive:
		leader.say_done()


## Off the map with it: its weight off the ground at once, the sprite rolling away
## west under its own dust.
func _drive_off(w: Dictionary) -> void:
	w["gone"] = true
	var by: Vector2 = Iso.to_screen(Vector2(-(w["corner"].x + 9.0), 0.0))
	for rec in w["recs"]:
		game.lift_object(rec, true)
		var spr: Sprite2D = rec["sprite"]
		var tw := game.create_tween()
		tw.tween_property(spr, "position", spr.position + by, LEAVE_T).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(spr.queue_free)
	w["leaving_t"] = LEAVE_T


func _physics_process(delta: float) -> void:
	_dust_t -= delta
	if _dust_t <= 0.0:
		_dust_t = 0.12
		for w in wagons:
			if w.get("leaving_t", 0.0) > 0.0:
				_dust(w)
	for w in wagons:
		if w.get("leaving_t", 0.0) > 0.0:
			w["leaving_t"] -= delta
	if over or game.state != "play":
		return
	if done and game.player.alive and not game.player.down \
			and game.player.global_position.distance_to(wagon_at()) < BOARD:
		_away()


func _dust(w: Dictionary) -> void:
	for rec in w["recs"]:
		var spr: Sprite2D = rec["sprite"]
		if not is_instance_valid(spr):
			continue
		var puff := Puff.new()
		puff.position = spr.position + Vector2(rng.randf_range(-12, 12), 4)
		for i in 3:
			var shade := rng.randf_range(0.62, 0.74)
			puff.smoke(Vector2(rng.randf_range(-10, 10), -rng.randf_range(0, 4)),
				Vector2(rng.randf_range(10, 30), -rng.randf_range(4, 12)), rng.randf_range(1.2, 2.0),
				rng.randf_range(3.0, 5.0), Color(shade, shade * 0.85, shade * 0.66, 0.45), rng.randf_range(3.0, 5.0),
				game.WIND * 0.5)
		game.world.add_child(puff)


## He's on the wagon: out of sight in it, and away it goes. That's the level.
func _away() -> void:
	over = true
	var p: Player = game.player
	p.visible = false
	p.set_deferred("collision_layer", 0)
	p.hurtbox.set_deferred("collision_layer", 0)
	_drive_off(wagons[-1])
	if leader and leader.alive and leader.visible:
		leader.board()
	for c in carriers:
		if c.alive and c.visible:
			c.board()
	game.end_level(true, "¡VÁMONOS, MUCHACHOS!")


func _lose() -> void:
	over = true
	game.end_level(false, "NOBODY LEFT TO CARRY THEM")


## For the end card.
func line() -> String:
	return "%d of %d loads away, %d carriers lost   -   " % [loaded, goal, lost_carriers]
