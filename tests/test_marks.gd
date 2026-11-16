extends SceneTree
## The arrows to what a town asks of him (game.marks, hud._draw_marks):
##   fade     - none before a second in, full in the opening, gone at nine seconds;
##              full whenever Tab's held.
##   gallows  - San Miguel points to the gallows, till the man on them is saved.
##   partner  - Cruz Verde points to his partner at the well, till he's cut loose.
##   carriers - Paso Esperanza points to the carriers, till it's all loaded (the
##              wagon has its own arrow then).
##   gold     - Silencio points to the gold and his horse; with the gold in his arms,
##              only to the horse.
##   godot --headless --path . --fixed-fps 60 -s tests/test_marks.gd

const LEVELS := ["san_miguel", "cruz_verde", "train", "silencio"]

var game: Node
var frame := 0
var failures := 0
var step := ""
var at := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_reserve", true)
	_load(LEVELS[0])


func _load(id: String) -> void:
	if game:
		game.queue_free()
	Engine.set_meta("level", id)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	frame = 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _names() -> Array:
	return game.marks().map(func(m): return m[1])


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	if frame == 3:
		game.begin()
		return false
	if frame < 5:
		return false
	match LEVELS[at]:
		"san_miguel":
			step = "fade"
			var h: Node = game.hud
			check(h.marks_alpha(0.5, false) == 0.0, "arrows before a second in")
			check(h.marks_alpha(5.0, false) == 1.0, "no arrows in the opening")
			check(h.marks_alpha(8.5, false) > 0.0 and h.marks_alpha(8.5, false) < 1.0, "the arrows should be fading at 8.5 s")
			check(h.marks_alpha(9.0, false) == 0.0, "arrows past the opening")
			check(h.marks_alpha(120.0, true) == 1.0, "Tab should bring them back")
			step = "gallows"
			check(_names() == ["THE GALLOWS"], "San Miguel's arrows: %s" % [_names()])
			check(game.marks()[0][0] == game.hanging.trap, "the arrow isn't on the gallows")
			game.hanging.state = "freed"
			check(_names().is_empty(), "still pointing at the gallows with the man saved: %s" % [_names()])
		"cruz_verde":
			step = "partner"
			check(_names() == ["YOUR PARTNER"], "Cruz Verde's arrows: %s" % [_names()])
			check(game.marks()[0][0] == game.captive.man.global_position, "the arrow isn't on his partner")
			game.captive.state = "freed"
			check(_names().is_empty(), "still pointing at him once he's loose: %s" % [_names()])
		"train":
			step = "carriers"
			check(_names() == ["THE CARRIERS"], "Paso Esperanza's arrows: %s" % [_names()])
			game.cargo.done = true
			check(_names().is_empty(), "still pointing at the carriers with it all loaded: %s" % [_names()])
		"silencio":
			step = "gold"
			check(_names() == ["THE GOLD", "YOUR HORSE"], "Silencio's arrows: %s" % [_names()])
			game.strongbox.take(game.player)
			check(_names() == ["YOUR HORSE"], "with the gold in his arms, only the horse: %s" % [_names()])
	at += 1
	if at < LEVELS.size():
		_load(LEVELS[at])
		return false
	print("marks test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
