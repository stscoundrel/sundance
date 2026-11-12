extends SceneTree
## The rain on his funeral (scripts/snowfall.gd in its rain, the map's "rain"):
##   rain     - the burial ground has weather: rain, not snow; no prints, no drifts;
##              the wind's loop is the rain's.
##   steady   - in the steady rain everyone sees a little less far; the drops fall
##              fast, straight down and a little east, no sway.
##   downpour - every so often the heavens open: everyone sees well over a third less
##              far, the grey closes in from the edges; and nobody goes in out of it
##              (they came to bury him).
##   godot --headless --path . --fixed-fps 60 -s tests/test_rain.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var sf: Snowfall
var drop0 := Vector2.ZERO
var mark := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "funeral")
	Engine.set_meta("no_sermon", true)
	seed(11)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		sf = game.snowfall
		step = "rain"
		check(sf != null and sf.rain, "the funeral has its rain")
		check(game.footprints == null and game.drifts == null, "no prints or drifts in the rain")
		check(game.wind_player.stream.resource_path.ends_with("rain.wav"), "the rain's loop plays, not the wind's")
		check(not sf.squalls.is_empty(), "downpours to come")
	elif frame == 10:
		step = "steady"
		check(absf(game.sight - Snowfall.RAIN_SIGHT.x) < 0.01, "sight %.2f in the steady rain" % game.sight)
		check(sf.storm == 0.0, "no downpour at the start")
		drop0 = sf.flake_at(5)
	elif frame == 40:   # half a second on
		var d := sf.flake_at(5) - drop0
		check(d.y > 150.0 or d.y < 0.0, "a drop falls fast (%.0f px in half a second, or wrapped)" % d.y)
		mark = 0
		for e in game.enemies:
			mark += 1 if e.shelter_rolled >= 0 else 0
		# into the worst of the first downpour
		game.clock = sf.squalls[0].x + Snowfall.RISE + 1.0
	elif frame == 44:
		step = "downpour"
		check(sf.storm == 1.0, "the heavens open (storm %.2f)" % sf.storm)
		check(absf(game.sight - Snowfall.RAIN_SIGHT.y) < 0.01, "sight %.2f in a downpour" % game.sight)
		var fog: float = (game.post.material as ShaderMaterial).get_shader_parameter("fog")
		check(fog > 0.3, "the grey closes in (fog %.2f)" % fog)
		var sheltered := 0
		for e in game.enemies:
			sheltered += 1 if e.shelter_rolled >= 0 else 0
		check(sheltered == mark, "nobody goes in out of the rain")
		print("rain test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	return false
