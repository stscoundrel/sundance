extends SceneTree
## Silencio, the snowbound town (phase 1: the place, San Miguel's gang standing in):
##   map    - the town's things wear their snow (every object with a snow skin is
##            drawn from it, and a crate shot up stays snowed on); the frozen pond
##            lies at the map's edge, holes cut in it; the gang's there, nobody else;
##            snow's falling, and the light's cold and flat under the cloud.
##   ways   - from his horse down the south trail the stranger can get to the
##            outlaws' hideout, the jail at the hunters' end, the saloon, the
##            church, out onto the ice, and to both ends of main street.
##   quiet  - left alone a while, nothing ends it.
##   godot --headless --path . --fixed-fps 60 -s tests/test_silencio.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var _flake0 := Vector4.ZERO


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "silencio")
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _reaches(a: Vector2, b: Vector2) -> bool:
	var path: PackedVector2Array = game.find_path(Iso.to_screen(a), Iso.to_screen(b))
	return path.size() > 0 and path[path.size() - 1].distance_to(Iso.to_screen(b)) < 20.0


func _map() -> void:
	step = "map"
	check(game.enemies.size() == 19 and game.civilians.is_empty(), "who's there: %d, %d" % [game.enemies.size(), game.civilians.size()])
	var snowy := 0
	for rec in game.placed:
		var m: Dictionary = game.meta["objects"][rec["type"]]
		var path: String = (rec["sprite"] as Sprite2D).texture.resource_path
		if m.has("skins"):
			snowy += 1
			check(path.contains("/snow/"), "%s isn't snowed on: %s" % [rec["type"], path])
	check(snowy > 100, "only %d things under snow" % snowy)
	var crate: Dictionary = {}
	for p in game.props:
		if p["kind"] == "crate":
			crate = p
			break
	check(not crate.is_empty(), "no crate to shoot up")
	if not crate.is_empty():
		game._prop_state(crate, 1, true)
		check((crate["sprite"] as Sprite2D).texture.resource_path.contains("/snow/crate_1"),
			"a shot-up crate loses its snow: %s" % (crate["sprite"] as Sprite2D).texture.resource_path)
	var ice: Array = game.level["ice"][0]
	check(ice[1] - ice[3] < 4.0 or ice[0] - ice[2] < 4.0, "the pond's not at the edge of town: %s" % [ice])
	check((game.level["ice_holes"] as Array).size() == 3, "holes in the ice: %s" % [game.level["ice_holes"]])
	check(game.meta.has("ground_silencio") and game.level["ground"] == "ground_silencio", "no snow on the ground")
	# the weather: snow falling, and the grade gone cold and flat under the cloud
	check(game.snowfall != null and game.snowfall.flakes.size() == Snowfall.COUNT, "no snow falling")
	var mat := game.post.material as ShaderMaterial
	check(mat.get_shader_parameter("tint").z > 1.0 and mat.get_shader_parameter("contrast") < 1.0, "still the desert's sun")


func _ways() -> void:
	step = "ways"
	var start := Vector2(game.level["player"]["x"], game.level["player"]["y"])
	for to in [Vector2(17.8, 29.6), Vector2(47.5, 29.6), Vector2(28.0, 30.6), Vector2(31.0, 16.4), Vector2(10.0, 9.0),
			Vector2(1.0, 31.5), Vector2(63.0, 31.5)]:
		check(_reaches(start, to), "no way from the horse to %s" % to)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		_map()
		_ways()
		game.begin()
	if frame <= 3:
		return false
	t += delta
	if t < 12.0:
		if t > 2.0 and t < 2.05:
			_flake0 = game.snowfall.flakes[0]
		return false
	step = "snow"
	var f: Vector4 = game.snowfall.flakes[0]
	check(f.y != _flake0.y, "the snow's stopped falling")
	step = "quiet"
	check(game.state == "play", "it ended by itself: %s" % game.state)
	print("silencio test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)
	return true
