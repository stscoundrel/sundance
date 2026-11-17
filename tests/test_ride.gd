extends SceneTree
## Riding from town to town the way the player does, off the picker's keys (no
## townsfolk, nobody hanged, no partner at the well, no army on the roads):
##   ride     - from San Miguel, a number on the picker rides to every other town and
##              back: the old town goes, the new one comes up at its briefing, and the
##              key that picked it is taken (it once fell on a scene already gone).
##   sprites  - every sprite a town loads up front is a real file, and what they come to
##              in video memory is printed for each town (the budget to beat).
##   godot --headless --path . --fixed-fps 60 -s tests/test_ride.gd

const ORDER := ["cruz_verde", "train", "silencio", "funeral", "san_miguel"]

var game: Node
var frame := 0
var failures := 0
var step := "ride"
var leg := 0
var waited := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_hanging", true)
	Engine.set_meta("no_captive", true)
	Engine.set_meta("no_waves", true)
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
		check(game.level_entry["id"] == "san_miguel", "the game should open on San Miguel (%s)" % game.level_entry["id"])
		_sprites(game)
		_pick(ORDER[0])
		return false
	var g: Node = current_scene
	if g == game or g == null or not g.is_node_ready():
		waited += 1
		check(waited < 120, "the ride to %s never arrived" % ORDER[leg])
		if waited >= 120:
			return _done()
		return false
	check(not is_instance_valid(game) or not game.is_inside_tree(), "the town left behind is still standing")
	check(g.level_entry["id"] == ORDER[leg], "rode for %s, got %s" % [ORDER[leg], g.level_entry["id"]])
	check(g.state == "brief", "%s should open on its briefing (%s)" % [ORDER[leg], g.state])
	if leg < ORDER.size() - 1:
		_sprites(g)
	game = g
	waited = 0
	leg += 1
	if leg == ORDER.size():
		return _done()
	_pick(ORDER[leg])
	return false


## Number `id` on the picker pressed, as a player would press it.
func _pick(id: String) -> void:
	step = "ride"
	game._to_levels()
	var i: int = game.levels.map(func(l): return l["id"]).find(id)
	check(i >= 0, "%s isn't on the picker" % id)
	var ev := InputEventKey.new()
	ev.keycode = KEY_1 + i
	ev.physical_keycode = KEY_1 + i
	ev.pressed = true
	root.push_input(ev)
	check(root.is_input_handled(), "the key that rode to %s wasn't taken" % id)


func _sprites(g: Node) -> void:
	step = "sprites"
	var paths: Array[String] = g.sprite_paths()
	var bytes := 0
	for p in paths:
		check(FileAccess.file_exists(p), "%s loads %s, which isn't there" % [g.level_entry["id"], p])
		bytes += _gpu_bytes(p)
	print("%-12s %d sprites, %.0f MB in video memory" % [g.level_entry["id"], paths.size(), bytes / 1e6])
	step = "ride"


## What a PNG comes to on the card, from its header: width x height x the bytes a
## pixel of its kind takes there. Colour is 3 and colour with alpha 4; grey is 4 too,
## since the Compatibility renderer widens the grey slot sheets on the card (counted
## so, San Miguel's 3.9 GB is a shade over the 3.6 GB a window measures: the safe side).
func _gpu_bytes(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	f.big_endian = true
	f.seek(16)
	var w := f.get_32()
	var h := f.get_32()
	f.get_8()
	var kind := f.get_8()
	var px: int = {0: 4, 4: 4, 2: 3, 6: 4}.get(kind, 4)
	return w * h * px


func _done() -> bool:
	print("ride test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
