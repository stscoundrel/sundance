extends SceneTree
## The end credits (see Credits), after he's buried on the worst record:
##   due     - the end screen offers the credits; a death in the fight wouldn't.
##   roll    - Enter rolls them, to their own music (the funeral's score gives way):
##             the cast, the crew, the films, and FINE last
##             (the breakout's last card is the level's name instead).
##   cards   - a card moves on by itself, and a key moves it on at once.
##   last    - the last card stays; once it's read, Enter rides on to the picker.
##   godot --headless --path . --fixed-fps 60 -s tests/test_credits.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var since := 0


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


func enter() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.physical_keycode = KEY_ENTER
	ev.pressed = true
	root.push_input(ev)
	var up := ev.duplicate()
	up.pressed = false
	root.push_input(up)


func done() -> bool:
	print("credits test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)
	return true


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		game._to_loadout()
	if frame <= 3:
		return false
	var f: Funeral = game.funeral
	if step == "":
		if f.phase in ["wait", "sermon"]:
			f.hurry()
		if game.state != "lost":
			if frame > 60 * 60:
				check(false, "never buried: %s" % f.phase)
				return done()
			return false
		step = "due"
		check(game.credits_due(), "no credits after the burial")
		check(game.hud.hint.begins_with("Enter: the credits"), "end screen says: %s" % game.hud.hint)
		game.stats["buried"] = false
		check(not game.credits_due(), "credits after a death in the fight")
		game.stats["buried"] = true
		var out := Credits.make("out")
		check(out.cards[-1]["lines"][0][1] == "A Good Man Never Dies", "breakout's last card: %s" % [out.cards[-1]])
		step = "roll"
		enter()
		return false
	var c: Credits = game.credits
	if step == "roll":
		check(game.state == "credits" and c != null, "Enter didn't roll them: %s" % game.state)
		if c == null:
			return done()
		check(c.ending == "buried" and c.cards[-1]["lines"][0][1] == "FINE", "buried's last card: %s" % [c.cards[-1]])
		var all := JSON.stringify(c.cards)
		for who in ["The Stranger", "YOU", "Directed by", "Sergio Leone", "Sergio Corbucci", "Sergio Sollima", "Enzo G. Castellari", "Ennio Morricone", "Godot Engine", "Dependabot", "GitHub Actions"]:
			check(all.contains(who), "no %s" % who)
		check(game.hud.message == "", "the end screen's still up")
		check(Engine.time_scale == 1.0, "still slowed: %.2f" % Engine.time_scale)
		check(game.credits_music != null and game.credits_music.playing, "no credits music")
		check(game.music == null, "the funeral's score still playing under them")
		step = "cards"
		since = frame
		return false
	if step == "cards":
		if c.i == 0:
			if frame - since > 60 * 8:
				check(false, "the first card never moved on")
				return done()
			return false
		check(c.i == 1, "skipped past the cast: %d" % c.i)
		enter()
		check(c.i == 2, "Enter didn't move it on: %d" % c.i)
		while not c.last():
			enter()
		step = "last"
		check(not c.read(), "the last card read before it's up")
		since = frame
		return false
	if step == "last":
		if not c.read():
			if frame - since > 60 * 5:
				check(false, "the last card never read")
				return done()
			return false
		check(c.alpha() == 1.0, "the last card fading: %.2f" % c.alpha())
		enter()
		check(game.state == "riding" and game.open_on == "levels", "not riding to the picker: %s %s" % [game.state, game.open_on])
		return done()
	return false
