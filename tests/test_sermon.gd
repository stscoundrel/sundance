extends SceneTree
## The burial (A Good Man Never Dies, phase 3; see Funeral), on a middling record:
##   sermon  - the padre speaks it line by line over his head, his record town by
##             town; the carpenter drives the nails in as each sin's named, the
##             record's worth all told; the lid can't be tried before the Amen.
##   lowered - at the Amen the coffin goes down into the grave, him in it; the lid
##             can be tried now, a nail at a time.
##   out     - broken open down there, he climbs up out of the hole; the grave's
##             empty again, the padre, carpenter and digger free to run.
##   godot --headless --path . --fixed-fps 60 -s tests/test_sermon.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var phase := 0
var said := {}


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "funeral")
	Engine.set_meta("record", "middling")
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
		game.player.hp = 1000000
	if frame <= 3:
		return false
	var f: Funeral = game.funeral
	var c: Coffin = game.coffin
	match phase:
		0:
			step = "sermon"
			check(f != null and f.padre != null and f.carpenter != null and f.digger != null, "nobody at the grave to bury him")
			if f == null:
				return _done()
			check(f.padre.bound and f.carpenter.bound and f.digger.bound, "they aren't held to the burial")
			phase = 1
		1:   # through the sermon, hurried: every line said, the nails in, no trying the lid
			if f.phase == "wait":
				return false
			if f.padre.shout != "":
				said[f.padre.shout] = true
			if f.phase == "sermon":
				c.blow()
				check(c.inside and c.blows == 0, "the lid tried before the Amen")
				f.hurry()
				return false
			step = "sermon"
			var want := Funeral.nails_for(Funeral.RECORDS["middling"])
			check(c.nails == want and want == 5, "nails in the lid: %d of %d" % [c.nails, want])
			for l in f.lines:
				check(said.has(l["text"]), "the padre never said: %s" % l["text"])
			check(f.lines.any(func(l): return l["text"].contains("hang a man")) and f.lines.back()["text"] == "Amen.", "the sermon: %s" % [f.lines.map(func(l): return l["text"])])
			phase = 2
		2:   # let down into the grave
			if not c.sunk:
				return false
			step = "lowered"
			check(c.can_hammer and f.phase == "fill" or f.phase == "lower", "not lowered: %s" % f.phase)
			check(game.player.global_position.distance_to(f.hole) < 2.0, "he wasn't let down with it")
			for i in c.blows_left():
				c.blow()
			step = "out"
			check(not c.inside and f.phase == "out", "still in the grave: %s" % f.phase)
			check(f.grave_spr.texture.resource_path.contains("open_grave_empty"), "the grave doesn't show him gone")
			check(not f.padre.bound and not f.carpenter.bound and not f.digger.bound, "they're still held to the burial")
			check(game.state == "play", "it ended: %s" % game.state)
			return _done()
	return false


func _done() -> bool:
	print("sermon test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)
	return true
