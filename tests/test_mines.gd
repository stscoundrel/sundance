extends SceneTree
## Paso Esperanza's mined ground and the plunger (scripts/minefield.gd):
##   laid     - the charges round the breastwork, none in reach of the gun or the
##              plunger; E by the plunger works it, from nowhere else.
##   dug in   - a stick going up on a charge doesn't set it off.
##   ripple   - pushed, they go up a moment later, down each run one after the
##              other: the men on them blown away, the army's cover too, but not
##              the stranger at the plunger, the gun, or the breastwork.
##   rout     - every man of the army falls back, the far ones he can't see too,
##              and a few seconds later comes on again.
##   once     - it's spent: nothing more to push.
##   godot --headless --path . --fixed-fps 60 -s tests/test_mines.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
var phase := "laid"
var mark := 0.0
var m: Minefield
var near_men: Array = []
var far_men: Array = []
var far_from := {}
var ours_hp: Array = []   # [prop, hp] (a prop is no key: its hp changes)
var theirs: Dictionary = {}
var theirs_hp := 0
var hp0 := 0
var belt0 := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "train")
	Engine.set_meta("no_waves", true)
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


## Out of rounds: nothing of his into the bags, or the stranger.
func _unload(e: Enemy) -> void:
	e.weapon.chambered = false
	e.weapon.tube = 0
	e.weapon.reserve = 0


func _blown() -> int:
	return game.stats.get("mines blown", 0)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 100000
	if frame <= 3:
		return false
	t += delta
	if t < 6.0:
		return false   # (the opening)
	if t > 120.0:
		check(false, "stuck in %s" % phase)
		return _finish()
	var p: Player = game.player
	match phase:
		"laid":
			step = "laid"
			m = game.minefield
			check(m != null, "no minefield on the map")
			if m == null:
				return _finish()
			check(m.charges() == 15, "%d charges" % m.charges())
			for run in m.runs:
				for c in run:
					check(c["at"].distance_to(game.mgun.seat) > Dynamite.R, "a charge reaches the gun")
					check(c["at"].distance_to(m.at) > Dynamite.R, "a charge reaches the plunger")
			var gun_to: float = m.at.distance_to(game.mgun.seat)
			check(gun_to > 40.0 and gun_to < 90.0, "the plunger's %.0f px from the gun: not a few steps" % gun_to)
			check(m.can_push(m.at + Vector2(8, 4)), "can't work it from beside it")
			check(not m.can_push(m.at + Vector2(40, 0)), "can work it from 40 px off")
			check(not m.can_push(game.mgun.seat), "can work it from the gun")
			step = "dug in"
			var leva: Enemy = game._add_enemy("leva", m.runs[0][3]["at"] + Vector2(0, -200), PackedVector2Array(), 90.0, {})
			game.blast(m.runs[0][3]["at"] + Vector2(10, 0), leva)   # (a stick of theirs, right on it)
			check(_blown() == 0 and not m.fired, "a stick set a charge off")
			leva.queue_free()
			game.enemies.erase(leva)
			phase = "men"
			mark = t
		"men":
			if t - mark < 1.0:
				return false
			step = "ripple"
			# a man on every other charge, held there (and, as it's pushed, two far off, coming on)
			var i := 0
			for run in m.runs:
				for c in run:
					i += 1
					if i % 2 == 0:
						continue
					var e: Enemy = game._add_enemy("soldado", c["at"] + Vector2(6, 3), PackedVector2Array(), 270.0,
						{"loadout": ["springfield"], "loadouts": []})
					e.reaction = "cower"
					e.reaction_t = 99.0
					_unload(e)   # (none of his rounds into the bags: only the mines, here)
					near_men.append(e)
			for prop in game.props:
				if prop.get("ours", false):
					ours_hp.append([prop, prop["hp"]])
				elif theirs.is_empty() and prop["state"] < 2:
					for run in m.runs:
						for c in run:
							if game.prop_centre(prop).distance_to(c["at"]) < 40.0:
								theirs = prop
			check(ours_hp.size() >= 8, "only %d pieces of the breastwork marked ours" % ours_hp.size())
			check(not theirs.is_empty(), "nothing of the army's cover near a charge")
			theirs_hp = theirs.get("hp", 0)
			p.global_position = m.at + Vector2(8, 4)
			hp0 = p.hp
			belt0 = game.mgun.belt
			phase = "push"
			mark = t
		"push":
			if t - mark < 1.0:
				return false
			var spot := Iso.to_screen(Vector2(40.4, 35.6))
			for at in [Vector2(54.0, 30.0), Vector2(52.0, 48.0)]:   # (off his screen, and coming on)
				var f: Enemy = game._add_enemy("soldado", Iso.to_screen(at), PackedVector2Array(), 180.0,
					{"loadout": ["springfield"], "loadouts": []})
				_unload(f)
				f.assault_to(spot)
				far_men.append(f)
				far_from[f] = f.global_position
			m.push(p)
			check(m.fired and not m.can_push(p.global_position), "pushed, and it can be pushed again")
			phase = "ripple"
			mark = t
		"ripple":
			step = "ripple"
			var dt := t - mark
			if dt < 0.2:
				check(_blown() == 0, "a bang before the handle's down")
				return false
			if dt > 0.55 and dt < 0.6:
				check(_blown() > 0 and _blown() < m.charges(), "not one after another: %d gone at %.2f s" % [_blown(), dt])
				for run in m.runs:
					check(run[0]["blown"] and not run[-1]["blown"], "a run went up from the wrong end")
			if dt < 3.0:
				return false
			check(_blown() == m.charges(), "%d of %d went up" % [_blown(), m.charges()])
			check(m.routed, "no rout")
			var dead := 0
			for e in near_men:
				if not e.alive:
					dead += 1
			check(dead >= near_men.size() - 1, "only %d of %d on the charges killed" % [dead, near_men.size()])
			check(p.alive and p.hp == hp0, "the stranger at the plunger hurt (%d)" % (hp0 - p.hp))
			check(game.mgun.belt == belt0 and game.mgun.gunner == null, "the gun touched")
			var worn := 0
			for o in ours_hp:
				if o[0]["hp"] < o[1]:
					worn += 1
			check(worn == 0, "%d pieces of the breastwork hurt" % worn)
			check(theirs["hp"] < theirs_hp or theirs["state"] > 0, "the army's %s by a charge untouched" % theirs["kind"])
			step = "rout"
			for f in far_men:
				check(f.alive and (f.reaction == "flee" or f.deserting), "a man off up the road didn't fall back (%s)" % f.reaction)
			phase = "rout"
			mark = t
		"rout":
			step = "rout"
			if t - mark < 1.5:
				return false
			for f in far_men:
				check(f.global_position.distance_to(m.at) > far_from[f].distance_to(m.at) + 40.0,
					"a man didn't fall back (%.0f px nearer)" % (far_from[f].distance_to(m.at) - f.global_position.distance_to(m.at)))
			phase = "again"
			mark = t
		"again":
			step = "again"
			if t - mark < 3.5:
				return false
			for f in far_men:
				check(f.alive and f.reaction == "" and f.assault and f.objective != Vector2.INF,
					"not coming on again (%s)" % f.reaction)
			step = "once"
			m.push(p)
			check(_blown() == m.charges(), "pushed again, and more went up")
			return _finish()
	return false


func _finish() -> bool:
	print("mines test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	return true
