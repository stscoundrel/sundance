extends SceneTree
## What the snow covers (Drifts; Footprints in a squall). In Silencio, the gangs held
## still:
##   steady  - a man dead in the snow: in the steady snow it settles on him slowly
##             (nowhere near covered in half a minute).
##   squall  - one comes down and he's soon under a drift: buried, and a guard looking
##             right at him doesn't find him; his blood's filled in (no pool to find)
##             and the gun he dropped has gone under with him.
##   dragged - a body being hauled shakes the snow off; let lie, it settles again.
##   tracks  - a squall blows the stranger's prints over fast, the oldest first.
##   godot --headless --path . --fixed-fps 60 -s tests/test_snowcover.gd

const SCENES := ["steady", "squall", "dragged", "tracks"]

var game: Node
var frame := 0
var failures := 0
var scene_i := -1
var t := 0.0
var dead: Enemy
var other: Enemy
var watcher: Enemy
var old_print: Dictionary
var new_print: Dictionary
var old_gone := -1.0
var new_gone := -1.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "silencio")
	Engine.set_meta("no_alarm", true)
	seed(4)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [SCENES[scene_i], msg])


## Calm weather from now on (or a squall at its worst from `at` for `blow` s).
func _weather(squall_at := INF, blow := 0.0) -> void:
	var s: Array[Vector2] = []
	if squall_at < INF:
		s.append(Vector2(squall_at - Snowfall.RISE, squall_at + blow))
	game.snowfall.squalls.assign(s)


func _pool_of(e: Enemy) -> Dictionary:
	for pl in game.blood_pools:
		if pl["body"] == e:
			return pl
	return {}


func _gun_under(e: Enemy) -> bool:
	for g in game.loose_guns:
		if g["under"] == e:
			return true
	return false


func _next() -> void:
	scene_i += 1
	t = 0.0
	if scene_i >= SCENES.size():
		print("snow cover: %s" % {"snowed over": game.stats.get("snowed over", 0)})
		print("snowcover test: ", "OK" if failures == 0 else "%d failures" % failures)
		quit(1 if failures else 0)
		return
	var p: Player = game.player
	match SCENES[scene_i]:
		"steady":
			_weather()
			dead.die(Vector2.RIGHT, p, "death_back")
		"squall":
			_weather(game.clock + 1.0, 60.0)
			watcher.global_position = dead.global_position + Vector2(-70, 0)
			watcher.facing = Vector2.RIGHT
			watcher.desired = Vector2.RIGHT
			watcher.home = watcher.global_position
			watcher.home_facing = Vector2.RIGHT
			watcher.st = Enemy.St.GUARD
		"dragged":
			_weather(game.clock + 1.0, 60.0)
			other.die(Vector2.RIGHT, p, "death_back")
		"tracks":
			_weather(game.clock + 1.0, 60.0)
			var at := p.global_position + Vector2(0, 60)
			old_print = game.footprints.add_print(at, Vector2.RIGHT, 1.0, true)
			old_print["t"] = game.clock - 30.0   # (laid half a minute ago...)
			old_print["depth"] = 0.5             # (...and half filled in already)
			new_print = game.footprints.add_print(at + Vector2(10, 0), Vector2.RIGHT, -1.0, true)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 1000
		var open := Iso.to_screen(Vector2(40.0, 44.0))
		var used := 0
		for e in game.enemies:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			if e.revealed and used < 3:
				used += 1
				e.global_position = open + Vector2(used * 40.0, 0)
				if used == 1:
					dead = e
				elif used == 2:
					other = e
				else:
					watcher = e
			else:
				e.global_position += Vector2(0, -4000)   # out of the way
		dead.process_mode = Node.PROCESS_MODE_INHERIT
		other.process_mode = Node.PROCESS_MODE_INHERIT
		game.player.global_position = open + Vector2(-200, -120)
		_weather()
	if frame <= 3:
		return false
	if scene_i < 0:
		_next()
		return false
	if scene_i >= SCENES.size():
		return false
	t += delta
	match SCENES[scene_i]:
		"steady":
			if t > 30.0:
				var snow := float(dead.get_meta("snow", 0.0))
				check(snow > 0.05 and snow < 0.25, "%.2f of a drift in 30 s of the steady snow" % snow)
				check(not dead.has_meta("buried"), "buried in the steady snow already")
				check(not _pool_of(dead).is_empty(), "no pool under him")
				check(_gun_under(dead), "no gun lying under him")
				_next()
		"squall":
			if t > 0.5 and t - delta <= 0.5:
				dead.set_meta("snow", 0.9)   # (well on the way: a squall's 40 s does the lot)
			if dead.has_meta("buried") and watcher.process_mode == Node.PROCESS_MODE_DISABLED:
				check(_pool_of(dead).is_empty(), "his blood's still there to find")
				check(not _gun_under(dead), "his gun's still lying there")
				watcher.process_mode = Node.PROCESS_MODE_INHERIT   # (and now a guard looking right at him)
				watcher.known_corpses.append(other)
				t = 9.0
			elif dead.has_meta("buried") and t > 10.0:
				check(not dead in watcher.known_corpses, "the guard found him under the snow")
				_next()
			elif t > 10.0 and not dead.has_meta("buried"):
				check(false, "not under the snow in a squall (%.2f)" % float(dead.get_meta("snow", 0.0)))
				_next()
		"dragged":
			if t > 6.0 and t - delta <= 6.0:
				check(float(other.get_meta("snow", 0.0)) > 0.1, "%.2f of a drift after 5 s at a squall's worst" % float(other.get_meta("snow", 0.0)))
				other.set_meta("dragged", true)
			if t > 6.5 and t - delta <= 6.5:
				check(float(other.get_meta("snow", 0.0)) == 0.0, "hauling him didn't shake the snow off")
				other.remove_meta("dragged")
			if t > 8.0:
				check(float(other.get_meta("snow", 0.0)) > 0.02, "it isn't settling on him again")
				_next()
		"tracks":
			if old_gone < 0.0 and not old_print in game.footprints.prints:
				old_gone = t
			if new_gone < 0.0 and not new_print in game.footprints.prints:
				new_gone = t
			if new_gone >= 0.0:
				check(old_gone >= 0.0 and old_gone < new_gone, "the older print wasn't the first to go (%.1f, %.1f)" % [old_gone, new_gone])
				check(old_gone < 4.0, "the old print took %.1f s to blow over" % old_gone)
				check(new_gone < 14.0, "a fresh print took %.1f s to blow over" % new_gone)
				_next()
			elif t > 20.0:
				check(false, "the prints never blew over (%.1f, %.1f)" % [old_gone, new_gone])
				_next()
	return false
