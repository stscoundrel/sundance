extends SceneTree
## The loadout's points. Each gun costs by how good it is (the horse pistol and the
## escopeta nothing, the Winchester 4) and kit too (a bandage 1, a stick 2), out of
## the level's budget. A gun he can't afford stays where it is: a click on it, or
## going on through the slot with 1 2 3, passes it by. A choice kept from a richer
## level gives back its dearest first. He rides in with the kit he bought, and none
## he didn't, a stick in any town:
##   godot --headless --path . --fixed-fps 60 -s tests/test_budget.gd

var game: Node
var frame := 0
var failures := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("level", "cruz_verde")
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


func _click(k: String) -> void:
	var i := Player.ORDER.find(Player.SLOT[k])
	var at: Vector2 = game.hud._option(i, Player.choices(Player.SLOT[k]).find(k)).get_center()
	game._loadout_pick(game.hud.loadout_hit(at))


func _process(_delta: float) -> bool:
	frame += 1
	var p: Player = game.player
	if frame == 3:
		check(Player.cost(["colt"]) == Player.cost(["schofield"]), "the Colt and the Schofield should cost the same")
		check(Player.cost(["pistola"]) == 0 and Player.cost(["escopeta"]) == 0, "junk should be free")
		check(Player.cost(["rifle"]) == 4 and Player.cost(["coach"]) == 3 and Player.cost(["sawnoff"]) == 2,
			"the Winchester 4, the coach gun 3, the sawn-off 2")
		for k in Player.SLOT:
			check(Weapon.DATA[k].has("points"), "%s has no price" % k)
		check(game.budget() == 12, "with no budget named, 12 (%d)" % game.budget())
		check(Player.cost(["colt", "coach", "rifle"], ["bandage", "dynamite"]) <= game.budget(),
			"the default budget should buy everything")
		check(game.kit_offered() == ["bandage", "dynamite"], "Cruz Verde sells both (%s)" % [game.kit_offered()])

		# a poorer level: 6 points
		game.level_entry["budget"] = 6
		game.picked.assign(["colt", "coach", "rifle"])
		game.kit.assign(["bandage", "dynamite"])
		game._to_loadout()
		check(game.spent() <= 6, "a kept choice over budget should be trimmed (%d)" % game.spent())
		check(game.picked == ["colt"] and game.kit == ["bandage", "dynamite"],
			"the Winchester, then the coach gun, should go first (%s %s)" % [game.picked, game.kit])
		_click("rifle")
		check(not "rifle" in game.picked, "the Winchester is too dear with 1 point left")
		_click("springfield")
		check("springfield" in game.picked and game.spent() == 6, "the Springfield should fit (%s)" % [game.picked])
		_key(KEY_G)
		check(game.kit == ["bandage"], "G gives the stick back (%s)" % [game.kit])
		_key(KEY_2)
		check(game.picked_for("coach") == "sawnoff", "2 should pass the coach gun by, to the sawn-off (%s)" % [game.picked])
		_key(KEY_G)
		check(game.kit == ["bandage"], "no points left for a stick (%s)" % [game.kit])
		_key(KEY_3)
		check(game.picked_for("rifle") == "", "3 goes on from the Springfield to none (%s)" % [game.picked])
		_key(KEY_3)
		check(game.picked_for("rifle") == "springfield", "and passes the Winchester and the Spencer by (%s)" % [game.picked])
		_key(KEY_1)
		check(game.picked_for("colt") == "schofield", "a Colt for a Schofield is even (%s)" % [game.picked])
		_key(KEY_ENTER)
		check(game.state == "play", "Enter should ride in")
		check(p.bandages == 1 and p.sticks == 0, "he should ride in with what he bought (%d %d)" % [p.bandages, p.sticks])
		check(p.weapons["coach"].kind == "sawnoff", "and the sawn-off")
	if frame == 6:
		# the kit he didn't buy, he hasn't
		game.state = "loadout"
		game.kit.assign([])
		game._ride_in()
		check(p.bandages == 0 and p.sticks == 0, "kit he didn't buy shouldn't come (%d %d)" % [p.bandages, p.sticks])
		# a level with no dynamite of its own still sells a stick
		game.level_entry.erase("dynamite")
		game.kit.assign(["bandage", "dynamite"])
		check(game.kit_offered() == ["bandage", "dynamite"], "a stick should be on sale anywhere")
		game.state = "loadout"
		game._ride_in()
		check(p.sticks == 1, "the stick he bought should come")
		print("budget test: ", "OK" if failures == 0 else "%d FAILED" % failures)
		quit(failures)
	return false
