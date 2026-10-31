extends SceneTree
## Corner watching. The stranger hides in the alley between the hotel and the bank
## and keeps stepping out to the street mouth to fire at four cowboys across main
## street (shots up the alley: heard, but nothing whistles past them; they can't
## die, nor can he). Nobody watches the mouth until he's come out there twice;
## then a watcher or two holds his gun on it (no more than two, and the others
## keep moving), and whenever one is in place as he steps out, he's met almost at
## once. A peek from somewhere new has nobody ready for it.
## Spots are loose: two corners of one house are one spot, across the street isn't.
##   godot --headless --path . --fixed-fps 60 -s tests/test_corners.gd

const HIDE := Vector2(35.5, 22.8)    # in the alley, out of sight of the street
const MOUTH := Vector2(35.5, 28.9)   # the alley mouth on main street
const ELSEWHERE := Vector2(46.0, 30.6)
const GANG := [Vector2(30.0, 34.0), Vector2(33.0, 35.2), Vector2(38.5, 35.0), Vector2(41.0, 34.0)]
const OUT := 1.0     # s out in the open each peek
const IN := 4.0      # s hidden between peeks
const PEEKS := 7     # at the mouth; then one somewhere new

var game: Node
var frame := 0
var failures := 0
var gang: Array[Enemy] = []
var peek := -1
var out_t := -1.0    # time out on this peek; < 0 while hidden
var in_t := 0.0
var latency: Array[float] = []
var watched: Array[bool] = []   # was someone watching the mouth as he stepped out
var first_watch_peek := -1
var ready_before_new := 0
var answered := false
var most_watchers := 0
var moving_while_watched := false


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_reserve", true)
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _spot_rules() -> void:
	var a := Iso.to_screen(Vector2(30.0, 20.0))
	game.clock = 100.0
	game._note_fire(a)
	game.clock = 104.0
	game._note_fire(a + Vector2(62, 8))      # the other corner of the same house
	game.clock = 104.2
	game._note_fire(a + Vector2(62, 8))      # same peek: a second shot
	check(game.fire_spots.size() == 1, "two corners of one house should be one spot (%d)" % game.fire_spots.size())
	check(game.fire_spots[0]["peeks"] == 2, "two peeks, however many shots (%d)" % game.fire_spots[0]["peeks"])
	game.clock = 108.0
	game._note_fire(a + Vector2(0, 240))     # across the street
	check(game.fire_spots.size() == 2, "a spot across the street is another spot (%d)" % game.fire_spots.size())
	game.fire_spots.clear()
	game.clock = 0.0


func _process(delta: float) -> bool:
	frame += 1
	var p: Player = game.player
	if frame == 3:
		game.begin()
		_spot_rules()
		p.hp = 1000000
		p.process_mode = Node.PROCESS_MODE_DISABLED
		p.global_position = Iso.to_screen(HIDE)
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			e.global_position += Vector2(0, -3000)   # everyone else out of town
		for i in GANG.size():
			for e in game.enemies:
				if e.kind == "cowboy" and not e in gang:
					gang.append(e)
					e.global_position = Iso.to_screen(GANG[i])
					e.hp = 100000
					e.process_mode = Node.PROCESS_MODE_INHERIT
					break
		for e in gang:
			check(not game.line_of_sight(e.global_position, Iso.to_screen(HIDE), false), "the hiding place can be seen")
		var see := gang.filter(func(e): return game.line_of_sight(e.global_position, Iso.to_screen(MOUTH), false)).size()
		check(see >= 2, "the alley mouth should be in view of the gang (%d)" % see)
		for e in gang:
			e.enter_combat(Iso.to_screen(MOUTH), false, false)
	if frame <= 3:
		return false
	p.weapon.update(delta)
	var watchers := gang.filter(func(e): return e.watch_at != Vector2.INF).size()
	if watchers > 0 and first_watch_peek < 0:
		first_watch_peek = peek
	most_watchers = maxi(most_watchers, watchers)
	if watchers > 0 and gang.any(func(e): return e.watch_at == Vector2.INF and e.velocity.length() > 5.0):
		moving_while_watched = true
	if out_t < 0.0:
		in_t += delta
		if in_t < IN:
			return false
		# out he steps
		peek += 1
		if peek > PEEKS:
			return _report()
		var at := Iso.to_screen(MOUTH if peek < PEEKS else ELSEWHERE)
		watched.append(gang.any(func(e): return e.watch_at != Vector2.INF and e.watch_at.distance_to(at) < 45.0))
		if peek == PEEKS:
			ready_before_new = game.stats.get("was ready for him", 0)
		p.global_position = at
		out_t = 0.0
		answered = false
		return false
	out_t += delta
	if out_t > 0.15 and out_t - delta <= 0.15:
		# a shot up the alley: heard and marked like any other, but no near misses
		# for them to flinch at (that's another test's business)
		p.facing = Vector2.UP
		p.weapon.trigger()
	if not answered:
		for e in gang:
			if e.since_shot < delta * 0.5 and e.sees_player:
				answered = true
				latency.append(out_t)
				break
	if out_t >= OUT:
		if not answered:
			latency.append(OUT)   # nobody got a shot off
		p.global_position = Iso.to_screen(HIDE)
		out_t = -1.0
		in_t = 0.0
	return false


func _report() -> bool:
	print("first shot at him, per peek (s): %s  (last one somewhere new)" % [latency.map(func(x): return snappedf(x, 0.01))])
	print("watched as he stepped out:        %s" % [watched])
	print("first watcher during peek %d; most at once %d; others kept moving: %s; %s" % [first_watch_peek, most_watchers,
		moving_while_watched, game.stats])
	check(first_watch_peek >= game.SPOT_HOT - 1, "they watched before he'd peeked there twice (peek %d)" % first_watch_peek)
	check(most_watchers <= game.WATCHERS, "too many watched one corner (%d)" % most_watchers)
	check(moving_while_watched, "while some watched, the rest should keep moving")
	var n := 0
	var quick := 0
	for i in PEEKS:
		if watched[i]:
			n += 1
			quick += 1 if latency[i] <= 0.25 else 0
	check(n >= 2, "a watcher should be in place for most later peeks (%d of %d)" % [n, PEEKS - game.SPOT_HOT])
	check(quick >= n - 1, "a watched corner should be met almost at once (%d of %d within 0.25 s)" % [quick, n])
	check(not watched[PEEKS], "someone was already watching the new spot")
	check(game.stats.get("was ready for him", 0) == ready_before_new, "a watcher was ready for him somewhere new")
	print("corners test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
