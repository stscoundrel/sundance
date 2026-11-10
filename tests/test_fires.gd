extends SceneTree
## Silencio's campfires and woodcutters (Campfire, Enemy "warm", Civilian "woodcutter"),
## no squalls:
##   fires   - four of them, two at each gang's end, burning, and burning down.
##   warm    - a man of a post by a fire goes over and holds his hands to it, eyes on
##             the flames (his sight cut short), then back to his post.
##   cutter  - a woodcutter splits logs at his stump, the axe heard; carries an armful
##             to his end's lowest fire and lays it on (it's higher after), and the
##             stranger walking right by doesn't put him off it.
##   cold    - a fire let go out: nobody warms at it, and its post is a cold one.
##   godot --headless --path . --fixed-fps 60 -s tests/test_fires.gd

var game: Node
var frame := 0
var failures := 0
var t := 0.0
var step := "fires"
var man: Enemy
var cutter: Civilian
var low: Campfire
var low_fuel := 0.0
var went := false
var cut := 1.0
var posed := ""
var fuel0 := 0.0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "silencio")
	Engine.set_meta("no_alarm", true)
	seed(8)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _done() -> void:
	print("fires: %s" % {"warmings": game.stats.get("warmings", 0), "fed": game.stats.get("fires fed", 0)})
	print("fires test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 1000
		game.player.process_mode = Node.PROCESS_MODE_DISABLED
		game.player.global_position = Iso.to_screen(Vector2(32.0, 62.0))   # (by his horse, out of it)
		game.snowfall.squalls.assign([])
		for e in game.enemies:
			e.warm_at = INF
			e.smoke_at = INF
			e.nature_at = INF
	if frame <= 3:
		return false
	t += delta
	match step:
		"fires":
			check(game.fires.size() == 4, "%d campfires" % game.fires.size())
			check(game.fires.filter(func(f): return f.end == "outlaws").size() == 2, "not two at the outlaws' end")
			check(game.fires.all(func(f): return f.lit()), "a fire out from the start")
			fuel0 = game.fires[0].fuel
			step = "burn"
			t = 0.0
		"burn":
			if t > 10.0:
				var burnt: float = fuel0 - game.fires[0].fuel
				check(absf(burnt - 10.0 / Campfire.BURN_T) < 0.01, "%.3f burnt in 10 s" % burnt)
				for e in game.enemies:
					if e.revealed and e.st == Enemy.St.GUARD and e._post_fire() != null and e._at_ease():
						man = e
						break
				check(man != null, "nobody at ease at a post by a fire")
				if man == null:
					_done()
					return false
				man.warm_at = game.clock
				step = "warm"
				t = 0.0
		"warm":
			if man.st == Enemy.St.ERRAND and man.errand == "warm":
				went = true
				if man.errand_t > 0.0:
					cut = minf(cut, man.view_range() / Enemy.VIEW)
					if man.pose == "warm":
						posed = "warm"
					check(man.global_position.distance_to(man.warm_fire.global_position) < 28.0, "not by the fire")
					check(man.facing.dot((man.warm_fire.global_position - man.global_position).normalized()) > 0.7, "not facing the fire")
			elif went and man.st == Enemy.St.GUARD and man.global_position.distance_to(man.home) < 8.0:
				check(cut < 0.35, "his sight was %.2f of itself at the fire" % cut)
				check(posed == "warm", "not warming his hands")
				for c in game.civilians:
					if c.woodcutter:
						cutter = c
						break
				check(cutter != null, "no woodcutter")
				low = null
				for f in game.fires:
					if f.end == cutter.end:
						if low == null:
							low = f
						else:
							f.fuel = 1.0
				low.fuel = 0.3
				posed = ""
				step = "cutter"
				t = 0.0
			elif t > 45.0:
				check(false, "no warming, and back (went %s, st %d)" % [went, man.st])
				_done()
		"cutter":
			if t > 1.0 and t - delta <= 1.0:   # (the stranger walking right past him, the gang held still)
				for e in game.enemies:
					e.process_mode = Node.PROCESS_MODE_DISABLED
				game.player.global_position = cutter.global_position + Vector2(30, 10)
			if t > 1.0 and t < 4.0:
				game.player.global_position += Vector2(-20, 0) * delta
				check(cutter.st != Civilian.St.GONE and cutter.st != Civilian.St.FLEE, "the stranger put him off it")
			if t > 4.0 and t - delta <= 4.0:
				game.player.global_position = Iso.to_screen(Vector2(32.0, 62.0))
				for e in game.enemies:
					e.process_mode = Node.PROCESS_MODE_INHERIT
			if cutter.st == Civilian.St.CHOP and cutter.pose == "chop":
				posed = "chop" if posed == "" else posed
				check(cutter.st != Civilian.St.GONE and cutter.st != Civilian.St.FLEE, "the stranger put him off it")
			if cutter.st == Civilian.St.TO_FIRE:
				check(cutter.fire == low, "taking it to the wrong fire")
				if cutter.pose == "carry":
					posed = "carry"
			if cutter.st == Civilian.St.FEED:
				low_fuel = low.fuel
			if low_fuel > 0.0 and cutter.st == Civilian.St.TO_BLOCK:
				check(low.fuel > low_fuel + Campfire.FEED * 0.8, "the fire's no higher (%.2f, %.2f)" % [low_fuel, low.fuel])
				check(posed == "carry", "never seen carrying")
				low.fuel = 0.0
				step = "cold"
				t = 0.0
			elif t > 60.0:
				check(false, "no armful laid on (st %d)" % cutter.st)
				_done()
		"cold":
			if t > 0.2 and t - delta <= 0.2:
				var near: Enemy = null
				for e in game.enemies:
					if e.alive and e._post_fire() == low and e.st == Enemy.St.GUARD:
						near = e
				if near:
					check(near._cold_post(), "a post by a dead fire isn't cold")
					near.warm_at = game.clock
					man = near
			if t > 2.0:
				if man and man._post_fire() == low:
					check(not (man.st == Enemy.St.ERRAND and man.errand == "warm"), "warming at a dead fire")
				_done()
	return false
