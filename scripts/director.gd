class_name Director
extends Node
## A level's waves: more of the gang arriving at set times, on foot, down the roads
## into town, whether or not the stranger has dealt with the last lot (that's his
## problem). The level lists them ("waves": [{"at": seconds into the fight, "groups":
## [{"from": an entry's name, "count": n, "kinds": [...] optional}]}]); the map names
## its entries, where the roads cross its edge. A countdown shows the next; a little
## before, word comes of which way they're coming. Arrivals make for the middle of
## town, unless there's shooting going on they can hear: then they go to it.
##
## A map can also keep some of its gang indoors ("sleepers", each at the door he'll
## come out of): nobody's there till the first shot (or till everyone outside has gone
## quiet for good). Then out they come, the ready ones in a couple of seconds, the
## rest when they've woken and found their boots. A level can count its waves from
## that first shot instead of from the start ("waves_from": "first_shot"). No more
## than CROWD of the gang are about at once: past that, the rest wait out on the
## road till there's room (the frame time's the reason, and a fair fight).
##
## A wave marked "rally" comes after a lull: word comes, a little after the one
## before it, that they're gathering outside the walls. A wave (or one of its
## groups) can hand its men other guns than their own ("arms": a set named in
## levels.json; [] for their own): the last of them, scraped together, are badly armed.

const WARN := 15.0          # s of warning: which roads they're coming down
const EVERY := 0.45         # s between men walking in off the same road (a band, not a file)
const HEAR := 1100.0        # px: gunfire this close to where they come in, and recent,
const HEAR_FOR := 8.0       # s: is a fight going on (they go to it)
const CROWD := 40           # alive at once, at most: the rest wait out on the road for room
const READY := Vector2(1.5, 2.5)     # s: out of the door, the ones who were ready
const ASLEEP := Vector2(12.0, 18.0)  # s: the ones who had to wake up first
const RALLY_AFTER := 20.0   # s after a wave's due that word comes of the next one rallying, after a lull

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
var sleepers: Array = []    # still indoors: {kind, at (screen, outside his door), delay}
var roused := -1.0          # when the first shot was fired (or the quiet noticed), or -1
var quiet := false          # roused by the quiet, not the shooting
var from_shot := false      # the waves count from the first shot
var rallied := -1           # the last wave word has come of it rallying
var arms_sets := {}         # name -> loadout options (levels.json "arms")


func setup(g: Node, wave_list: Array, from_first_shot := false) -> void:
	game = g
	waves = wave_list
	from_shot = from_first_shot
	rng.seed = 7919 + waves.size()
	arms_sets = g._load_json("res://data/levels.json").get("arms", {})
	for sl in g.level.get("sleepers", []):
		var r: Vector2 = READY if sl.get("ready", false) else ASLEEP
		var delay := rng.randf_range(r.x, r.y)
		if sl.has("after"):   # (or a set time after the shot, give or take)
			delay = maxf(0.5, float(sl["after"]) + rng.randf_range(-0.5, 0.5))
		sleepers.append({"kind": sl["kind"], "at": Iso.to_screen(Vector2(sl["x"], sl["y"])),
			"delay": delay, "ready": delay < 5.0})
	var mid := _center()
	for e in g.level.get("entries", []):
		var at := Iso.to_screen(Vector2(e["x"], e["y"]))
		entries[e["name"]] = {"name": e["name"], "at": at, "into": at + (mid - at).normalized() * 40.0}


func _center() -> Vector2:
	var c: Dictionary = game.level.get("center", {"x": game.size / 2.0, "y": game.size / 2.0})
	return Iso.to_screen(Vector2(c["x"], c["y"]))


## How far into the waves' own clock: from the start, or from the first shot (-1
## till then).
func wave_clock() -> float:
	if not from_shot:
		return clock
	return clock - roused if roused >= 0.0 else -1.0


## Seconds to the next wave, or -1 when there are no more (or none's begun counting).
func next_in() -> float:
	if next >= waves.size() or wave_clock() < 0.0:
		return -1.0
	return float(waves[next]["at"]) - wave_clock()


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


## All in: no wave still to come or still walking in, nobody still indoors.
func done() -> bool:
	return next >= waves.size() and queue.is_empty() and sleepers.is_empty()


## How many in the gang all told, those indoors included.
func indoors() -> int:
	return sleepers.size()


