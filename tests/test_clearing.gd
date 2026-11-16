extends SceneTree
## The funeral's sky clearing as he wins (Snowfall.clear, the map's "clears"):
##   count  - every guest on his feet and every man still down the roads counts:
##            35 at the start, and the storm at its worst.
##   stages - full storm down to 25 left; thinning to 15; an overcast drizzle to 5;
##            the sun with fewer than 5.
##   sun    - four left: over half a minute the rain stops, the downpours and the
##            thunder with it; everyone sees as far as in the other towns; the light
##            goes from the grey to the desert sun's; the blood stays where it falls;
##            "The rain eases", then "The sun breaks through"; the rain's
##            noise gone, the wind back, the ground steaming.
##   godot --headless --path . --fixed-fps 60 -s tests/test_clearing.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var t0 := 0.0
var phase := 0
var splat: Array


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "funeral")
	Engine.set_meta("no_coffin", true)
	Engine.set_meta("no_downed", true)
	Engine.set_meta("no_gasp", true)
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game._to_loadout()
		game.player.hp = 1000000
		game.player.global_position = Iso.to_screen(Vector2(3.0, 96.0))   # (off in the far corner, out of their way)
	if frame <= 3:
		return false
	t += delta
	if t > 60.0:
		check(false, "ran out of time in phase %d" % phase)
		return _done()
	var sf: Snowfall = game.snowfall
	match phase:
		0:
			if t < 1.0:
				return false
			step = "count"
			check(game.gang_left() == 35, "fifteen guests and twenty coming: %d" % game.gang_left())
			check(sf.clear == 0.0 and sf.wet == 1.0, "a storm to start: clear %.2f" % sf.clear)
			step = "stages"
			for c in [[35, 0.0], [25, 0.0], [20, 0.225], [15, 0.45], [10, 0.65], [5, 0.85], [4, 1.0], [7, 0.77], [2, 1.0]]:
				check(absf(Snowfall.clearing_for(c[0]) - c[1]) < 0.01, "%d left: clear %.3f, not %.3f" % [c[0], Snowfall.clearing_for(c[0]), c[1]])
			step = "sun"
			var d: Director = game.director
			for g in d.camps:   # (every faction's men in: none still coming)
				d.camps[g]["state"] = "sent"
			var alive: Array = game.enemies.filter(func(e): return e.alive)
			for i in game.alive_enemies() - 4:   # (dead of nothing anyone saw)
				alive[i].silent_death = true
				alive[i].take_hit(1000, Vector2.RIGHT, null)
			phase = 1
			t0 = t
		1:
			if t - t0 < 2.0:
				return false
			check(game.gang_left() == 4, "four left: %d" % game.gang_left())
			check(sf.clear > 0.0 and sf.clear < 0.2, "it clears over time, not at once: %.2f" % sf.clear)
			phase = 2
		2:
			if sf.clear < 1.0 and t - t0 < 40.0:
				return false
			check(sf.clear == 1.0 and sf.wet == 0.0, "the sun never came: clear %.2f" % sf.clear)
			check(t - t0 > 20.0, "the sky cleared in %.1f s: too quick" % (t - t0))
			check(absf(game.sight - 1.0) < 0.001, "sight in the sun: %.2f" % game.sight)
			check(sf.storm == 0.0, "a downpour in the sun")
			check(sf._mm.visible_instance_count == 0, "rain in the sun: %d drops" % sf._mm.visible_instance_count)
			var mat := game.post.material as ShaderMaterial
			check((mat.get_shader_parameter("tint") as Vector3).distance_to(game.SUN["tint"]) < 0.01, "the light's still grey")
			check(game.sun_wind != null and game.sun_wind.volume_db > -13.0, "no wind in the sun: %.1f dB" % (game.sun_wind.volume_db if game.sun_wind else -999.0))
			check(game.wind_player.volume_db < -50.0, "rain still heard in the sun: %.1f dB" % game.wind_player.volume_db)
			check(game.puddles._steam_t > 0.0, "the ground never steamed in the sun")
			check(sf._eased and sf._sunny, "no word of it: eased %s, sun %s" % [sf._eased, sf._sunny])
			game.drip(game.player, game.player.global_position + Vector2(20, 0))
			splat = game.decals.splats[game.decals.splats.size() - 1]
			t0 = t
			phase = 3
		3:   # the blood stays in the dry
			if t - t0 < 2.0:
				return false
			check(splat[3] == 0.0, "blood washed in the sun: %.3f" % splat[3])
			var next: Vector2 = sf.squalls.filter(func(q): return q.x > game.clock)[0]
			game.clock = next.x + 0.5   # (into the next of the storm's downpours, as was)
			var before := sf.flashed
			for k in 3:
				sf._physics_process(1.0 / 60.0)
			check(sf.flashed == before and sf._thunder_at < 0.0, "lightning in the sun")
			check(sf.storm == 0.0, "a downpour in the sun")
			return _done()
	return false


func _done() -> bool:
	print("clearing test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)
	return true
