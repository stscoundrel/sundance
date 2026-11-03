extends SceneTree
## Couples out for a stroll keep together, she on his arm, while the town is calm,
## and both take to their heels when a shot rings out:
##   godot --headless --path . --fixed-fps 60 -s tests/test_couples.gd

const CALM := 40.0

var game: Node
var frame := 0
var clock := 0.0
var failures := 0
var leads: Array[Civilian] = []
var samples := 0
var close := 0
var walked := {}    # lead -> distance strolled
var last := {}


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_hanging", true)   # (the gallows stays empty: see test_hanging)
	seed(2)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		game.begin()
		game.player.global_position = Iso.to_screen(Vector2(-40, -40))   # off the map: all is calm
		for c in game.civilians:
			if c.leads:
				leads.append(c)
				last[c] = c.global_position
				walked[c] = 0.0
		check(leads.size() == 2, "expected two couples (got %d)" % leads.size())
	if frame <= 3:
		return false
	clock += delta
	if clock < CALM:
		for l in leads:
			walked[l] += l.global_position.distance_to(last[l])
			last[l] = l.global_position
			if int(clock * 2.0) != int((clock - delta) * 2.0):
				samples += 1
				close += 1 if l.partner.global_position.distance_to(l.global_position) < Civilian.ARM * 3.0 else 0
		return false
	if clock - delta < CALM:
		for l in leads:
			game.make_noise(l.global_position + Vector2(30, 0), 380.0, "enemy_shot", null)
		return false
	if clock < CALM + 1.0:
		return false
	print("strolled %s px; together %d of %d samples" % [walked.values().map(func(v): return int(v)), close, samples])
	for l in leads:
		check(walked[l] > 80.0, "a couple never went for a stroll (%d px)" % walked[l])
		for c in [l, l.partner]:
			check(c.st in [Civilian.St.FLEE, Civilian.St.COWER, Civilian.St.GONE], "%s stayed put at the shot" % c.kind)
	check(close >= samples * 0.9, "the couples came apart: together %d of %d samples" % [close, samples])
	print("couples test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
	return true
