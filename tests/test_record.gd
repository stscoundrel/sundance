extends SceneTree
## His record, kept for his funeral (A Good Man Never Dies, phase 4; see Record):
##   kept    - a town won keeps what he did there (San Miguel: the condemned man,
##             the innocents, the wounded finished in the dirt, the men shot helping
##             their wounded, the priests dead); a town lost keeps nothing; a second
##             win writes over the first; the towns add up for the padre.
##   sins    - finishing a wounded man who isn't shooting back, and shooting a man
##             as he drags his wounded, each flash on screen and go on the record; a
##             priest dead goes on it however he died.
##   sermon  - the padre says nothing of a town never won.
##   forget  - "FORGET WHAT HE DID" asks once more, then wipes it.
##   (the test keeps its own file: the player's record is never touched)
##   godot --headless --path . --fixed-fps 60 -s tests/test_record.gd

const FILE := "user://test_record.json"

var game: Node
var frame := 0
var failures := 0
var step := ""


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "san_miguel")
	Engine.set_meta("no_gasp", true)
	Engine.set_meta("no_hanging", true)
	Engine.set_meta("record_file", FILE)
	Record.forget()
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
		game.begin()
		game.player.hp = 1000000
	if frame < 30:
		return false
	_api()
	_sins()
	_kept()
	_sermon()
	_forget()
	Record.forget()
	print("record test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)
	return true


func _api() -> void:
	step = "api"
	check(Record.towns().is_empty(), "a record before anything's kept")
	Record.keep("san_miguel", {"condemned": "saved", "innocents": 1, "downed_shot": 0})
	Record.keep("train", {"carriers_dead": 5, "innocents": 2, "downed_shot": 1})
	var m := Record.merged(Record.towns())
	check(m.get("condemned") == "saved" and int(m.get("innocents")) == 3 and int(m.get("carriers_dead")) == 5 and int(m.get("downed_shot")) == 1,
		"added up wrong: %s" % m)
	Record.keep("san_miguel", {"condemned": "hanged", "innocents": 0})
	check(Record.towns()["san_miguel"]["condemned"] == "hanged", "the second win didn't write over the first")
	Record.forget()
	check(Record.towns().is_empty(), "forgotten, but still there")


func _sins() -> void:
	step = "sins"
	var men: Array = game.enemies.filter(func(e): return e.alive)
	# a wounded man in the dirt, not shooting back, finished
	var w: Enemy = men[0]
	w.go_down(Vector2.RIGHT, game.player)
	check(w.downed, "he didn't go down")
	w.finish(game.player)
	check(int(game.stats.get("wounded men shot", 0)) == 1 and game.verdict_t > 0.0 and game.verdict_title == "A MAN IN THE DIRT",
		"finishing him: %s, '%s'" % [game.stats.get("wounded men shot", 0), game.verdict_title])
	# a man dragging his wounded, shot down
	var r: Enemy = men[1]
	r.rescuing = men[2]
	r.reaction = "rescue"
	r.take_hit(1000, Vector2.RIGHT, game.player)
	check(not r.alive and int(game.stats.get("rescuers shot", 0)) == 1 and game.verdict_title == "HE WAS HELPING HIS OWN",
		"shooting the rescuer: %s, '%s'" % [game.stats.get("rescuers shot", 0), game.verdict_title])
	# the padre, dead
	var padres: Array = game.civilians.filter(func(c): return c.priest)
	check(not padres.is_empty(), "no padre in San Miguel")
	if not padres.is_empty():
		padres[0].take_hit(1000, Vector2.RIGHT, game.player)
		check(int(game.stats.get("priests dead", 0)) == 1 and game.innocents >= 1, "the padre's death: %s" % game.stats.get("priests dead", 0))


func _kept() -> void:
	step = "kept"
	game._keep_record()   # (as a win does)
	var rec: Dictionary = Record.towns().get("san_miguel", {})
	check(rec.get("downed_shot") == 1 and rec.get("rescuers_shot") == 1 and rec.get("priests_dead") == 1 and rec.get("innocents") == game.innocents,
		"San Miguel's record: %s" % rec)
	check(not rec.has("captive") and not rec.has("carriers_dead"), "San Miguel asks for nothing of the sort: %s" % rec)
	Record.forget()
	game.end_level(false, "LOST")
	check(Record.towns().is_empty(), "a town lost was kept")


func _sermon() -> void:
	step = "sermon"
	var said: Array = Funeral.sermon({"condemned": "hanged", "innocents": 0}).map(func(l): return l["text"])
	check(said.any(func(s): return s.contains("San Miguel")), "nothing said of San Miguel")
	check(not said.any(func(s): return s.contains("Cruz Verde") or s.contains("Paso Esperanza") or s.contains("Silencio")),
		"spoke of towns never won: %s" % [said])


func _forget() -> void:
	step = "forget"
	Record.keep("san_miguel", {"condemned": "saved"})
	game.state = "levels"
	game.pick_level(game.levels.size())
	check(game.forget_armed and not Record.towns().is_empty(), "forgot it without asking twice")
	game.pick_level(game.levels.size())
	check(not game.forget_armed and Record.towns().is_empty(), "asked twice, still remembered")
