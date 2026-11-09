extends SceneTree
## Getting about between the towns (no townsfolk, no hanging):
##   esc      - Esc goes back a step: the title to the picker, the guns to the picker,
##              the picker to its way out of the game (Enter on it leaves); in town it
##              brings up the menu, the town paused under it (game time stands still),
##              and Esc again lets it go on.
##   budgets  - each town gives its own points: Silencio the fewest, Paso Esperanza
##              the most; the picker shows them.
##   onward   - a town won is marked on the picker, and Enter (or the menu's "ride on")
##              rides on to the next one, at the guns; the last has none to ride on to.
##   retry    - a town lost: Enter goes straight back to its guns, the slow-motion gone.
##   godot --headless --path . --fixed-fps 60 -s tests/test_menu.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var phase := "start"
var waited := 0
var clock_at := 0.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_hanging", true)
	Engine.set_meta("no_captive", true)
	Engine.set_meta("level", "san_miguel")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	return e


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	match phase:
		"start":
			_esc()
			_budgets()
			game._ride_in()
			game.open_menu()
			clock_at = game.clock
			phase = "paused"
			waited = 0
		"paused":
			waited += 1
			if waited < 20:
				return false
			step = "esc"
			check(paused and game.clock == clock_at, "the town should stand still under the menu (%.2f, %.2f)" % [clock_at, game.clock])
			game.menu_input(_key(KEY_ESCAPE))
			check(not paused and game.menu.is_empty(), "Esc again should let the town go on")
			phase = "running"
			waited = 0
		"running":
			waited += 1
			if waited < 20:
				return false
			check(game.clock > clock_at, "the town should go on after the menu (%.2f)" % game.clock)
			_onward()
			phase = "to cruz verde"
			waited = 0
		"to cruz verde":
			if not _arrived("cruz_verde"):
				return false
			step = "onward"
			check(game.ridden.has("san_miguel"), "San Miguel won, but not marked on the picker")
			game._ride_in()
			game.end_level(false, "THE CAPTIVE IS DEAD")
			step = "retry"
			check(game.state == "lost" and game.hud.hint.contains("again"), "a loss should offer the town again (%s)" % game.hud.hint)
			game._unhandled_input(_key(KEY_ENTER))
			phase = "again"
			waited = 0
		"again":
			if not _arrived("cruz_verde"):
				return false
			check(Engine.time_scale == 1.0, "the loss's slow-motion should be gone (%.2f)" % Engine.time_scale)
			print("menu test: ", "OK" if failures == 0 else "%d failures" % failures)
			quit(1 if failures else 0)
			return true
	return false


## Whether the scene has come back up with town `id`, at the guns (a limit on the wait).
func _arrived(id: String) -> bool:
	waited += 1
	var g: Node = current_scene
	if g != game and g != null and g.is_node_ready() and g.state == "loadout":
		game = g
		check(g.level_entry["id"] == id, "rode on to %s, not %s" % [g.level_entry["id"], id])
		check(not paused, "the new town shouldn't come up paused")
		return true
	if waited > 120:
		check(false, "no %s loadout after %d frames (%s)" % [id, waited, g.state if g else "no scene"])
		quit(1)
	return false


func _esc() -> void:
	step = "esc"
	check(game.state == "title", "starts at %s" % game.state)
	game._unhandled_input(_key(KEY_ESCAPE))
	check(game.state == "levels", "Esc on the title should go to the picker (%s)" % game.state)
	game._unhandled_input(_key(KEY_ESCAPE))
	check(game.state == "levels" and game.level_pick == game.levels.size(),
		"Esc on the picker should go to its way out (%d)" % game.level_pick)
	var out: Rect2 = game.hud._row(game.levels.size())
	check(game.hud.level_hit(out.get_center() + game.hud.menu_at()) == game.levels.size(), "the way out should take a click")
	game.pick_level(0)   # (the town already loaded: on to the guns)
	check(game.state == "loadout", "picking San Miguel should go on to the guns (%s)" % game.state)
	game._unhandled_input(_key(KEY_ESCAPE))
	check(game.state == "levels", "Esc on the guns should go back to the picker (%s)" % game.state)
	game.pick_level(0)
	game._ride_in()
	check(game.state == "play", "he should ride in (%s)" % game.state)
	game._unhandled_input(_key(KEY_ESCAPE))
	check(not game.menu.is_empty() and paused, "Esc in town should bring the menu up, paused")
	check(game.menu == ["resume", "again", "levels", "quit"], "the menu in town: %s" % [game.menu])
	game.menu_input(_key(KEY_ESCAPE))
	check(game.menu.is_empty() and not paused, "Esc should close it")


func _budgets() -> void:
	step = "budgets"
	var b := {}
	for l in game.levels:
		b[l["id"]] = int(l.get("budget", game.BUDGET))
	check(b["silencio"] < b["san_miguel"] and b["san_miguel"] < b["cruz_verde"] and b["cruz_verde"] < b["train"],
		"the towns' points should run Silencio, San Miguel, Cruz Verde, Paso Esperanza (%s)" % [b])
	check(game.budget() == b["san_miguel"], "San Miguel's loadout gives %d" % game.budget())


func _onward() -> void:
	step = "onward"
	check(game.next_level()["id"] == "cruz_verde", "after San Miguel, Cruz Verde (%s)" % [game.next_level()])
	var last: Dictionary = game.level_entry
	game.level_entry = game.levels[-1]
	check(game.next_level().is_empty(), "Silencio is the last")
	game.level_entry = last
	game.end_level(true, "THE TOWN IS QUIET")
	check(game.state == "won" and game.hud.hint.contains("Cruz Verde"), "the win should offer Cruz Verde (%s)" % game.hud.hint)
	game.open_menu()
	check(game.menu == ["resume", "next", "again", "levels", "quit"], "the menu after a win: %s" % [game.menu])
	Engine.remove_meta("level")
	game.menu_choose("next")
