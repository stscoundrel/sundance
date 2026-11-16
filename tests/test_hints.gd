extends SceneTree
## The first-time hints (game.firsts, hints.json's "first"), on a hints file of the
## test's own, in a quiet San Miguel:
##   once     - his first wound queues "hurt"; a second doesn't queue it again; it
##              shows low in the middle, and is kept as told in the file.
##   marks    - the first "?" over a man's head on screen queues "wary", the first
##              "!" "seen"; one at a time, each after the last has had its seconds.
##   down     - going down in the dirt jumps the queue.
##   kept     - a new sitting reads the file: nothing told is told again.
##   forget   - the picker's FORGET THE HINTS, asked twice, and he's told again.
##   godot --headless --path . --fixed-fps 60 -s tests/test_hints.gd

const FILE := "user://test_hints.json"

var game: Node
var frame := 0
var failures := 0
var step := ""
var phase := "once"
var mark_at := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_hanging", true)
	Engine.set_meta("no_reserve", true)
	Engine.set_meta("level", "san_miguel")
	Engine.set_meta("hints_file", FILE)
	if FileAccess.file_exists(FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	_load()


func _load() -> void:
	if game:
		game.queue_free()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	frame = 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _line(key: String) -> String:
	return game.hints["first"][key]


func _man() -> Enemy:
	for e in game.enemies:
		if e.alive and e.revealed:
			return e
	return null


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	if frame == 3:
		game.begin()
		return false
	var p: Player = game.player
	var f: Firsts = game.firsts
	match phase:
		"once":
			step = "once"
			check(f.told.is_empty(), "a new file should have told him nothing: %s" % [f.told])
			p.take_hit(1, Vector2.LEFT, _man())
			p.take_hit(1, Vector2.LEFT, _man())
			check(f.waiting == ["hurt"] or game.hud.hint_line == _line("hurt"), "his wound should queue the hint once: %s" % [f.waiting])
			phase = "shown"
		"shown":
			if game.hud.hint_line == _line("hurt"):
				check(f.told.has("hurt") and FileAccess.file_exists(FILE), "shown, but not kept as told")
				var e := _man()
				e.global_position = p.global_position + Vector2(60, 0)
				e.marker = "?"
				e.marker_t = 2.0
				phase = "marks"
				mark_at = frame
			elif frame > 30:
				check(false, "the wound's hint never showed")
				phase = "marks"
		"marks":
			step = "marks"
			if frame == mark_at + 3:
				check("wary" in f.waiting, "a '?' on screen should queue 'wary': %s" % [f.waiting])
				check(game.hud.hint_line == _line("hurt"), "one at a time: the wound's should still be up")
				var e := _man()
				e.marker = "!"
				e.marker_t = 2.0
			if frame == mark_at + 6:
				check(f.waiting == ["wary", "seen"], "a '!' should queue 'seen' behind: %s" % [f.waiting])
				step = "down"
				Engine.remove_meta("no_last_stand")
				p.take_hit(99, Vector2.LEFT, _man())
				check(p.down and f.waiting.front() == "down", "going down should jump the queue: %s" % [f.waiting])
				game.hud.hint_t = 0.01   # (staged: the wound's had its seconds)
			if frame == mark_at + 9:
				check(game.hud.hint_line == _line("down"), "the last stand's hint should be up next: '%s'" % game.hud.hint_line)
				phase = "kept"
				_load()
		"kept":
			step = "kept"
			if frame == 5:
				check(game.firsts.told.has("hurt") and game.firsts.told.has("down"), "the told hints should be read back: %s" % [game.firsts.told])
				p.take_hit(1, Vector2.LEFT, _man())
				check(not "hurt" in game.firsts.waiting, "told already, but queued again")
				step = "forget"
				game._to_levels()
				game.pick_level(game.levels.size() + 1)
				check(game.hints_armed and not game.firsts.told.is_empty(), "forgot them without asking twice")
				game.pick_level(game.levels.size() + 1)
				check(not game.hints_armed and game.firsts.told.is_empty() and not FileAccess.file_exists(FILE),
					"asked twice, still remembered")
				var r: Rect2 = game.hud._pick_rect(game.levels.size() + 1)
				check(game.hud.level_hit(r.get_center() + game.hud.menu_at()) == game.levels.size() + 1, "forgetting the hints should take a click")
				print("hints test: ", "OK" if failures == 0 else "%d failures" % failures)
				quit(1 if failures else 0)
				return true
	return false