func _process(delta: float) -> void:
	if game.state != "play":
		return
	clock += delta
	_rouse()
	var wc := wave_clock()
	if next < waves.size() and wc >= 0.0:
		var w: Dictionary = waves[next]
		if w.get("rally", false) and rallied < next and next > 0 and wc >= float(waves[next - 1]["at"]) + RALLY_AFTER:
			rallied = next
			game.hud.banner("The enemy is rallying their troops outside the fort!")
			game.sfx("sting", null, -14.0, 0.0)
			game.stats["rallies"] = game.stats.get("rallies", 0) + 1
		if warned < next and wc >= float(w["at"]) - WARN:
			warned = next
			var names: Array = w["groups"].map(func(gr): return gr["from"])
			game.hud.banner("Men coming in by the %s!" % " and the ".join(names))
			game.sfx("sting", null, -12.0, 0.0)
			game.stats["waves warned"] = game.stats.get("waves warned", 0) + 1
		if wc >= float(w["at"]):
			_send(w)
			next += 1
	if not queue.is_empty() and game.alive_enemies() < CROWD:
		spawn_t -= delta
		if spawn_t <= 0.0:
			spawn_t = EVERY / maxf(1.0, _roads_in_queue())
			_walk_in(queue.pop_front())


## The first shot (or, for one who's done it all with the knife, everyone outside
## gone quiet for good) brings out those indoors.
func _rouse() -> void:
	if sleepers.is_empty() and not from_shot or roused >= 0.0:
		_wake()
		return
	if game.last_gunfire > -1e8:
		roused = clock
		game.stats["roused by"] = "the shooting"
	elif game.enemies.size() > 0 and game.alive_enemies() == 0:
		roused = clock
		quiet = true
		game.stats["roused by"] = "the quiet"
	if roused >= 0.0 and not sleepers.is_empty():
		game.hud.banner("¡Despierten, muchachos!  The garrison's waking!" if not quiet else "It's gone very quiet out there...")
	_wake()


## Out of the doors, each when he's ready.
func _wake() -> void:
	if roused < 0.0:
		return
	for i in range(sleepers.size() - 1, -1, -1):
		var sl: Dictionary = sleepers[i]
		if clock - roused < sl["delay"]:
			continue
		sleepers.remove_at(i)
		var at: Vector2 = sl["at"]
		if not game.is_free(at):
			at = game.free_point_near(at, 20.0)
		# out in a hurry with a pistol, the rifles left in the rack (all but the boss: his
		# own gun goes where he goes)
		var hurry := {} if game.enemy_type(sl["kind"]).get("boss", false) else {"pistols_only": true}
		var en: Enemy = game._add_enemy(sl["kind"], at, PackedVector2Array(), 90.0, hurry)
		game.stats["out of doors"] = game.stats.get("out of doors", 0) + 1
		if game.leaderless:
			en.lose_heart()
		if quiet:   # nobody about, and no answer: they go and look
			en.wary = true
			en.start_investigate(_center(), true)
		else:
			en.enter_combat(game.seen_pos if game.staleness() < 15.0 else game.last_gunfire_at, false, false)
		if rng.randf() < 0.4:
			en.say_line("spot", ["¡Vámonos!", "¿Qué pasa?", "¡A las armas!"] if sl["ready"] else ["¡Mis botas!", "¿Quién dispara?", "¡Ay, mi cabeza!"])


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
		var arms = gr.get("arms", w.get("arms", []))
		if arms is String:
			arms = arms_sets[arms]
		lines.append(kinds.map(func(k): return [entries[gr["from"]], k, arms]))
	var longest := 0
	for l in lines:
		longest = maxi(longest, l.size())
	for i in longest:
		for l in lines:
			if i < l.size():
				queue.append(l[i])
	spawn_t = 0.0
	game.stats["waves"] = game.stats.get("waves", 0) + 1


## One of the gang's sort: the map's own mix for its waves ("wave_kinds", by weight),
## or else the mix of the men already in town (those passing as townsfolk and the
## boss don't come marching in).
func _a_kind() -> String:
	var mix: Dictionary = game.level.get("wave_kinds", {})
	if not mix.is_empty():
		var total := 0.0
		for k in mix:
			total += float(mix[k])
		var r := rng.randf() * total
		for k in mix:
			r -= float(mix[k])
			if r <= 0.0:
				return k
		return mix.keys()[0]
	var pool: Array = game.level["enemies"].map(func(e): return e["kind"]).filter(
		func(k): return not (game.enemy_type(k).get("boss", false) or game.enemy_type(k).get("concealed", false)))
	if pool.is_empty():
		return "bandido"
	return pool[rng.randi_range(0, pool.size() - 1)]


func _walk_in(q: Array) -> void:
	var entry: Dictionary = q[0]
	var at: Vector2 = entry["at"]
	if not game.is_free(at):
		at = game.free_point_near(at, 30.0)
	var arms: Array = q[2]
	var en: Enemy = game._add_enemy(q[1], at, PackedVector2Array(), rad_to_deg((entry["into"] - entry["at"]).angle()),
		{} if arms.is_empty() else {"loadouts": arms})
	arrived += 1
	game.stats["arrivals"] = game.stats.get("arrivals", 0) + 1
	if game.leaderless:   # word on the road: their general's dead
		en.shaken = 0.7
		en.nerve *= 0.7
		game.stats["arrive headless"] = game.stats.get("arrive headless", 0) + 1
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
