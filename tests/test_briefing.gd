extends SceneTree
## The briefing card between the picker and the guns (no townsfolk, no hanging):
##   card     - every town on the picker has a story, a job and two to four rows of who's
##              who; the story fits in three lines, each row's line in two, and every man
##              named is a real type standing whole on the card (legs and upper body).
##   flow     - the card comes up, holds its men, and goes with them on to the guns; a
##              town with nothing to tell (the test yard) goes straight to the guns.
##   godot --headless --path . --fixed-fps 60 -s tests/test_briefing.gd

var game: Node
var frame := 0
var failures := 0
var step := ""


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_hanging", true)
	Engine.set_meta("level", "san_miguel")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	if frame == 3:
		_card()
		step = "flow"
		game._to_brief()
		check(game.state == "brief", "San Miguel should be told first (%s)" % game.state)
		return false
	if frame == 5:
		var b: Dictionary = game.level_entry["brief"]
		var n := 0
		for row in b["who"]:
			n += row["kinds"].size()
		check(game.hud.stills.size() == n, "the card should stand %d men, not %d" % [n, game.hud.stills.size()])
		for man in game.hud.stills:
			check(man.get_child_count() == 2, "a man on the card should be whole (%d parts)" % man.get_child_count())
		game._to_loadout()
		return false
	if frame == 7:
		check(game.state == "loadout" and game.hud.stills.is_empty(), "the men should go with the card (%d left)" % game.hud.stills.size())
		var all: Array = game._load_json(game.LEVELS_PATH)["levels"]
		game.level_entry = all.filter(func(l): return l["id"] == "test_yard")[0]
		game._to_brief()
		check(game.state == "loadout", "a town with nothing to tell should go straight to the guns (%s)" % game.state)
		print("briefing test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	return false


## Every town's card: what it says fits, and whoever it names is a type with a body.
func _card() -> void:
	step = "card"
	var hud: Node = game.hud
	for l in game.levels:
		var b: Dictionary = l.get("brief", {})
		var id: String = l["id"]
		check(b.get("story", "") != "", "%s has no story" % id)
		check(hud.wrapped(b.get("story", ""), hud.STORY_W, 9).size() <= 3, "%s's story runs past three lines" % id)
		var who: Array = b.get("who", [])
		check(who.size() >= 2 and who.size() <= 4, "%s has %d rows of who's who" % [id, who.size()])
		for i in who.size():
			var row: Dictionary = who[i]
			var r: Rect2 = hud._brief_row(i)
			var x: float = r.position.x + 12 + hud.STILL_W * row["kinds"].size()
			check(hud.wrapped(row["line"], r.end.x - x - 10, 8).size() <= 2, "%s: %s's line runs past two lines" % [id, row["name"]])
			check(r.end.y <= 330.0, "%s: %s's row runs into the foot of the page" % [id, row["name"]])
			for k in row["kinds"]:
				var known: bool = game.enemy_data["types"].has(k) or game.enemy_data["civilians"]["types"].has(k)
				check(known, "%s: no such type as %s" % [id, k])
