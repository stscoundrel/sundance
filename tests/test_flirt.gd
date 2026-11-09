extends SceneTree
## The saloon girls. In San Miguel (the girls told to go out at once):
##   out    - a girl walks out to a man standing guard near her place, one of the gang
##            proper (never the girl with the derringer, nor a patrol); there she keeps
##            him talking, and he has eyes only for her: his sight a short, narrow wedge
##            on her. Done, she goes home and he's himself again.
##   shot   - a shot nearby and she's off indoors; he's free of her at once.
## Then Silencio, where the girls are in furs and go out all the same, and Cruz Verde,
## a fight's town, where they never do.
##   godot --headless --path . --fixed-fps 60 -s tests/test_flirt.gd

const LEVELS := ["san_miguel", "silencio", "cruz_verde"]

var level := ""
var game: Node
var frame := 0
var failures := 0
var t := 0.0
var girl: Civilian
var beau: Enemy
var talked := 0.0
var narrow := 1.0
var phase := "out"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	level = args[0] if args.size() > 0 else ""
	if level == "":
		# each town in its own process, one after another
		var code := 0
		for l in LEVELS:
			var out := []
			code += OS.execute(OS.get_executable_path(), ["--headless", "--path", ".", "--fixed-fps", "60", "-s", "tests/test_flirt.gd", "--", l], out, true)
			for line in "".join(out).split("\n"):
				if line.begins_with("FAIL") or line.begins_with("[") or "SCRIPT ERROR" in line:
					print(line)
		print("flirt test: ", "OK" if code == 0 else "failures")
		quit(1 if code else 0)
		return
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", level)
	Engine.set_meta("no_hanging", true)
	Engine.set_meta("no_captive", true)
	Engine.set_meta("no_waves", true)
	seed(3)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [level, msg])


func _done() -> void:
	print("[%s] %s" % [level, "OK" if failures == 0 else "%d failures" % failures])
	quit(1 if failures else 0)


func _process(delta: float) -> bool:
	if level == "":
		return false
	frame += 1
	if frame == 3:
		game.begin()
		game.player.hp = 1000
		game.player.global_position = Iso.to_screen(Vector2(1.0, 62.0))   # (out of everyone's way)
		var girls := 0
		for c in game.civilians:
			if c.flirts:
				girls += 1
				c.flirt_cd = 0.0
		check(girls >= 2, "%d saloon girls" % girls)
		for e in game.enemies:
			e.set_meta("courted", -1000.0)
	if frame <= 3:
		return false
	t += delta
	if level == "cruz_verde":
		for c in game.civilians:
			check(c.st != Civilian.St.TO_BEAU and c.st != Civilian.St.FLIRT, "a girl out flirting in a fight's town")
		if t > 30.0:
			_done()
		return false
	if girl == null:
		for c in game.civilians:
			if c.st == Civilian.St.FLIRT:
				girl = c
				beau = c.beau
				check(beau.revealed and not beau.tdata["concealed"], "her beau's the gang's own girl")
				check(beau.patrol.size() <= 1, "her beau's a man on his rounds")
				check(beau.sweetheart == girl, "he doesn't know she's there")
				if level == "silencio":
					check(girl.kind == "winter_girl", "a girl out in Silencio not in furs (%s)" % girl.kind)
		if girl == null and t > 60.0:
			check(false, "no girl went out to a man on guard")
			_done()
		return false
	match phase:
		"out":
			if girl.st == Civilian.St.FLIRT:
				talked += delta
				narrow = minf(narrow, beau.view_range() / beau.VIEW)
				if talked > 1.0:
					check(beau.facing.dot((girl.global_position - beau.global_position).normalized()) > 0.8, "he isn't looking at her")
					check(beau.half_fov() < Enemy.FOV * 0.3, "his eyes aren't narrowed on her")
			elif talked > 0.0:
				check(narrow < 0.35, "his sight was %.2f of itself with her there" % narrow)
				check(talked >= Civilian.FLIRT_T.x - 0.5, "she only stayed %.1f s" % talked)
				check(beau.sweetheart == null and beau.eyes() == Vector2.ONE, "he still has eyes only for her")
				check(girl.st == Civilian.St.WALK, "she isn't on her way home")
				if level == "silencio":
					_done()
					return false
				phase = "shot"
				girl.flirt_cd = 0.0
				beau.set_meta("courted", -1000.0)
				girl.global_position = girl.home
				girl.st = Civilian.St.IDLE
				talked = 0.0
				t = 0.0
		"shot":
			if girl.st == Civilian.St.FLIRT and talked == 0.0:
				talked = 1.0
				game.make_noise(girl.global_position + Vector2(60, 0), 400.0, "shot", game.player)
				girl.alarm(girl.global_position + Vector2(60, 0), false)
			elif talked > 0.0 and t > 0.2:
				check(girl.st in [Civilian.St.FLEE, Civilian.St.COWER, Civilian.St.GONE], "she stayed at a shot")
				check(girl.beau == null or girl.beau.sweetheart != girl, "he's still sweet on her with shooting going on")
				check(beau.eyes() == Vector2.ONE, "his eyes are still on her")
				_done()
			elif t > 60.0:
				check(false, "she never went out again")
				_done()
	return false
