class_name Director
extends Node
## A level's waves: more of the gang arriving at set times, on foot, down the roads
## into town, whether or not the stranger has dealt with the last lot (that's his
## problem). The level lists them ("waves": [{"at": seconds into the fight, "groups":
## [{"from": an entry's name, "count": n, "kinds": [...] optional}]}]); the map names
## its entries, where the roads cross its edge. A countdown shows the next; a little
## before, word comes of which way they're coming. Arrivals make for the middle of
## town, unless there's shooting going on they can hear: then they go to it.

const WARN := 15.0          # s of warning: which roads they're coming down
const EVERY := 0.9          # s between men walking in off the same road
const HEAR := 1100.0        # px: gunfire this close to where they come in, and recent,
const HEAR_FOR := 8.0       # s: is a fight going on (they go to it)

var game: Node
var waves: Array = []
var clock := 0.0            # into the fight (only while it's on)
var next := 0               # the next wave due
var warned := -1            # the last wave word has come of
var queue: Array = []       # men still to walk in: [entry dict, kind]
var spawn_t := 0.0
var arrived := 0
var entries := {}           # name -> {name, at (screen), into (a step inside, screen)}
var rng := RandomNumberGenerator.new()


func setup(g: Node, wave_list: Array) -> void:
	game = g
	waves = wave_list
	rng.seed = 7919 + waves.size()
	var mid := _center()
	for e in g.level.get("entries", []):
		var at := Iso.to_screen(Vector2(e["x"], e["y"]))
		entries[e["name"]] = {"name": e["name"], "at": at, "into": at + (mid - at).normalized() * 40.0}


func _center() -> Vector2:
	var c: Dictionary = game.level.get("center", {"x": game.size / 2.0, "y": game.size / 2.0})
	return Iso.to_screen(Vector2(c["x"], c["y"]))


## Seconds to the next wave, or -1 when there are no more.
func next_in() -> float:
	return float(waves[next]["at"]) - clock if next < waves.size() else -1.0


## The roads the next wave is coming down, once word of it has come (else empty).
func warned_from() -> Array:
	if next >= waves.size() or warned < next:
		return []
	return waves[next]["groups"].map(func(gr): return entries[gr["from"]])


## The roads men are walking in by right now.
func arriving_from() -> Array:
	var seen := {}
	for q in queue:
		seen[q[0]["name"]] = q[0]
	return seen.values()


## All in: no wave still to come or still walking in.
func done() -> bool:
	return next >= waves.size() and queue.is_empty()


func _process(delta: float) -> void:
	if game.state != "play":
		return
	clock += delta
	if next < waves.size():
		var w: Dictionary = waves[next]
		if warned < next and clock >= float(w["at"]) - WARN:
			warned = next
			var names: Array = w["groups"].map(func(gr): return gr["from"])
			game.hud.banner("Men coming in by the %s!" % " and the ".join(names))
			game.sfx("sting", null, -12.0, 0.0)
			game.stats["waves warned"] = game.stats.get("waves warned", 0) + 1
		if clock >= float(w["at"]):
			_send(w)
			next += 1
	if not queue.is_empty():
		spawn_t -= delta
		if spawn_t <= 0.0:
			spawn_t = EVERY / maxf(1.0, _roads_in_queue())
			_walk_in(queue.pop_front())


func _roads_in_queue() -> float:
	var seen := {}
	for q in queue:
		seen[q[0]["name"]] = true
	return float(seen.size())


## A wave: its men lined up on their roads, interleaved so each road sends one in turn.
func _send(w: Dictionary) -> void:
	var lines: Array = []
	for gr in w["groups"]:
		var kinds: Array = gr.get("kinds", [])
		if kinds.is_empty():
			kinds = range(int(gr["count"])).map(func(_i): return _a_kind())
		lines.append(kinds.map(func(k): return [entries[gr["from"]], k]))
	var longest := 0
	for l in lines:
		longest = maxi(longest, l.size())
	for i in longest:
		for l in lines:
			if i < l.size():
				queue.append(l[i])
	spawn_t = 0.0
	game.stats["waves"] = game.stats.get("waves", 0) + 1


## One of the gang's sort (those passing as townsfolk and El Jefe don't come
## marching in), in the mix of the men already in town.
func _a_kind() -> String:
	var pool: Array = game.level["enemies"].map(func(e): return e["kind"]).filter(
		func(k): return not k in ["jefe", "gambler", "saloon_girl"])
	if pool.is_empty():
		return "bandido"
	return pool[rng.randi_range(0, pool.size() - 1)]


func _walk_in(q: Array) -> void:
	var entry: Dictionary = q[0]
	var at: Vector2 = entry["at"]
	if not game.is_free(at):
		at = game.free_point_near(at, 30.0)
	var en: Enemy = game._add_enemy(q[1], at, PackedVector2Array(), rad_to_deg((entry["into"] - entry["at"]).angle()))
	arrived += 1
	game.stats["arrivals"] = game.stats.get("arrivals", 0) + 1
	var fight: bool = game.clock - game.last_gunfire < HEAR_FOR and game.last_gunfire_at.distance_to(at) < HEAR
	if fight:
		en.enter_combat(game.last_gunfire_at, false, false)   # the shooting: that's where they're wanted
		game.stats["arrive to a fight"] = game.stats.get("arrive to a fight", 0) + 1
	else:
		en.arrive(_post_near_center(), entry["at"])


## A spot of his own about the middle of town: they spread out there and wait.
func _post_near_center() -> Vector2:
	var mid := _center()
	for r in [0.0, 40.0, 80.0, 120.0, 160.0]:
		for k in 8:
			var p: Vector2 = mid + Vector2.from_angle(k * TAU / 8.0 + rng.randf() * 0.4) * r
			if game.is_free(p) and game.enemies.all(func(e): return not e.alive or e.home.distance_to(p) > 24.0):
				return p
	return mid
