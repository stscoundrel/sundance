extends SceneTree
## The rain on his funeral (scripts/snowfall.gd in its rain, the map's "rain"):
##   rain     - the burial ground has weather: rain, not snow; no prints, no drifts;
##              the wind's loop is the rain's.
##   steady   - in the steady rain everyone sees a little less far; the drops fall
##              fast, straight down and a little east, no sway.
##   downpour - every so often the heavens open: everyone sees well over a third less
##              far, the grey closes in from the edges; and nobody goes in out of it
##              (they came to bury him).
##   wash     - the rain washes his blood away: a drop on the ground thins and his
##              trail drop with it in the steady rain, slowly; in a downpour it's
##              soon no lead to follow, then gone, ground and trail alike; the pool
##              where a man fell thins but stays.
##   puddles  - water stands all over the open ground, never on anything solid.
##   thunder  - each downpour is marked coming in: a flash of lightning, and the
##              thunder a moment after, once a downpour.
##   godot --headless --path . --fixed-fps 60 -s tests/test_rain.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var sf: Snowfall
var drop0 := Vector2.ZERO
var mark := 0
var drop: Dictionary
var splat: Array
var pool: Sprite2D


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
		step = "puddles"
		check(game.puddles != null and game.puddles.puddles.size() > 150, "puddles all around: %d" % (game.puddles.puddles.size() if game.puddles else 0))
		if game.puddles:
			check(game.puddles.puddles.all(func(p): return game.is_free(p["at"])), "a puddle on something solid")
	elif frame == 10:
		step = "steady"
		check(absf(game.sight - Snowfall.RAIN_SIGHT.x) < 0.01, "sight %.2f in the steady rain" % game.sight)
		check(sf.storm == 0.0, "no downpour at the start")
		drop0 = sf.flake_at(5)
		# his blood, a drop of it, on the ground and on his trail; and a man's pool
		var at: Vector2 = game.player.global_position + Vector2(30, 10)
		game.drip(game.player, at)
		drop = game.trails[game.trails.size() - 1]
		splat = game.decals.splats[game.decals.splats.size() - 1]
		pool = Sprite2D.new()
		game.decals.add_child(pool)
		game.blood_pools.append({"at": at, "body": null, "known": [], "sprite": pool})
	elif frame == 40:   # half a second on
		var d := sf.flake_at(5) - drop0
		check(d.y > 150.0 or d.y < 0.0, "a drop falls fast (%.0f px in half a second, or wrapped)" % d.y)
		step = "wash"
		check(splat[2].a < splat[4] and splat[2].a > splat[4] * 0.9, "a drop thins slowly in the steady rain: %.3f of %.3f" % [splat[2].a, splat[4]])
		check(drop.get("wash", 0.0) > 0.0 and drop["wash"] < Snowfall.WASH_LEAD, "his trail washes slowly in the steady rain: %.3f" % drop.get("wash", 0.0))
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
		step = "thunder"
		check(sf.flashed >= 0.0, "lightning as the downpour comes in")
		check(game.post.material.get_shader_parameter("flash") > 0.0, "the screen whitens")
	elif frame == 44 + 60 * 8:   # eight seconds of the downpour
		step = "wash"
		check(drop["wash"] > Snowfall.WASH_LEAD, "half washed out in a downpour, no lead: %.2f" % drop["wash"])
		check(game.trails.has(drop), "but not gone yet")
		check(pool.modulate.a >= Snowfall.POOL_LEFT - 0.001 and pool.modulate.a < 1.0, "the pool thins: %.2f" % pool.modulate.a)
	elif frame == 44 + 60 * 17:   # seventeen
		check(not game.trails.has(drop), "his trail drop washed away")
		check(not game.decals.splats.has(splat), "the drop on the ground washed away")
		check(absf(pool.modulate.a - Snowfall.POOL_LEFT) < 0.001, "the pool stays, thinned: %.2f" % pool.modulate.a)
		print("rain test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return true
	elif frame == 110:   # a second on: the thunder's come, the flash is gone
		check(sf._thunder_at < 0.0, "the thunder came after the flash")
		check(sf.flash == 0.0, "the flash is over")
		var f := sf.flashed
		for i in 30:
			sf._physics_process(0.0)
		check(sf.flashed == f, "one flash a downpour")
	return false
