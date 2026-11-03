extends SceneTree
## One bandit at a time in the open against an invulnerable hero, with rounds
## cracking past him every couple of seconds. A gunslinger must shoot more, close
## in, shoot on the move and shrug the near misses off; a pistolero is the yardstick:
##   godot --headless --path . --fixed-fps 60 -s tests/test_gunslinger.gd

const HERO := Vector2(26.0, 31.4)
const START := Vector2(36.0, 31.4)
const ROUND := 20.0
const KINDS := ["gunslinger", "pistolero"]

var game: Node
var frame := 0
var failures := 0
var who: Enemy
var round_i := -1
var round_t := 0.0
var results := {}
var r := {}
var last_reaction := ""
var next_miss := 1.0
var next_tick := 0.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _start_round() -> void:
	round_i += 1
	round_t = 0.0
	next_miss = 1.0
	next_tick = 0.0
	for e in game.enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED
	who = null
	for e in game.enemies:
		if e.kind == KINDS[round_i] and e.alive and e != who:
			who = e
			break
	who.process_mode = Node.PROCESS_MODE_INHERIT
	who.global_position = Iso.to_screen(START)
	who.enter_combat(game.player.global_position, true, false)
	r = {"shots": 0, "moving_shots": 0, "closest": 1e9, "scared": 0, "start": 0.0}
	r["start"] = who.global_position.distance_to(game.player.global_position)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.global_position = Iso.to_screen(HERO)
		game.player.hp = 1000000
		_start_round()
	if frame <= 3:
		return false
	round_t += delta
	if OS.get_cmdline_user_args().has("trace") and who.reaction != last_reaction:
		last_reaction = who.reaction
		print("  %5.1fs %s: %s (fear %.2f, shaken %.2f, nerve %.2f)" % [round_t, who.kind, who.reaction, who.fear(), who.shaken, who.nerve])
	if who.since_shot < delta * 0.5:
		r["shots"] += 1
		if who.velocity.length() > 5.0:
			r["moving_shots"] += 1
	r["closest"] = min(r["closest"], who.global_position.distance_to(game.player.global_position))
	if round_t >= next_tick:
		next_tick += 0.5
		if OS.get_cmdline_user_args().has("trace") and who.kind == "gunslinger":
			var fp: float = -1.0 if who.fight_pos == Vector2.INF else who.fight_pos.distance_to(game.player.global_position)
			print("    . %4.1fs d %.0f fight_pos %.0f at_cover %s sees %s st %d wstate %d loaded %d crouch %s side %.1f react %.1f" % [
				round_t, who.global_position.distance_to(game.player.global_position), fp, who.at_cover, who.sees_player,
				who.st, who.weapon.state, who.weapon.loaded(), who.crouched, who.sidestep_t, who.react])
		if who.reaction in ["cower", "flee", "dash", "hide", "backoff", "flinch"] and who.reaction_t > 0.0:
			r["scared"] += 1   # half-seconds spent ducking, cowering or running
	if round_t >= next_miss:
		next_miss += 2.0
		who.near_miss(game.player.global_position)
	if round_t < ROUND:
		return false
	results[who.kind] = r
	print("%-10s shots %2d (%d on the move), from %.0f px closed to %.0f px, %.1f s scared" % [
		who.kind, r["shots"], r["moving_shots"], r["start"], r["closest"], r["scared"] * 0.5])
	if round_i + 1 < KINDS.size():
		_start_round()
		return false
	var g: Dictionary = results["gunslinger"]
	var p: Dictionary = results["pistolero"]
	check(g["shots"] > p["shots"] * 1.5, "gunslinger should outshoot a pistolero (%d vs %d)" % [g["shots"], p["shots"]])
	check(g["moving_shots"] >= 3, "gunslinger should shoot on the move (%d)" % g["moving_shots"])
	check(g["closest"] < p["closest"] - 20.0, "gunslinger should close in (%.0f vs %.0f px)" % [g["closest"], p["closest"]])
	check(g["scared"] < p["scared"], "gunslinger should spend less time scared (%.1f vs %.1f s)" % [g["scared"] * 0.5, p["scared"] * 0.5])
	print("gunslinger test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
