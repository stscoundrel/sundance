extends SceneTree
## Buried (A Good Man Never Dies, phase 3; see Funeral), on the worst record:
##   sermon  - "He lived by the gun... and by the gun he died": more nails than any
##             lid will give on.
##   locked  - after the Amen, blows on the lid do nothing.
##   buried  - the earth goes in over him: a fresh grave with a cross where the hole
##             was, and the level's lost ("HE LIVED BY THE GUN").
##   godot --headless --path . --fixed-fps 60 -s tests/test_buried.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var mounds := 0


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "funeral")
	Engine.set_meta("record", "worst")
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		game._to_loadout()
		mounds = game.placed.filter(func(r): return r["type"] == "mound").size()
	if frame <= 3:
		return false
	var f: Funeral = game.funeral
	var c: Coffin = game.coffin
	if f.phase in ["wait", "sermon"]:
		f.hurry()
		return false
	if f.phase in ["lower", "fill"]:
		if step == "":
			step = "sermon"
			check(c.nails >= Funeral.LOCKED and c.locked(), "a lid he could break: %d nails" % c.nails)
			check(f.lines.any(func(l): return l["text"].begins_with("He lived by the gun")), "no 'lived by the gun'")
			step = "locked"
		c.blow()
		check(c.inside and c.blows == 0, "the lid gave")
		return false
	step = "buried"
	check(f.phase == "buried" and c.inside and game.state == "lost" and game.stats.get("buried", false), "not buried: %s %s" % [f.phase, game.state])
	check(game.placed.filter(func(r): return r["type"] == "mound").size() == mounds + 1, "no fresh grave over him")
	check(not f.grave_spr.visible, "the hole's still open")
	print("buried test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)
	return true
