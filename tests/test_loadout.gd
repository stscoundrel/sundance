extends SceneTree
## The loadout screen and picking guns up. From the title the stranger chooses his
## guns (one a slot, at least one: 1 2 3 go through a slot's guns, a click on a
## name takes it); he rides in with only those and can't
## switch to the other. Cartridges for it still go in his belt. Walking over that gun
## lying in the dirt makes it his (part-spent, as a dead man left it); a gun he
## already has, one for a slot he's filled (a sawn-off: a swap he has to mean, F),
## or one he can't use yet (a Sharps), stays where it lies:
##   godot --headless --path . --fixed-fps 60 -s tests/test_loadout.gd

var game: Node
var frame := 0
var failures := 0
var at := Vector2.ZERO
var coach: Dictionary
var colt: Dictionary
var sawn: Dictionary
var sharps: Dictionary


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	Engine.set_meta("no_civilians", true)
	seed(1)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	game._loadout_input(e)


## A click on a gun's name on the loadout screen.
func _click(k: String) -> void:
	var i := Player.ORDER.find(Player.SLOT[k])
	var at: Vector2 = game.hud._option(i, Player.choices(Player.SLOT[k]).find(k)).get_center()
	game._loadout_pick(game.hud.loadout_hit(at))


func _process(_delta: float) -> bool:
	frame += 1
	var p: Player = game.player
	if frame == 3:
		game.level_entry["budget"] = 20   # (points enough for any choice: test_budget has the prices)
		game.picked.assign(["colt", "coach"])
		game._to_loadout()
		check(game.state == "loadout", "the title should lead to the loadout screen")
		_key(KEY_3)
		check(game.picked == ["colt", "coach", "rifle"], "all three should go (%s)" % [game.picked])
		_key(KEY_2)
		check(game.picked == ["colt", "champion", "rifle"], "2 should go on to the Champion, in the coach gun's place (%s)" % [game.picked])
		_key(KEY_2)
		check(game.picked == ["colt", "sawnoff", "rifle"], "and on to the sawn-off (%s)" % [game.picked])
		_key(KEY_2)
		check(game.picked == ["colt", "escopeta", "rifle"], "and on to the escopeta (%s)" % [game.picked])
		_key(KEY_2)
		check(game.picked == ["colt", "rifle"], "and then to no shotgun at all (%s)" % [game.picked])
		_key(KEY_1)
		check(game.picked == ["schofield", "rifle"], "1 should go on from the Colt to the Schofield (%s)" % [game.picked])
		for i in 5:
			_key(KEY_1)
		check(game.picked == ["pistola", "rifle"], "and on through the Walker, the Navy, the howdah and the derringer to the horse pistol (%s)" % [game.picked])
		_click("spencer")
		_click("colt")
		check(game.picked == ["colt", "spencer"], "a click on a gun's name should take it for its slot (%s)" % [game.picked])
		p.arm(game.picked)
		check(p.weapons["rifle"].kind == "spencer" and p.weapons["rifle"].reserve == Player.RESERVE["spencer"],
			"riding in with a Spencer, he hasn't one, or its rounds")
		_click("spencer")
		_key(KEY_3)
		_key(KEY_ENTER)
		check(game.state == "play", "Enter should ride in")
		check(p.owned == ["colt", "rifle"], "he should ride in with the two he picked (%s)" % [p.owned])
		p.switch_to("coach")
		check(p.current != "coach", "he switched to a gun he hasn't got")
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
		at = Iso.to_screen(Vector2(26.0, 31.4))
		p.global_position = at
		# cartridges for the coach gun go in his belt all the same
		var before: int = p.weapons["coach"].reserve
		var shells := Pickup.new()
		shells.setup(game, at, "coach")
		game.world.add_child(shells)
		p.global_position = at + Vector2(0, 1)
		# guns lying further down the street
		coach = game._place_gun("coach", at + Vector2(60, 0), 0.0)
		colt = game._place_gun("colt", at + Vector2(90, 0), 0.0)
		sawn = game._place_gun("sawnoff", at + Vector2(120, 0), 0.0)
		sharps = game._place_gun("sharps", at + Vector2(150, 0), 0.0)
		set_meta("before", before)
	if frame <= 3:
		return false
	if frame == 10:
		check(p.weapons["coach"].reserve > get_meta("before"), "coach shells should go in his belt without the gun")
	# he walks down the street over all three
	if frame > 10 and frame < 200:
		p.global_position = at + Vector2(float(frame - 10), 0)
	if frame == 200:
		check("coach" in p.owned, "walking over the coach gun should make it his")
		check(not game.loose_guns.has(coach), "the coach gun is still lying there")
		check(p.weapons["coach"].reserve > 0, "the shells he'd picked up should be his to load it with")
		check(game.loose_guns.has(colt), "he picked up a Colt he already had")
		check(game.loose_guns.has(sawn) and p.weapons["coach"].kind == "coach", "walked over the sawn-off and it swapped without F")
		check(game.loose_guns.has(sharps), "he picked up a Sharps (not his to use yet)")
		check(game.hud.toast_text.contains("COACH"), "no word that he picked it up (%s)" % game.hud.toast_text)
		p.switch_to("coach")
		check(p.current == "coach", "he can't switch to the coach gun he picked up")
		print("owned %s, coach loaded %d, reserve %d" % [p.owned, p.weapon.loaded(), p.weapon.reserve])
		print("loadout test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	return false
