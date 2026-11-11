extends SceneTree
## The guests' long guns at the funeral (A Good Man Never Dies; see Arms):
##   pistols  - every guest has only his pistol on him; whoever owns a long gun has
##              it left in a saddle or a wagon (stowed), the places to fetch it from
##              written on the map (a saddle on every horse, every wagon, the rack).
##   his      - by a saddle the stranger is offered its gun (F): it's his, loaded and
##              nothing spare, and that saddle's empty after.
##   flee     - two of them shot down in a breath, in front of the others: some run
##              for their long guns (never to a place by the stranger), and one comes
##              back with his in his hands, his pistol behind it, to fight.
##   shaken   - a round in a man struck dumb snaps him out of it; the run for a long
##              gun has a limit (a way through to it may be blocked).
##   battle   - three dead: everyone in the fight has thought about his long gun.
##   godot --headless --path . --fixed-fps 60 -s tests/test_arms.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var phase := 0
var t0 := 0.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "funeral")
	Engine.set_meta("no_coffin", true)
	Engine.set_meta("no_downed", true)
	Engine.set_meta("no_gasp", true)
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		_pistols()
		game._to_loadout()
		game.player.hp = 1000000   # (he stands about for the test)
	if frame <= 3:
		return false
	t += delta
	match phase:
		0:
			if t < 3.0:
				return false
			_his()
			_shaken_out()
			_shoot_two()
			t0 = t
			phase = 1
		1:   # someone runs for his gun, gets it, and comes back to fight with it
			var armed: Array = game.enemies.filter(func(e): return e.alive and not e.weapon.kind in Enemy.PISTOLS)
			if armed.is_empty() and t - t0 < 30.0:
				return false
			step = "flee"
			check(game.stats.get("flees", 0) >= 1, "nobody ran for his gun: %s" % game.stats.get("flees", 0))
			check(not armed.is_empty(), "nobody came back with a long gun")
			if not armed.is_empty():
				var e: Enemy = armed[0]
				check(e.loadout.size() >= 2 and e.loadout[1] in Enemy.PISTOLS and e.stowed == "", "armed wrong: %s" % [e.loadout])
				check(e.reaction == "" and e.st == Enemy.St.COMBAT, "armed, but not fighting: %s %s" % [e.reaction, Enemy.St.keys()[e.st]])
			step = "battle"
			var third: Array = game.enemies.filter(func(e): return e.alive and e.reaction != "arm")
			third[0].take_hit(1000, Vector2.RIGHT, game.player)   # (the third: it's a battle now)
			check(game.enemies.filter(func(e): return e.alive and e.st == Enemy.St.COMBAT and e.stowed != "" and e.reaction != "agape").all(func(e): return e.arm_rolled),
				"a man in the fight never thought of his long gun")
			print("arms test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
			quit(failures)
			return true
	return false


func _pistols() -> void:
	step = "pistols"
	check(game.enemies.all(func(e): return e.weapon.kind in Enemy.PISTOLS and e.loadout.all(func(g): return g in Enemy.PISTOLS)),
		"a guest wears a long gun: %s" % [game.enemies.filter(func(e): return not e.weapon.kind in Enemy.PISTOLS).map(func(e): return e.kind)])
	var by_kind := {}
	for e in game.enemies:
		by_kind[e.kind] = e.stowed
	check(by_kind.get("manhunter", "") != "" and by_kind.get("soldado", "") != "" and by_kind.get("cowboy", "x") == "",
		"what they left with the horses: %s" % by_kind)
	check(game.arms != null and game.arms.places.size() >= 30, "places for their long guns: %s" % (game.arms.places.size() if game.arms else 0))
	var kinds := {}
	for p in game.arms.places:
		kinds[p["kind"]] = kinds.get(p["kind"], 0) + 1
	check(kinds.get("saddle", 0) >= 15 and kinds.get("wagon", 0) >= 10 and kinds.get("rack", 0) == 1, "saddles, wagons, rack: %s" % kinds)


func _his() -> void:
	step = "his"
	var p: Player = game.player
	var place: Dictionary = game.arms.places[0]
	p.global_position = place["at"]
	game._pick_up_guns()
	check(game.at_feet.has("place"), "no gun offered by the saddle")
	var k: String = game.at_feet.get("kind", "")
	game.swap_gun()
	check(Player.SLOT.get(k, "") in p.owned and p.weapons[Player.SLOT[k]].kind == k, "he didn't get the %s" % k)
	if Player.SLOT.get(k, "") in p.owned:
		var w: Weapon = p.weapons[Player.SLOT[k]]
		check(w.reserve == 0 and w.loaded() > 0, "%s: %d loaded, %d spare" % [k, w.loaded(), w.reserve])
	check(place["offer"].is_empty() and game.arms.offer(place["at"]).is_empty(), "the saddle still has a gun in it")
	p.global_position = Iso.to_screen(Vector2(32.0, 40.0))   # (back by the grave, in sight of them all)


## A man struck dumb and shot is out of it at once; a man running for his long gun
## gives it up if it takes too long.
func _shaken_out() -> void:
	step = "shaken out"
	var e: Enemy = game.enemies.filter(func(o): return o.kind == "cowboy")[0]
	e.agape(game.player.global_position, 3.0, Enemy.wake_rng)
	e.take_hit(1, Vector2.RIGHT, game.player)
	check(e.alive and e.reaction == "agape" and e.reaction_t <= 0.0, "a round in him and he's still staring: %s %.1f" % [e.reaction, e.reaction_t])
	var r: Enemy = game.enemies.filter(func(o): return o.kind == "rural")[0]
	r.go_arm("test")
	check(r.reaction == "arm" and r.reaction_t <= Enemy.ARM_LIMIT, "no limit on the run for his gun: %s %.1f" % [r.reaction, r.reaction_t])


## Two of the mourners shot down together, the rest looking on.
func _shoot_two() -> void:
	step = "flee"
	var ms: Array = game.enemies.filter(func(e): return e.tdata.get("mourning", false))
	for i in 2:
		ms[i].take_hit(1000, Vector2.RIGHT, game.player)
	check(game.recent_deaths(Enemy.RAPID) == 2, "two dead: %d" % game.recent_deaths(Enemy.RAPID))
	for e in game.enemies:
		if e.reaction == "arm":
			check(e.arm_at.distance_to(game.player.global_position) > Arms.NEAR_HIM, "%s runs for a gun by the stranger" % e.kind)
