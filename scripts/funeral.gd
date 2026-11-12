class_name Funeral
extends Node
## The stranger's burial, as it runs (the map's "grave", the townsfolk placed with a
## "funeral" part: the padre's "sermon", the carpenter's "nails", the digger's
## "spade"). They're held to it ("bound") until it's over or he's out.
##
## A few seconds in, the padre reads his life over the coffin, a line at a time over
## his head: who he was, then what he did in every town he rode through (his record,
## see RECORDS), then the end of it. For each sin named the carpenter kneels to the
## lid and drives nails (WEIGHTS); a good deed he lets lie. The stranger can only lie
## still and listen (E hurries the padre on). At the Amen they lower him into the
## grave and the digger shovels the earth back in: that's his time to break out
## (see Coffin). With LOCKED nails or more in it the lid won't give, whatever he
## does. Filled in, he's buried, and that's the end of him: he lived by the gun, and
## by the gun he died.
##
## His record is what he did in the towns he's won (see Record), or one of the
## made-up RECORDS (--record=NAME, or the tests' meta).

const SERMON_AT := 3.0            # s after he rides in: the padre begins
const LINE_T := Vector2(2.6, 5.0) # s a line is said for, by its length
const PER_CHAR := 0.075
const HURRY := 0.4                # s a line is held at least, hurried on (E)
const NAIL_GAP := 0.4             # s between the carpenter's nails
const LOWER_T := 2.5              # s letting the coffin down
const FILL_T := 14.0              # s shovelling the earth back in
const LOCKED := 8                 # nails it takes to hold him for good
const SHOVEL := 1.1               # s a shovelful

# The nails a sin is worth: (count, nails a count, most nails); a good deed is worth none.
const WEIGHTS := {
	"condemned": [1, 1, 1],       # (the condemned man hanged in San Miguel)
	"captive": [1, 1, 1],         # (the captive dead at Cruz Verde)
	"carriers_dead": [4, 1, 3],   # one nail for every four carriers dead at Paso Esperanza
	"silencio_wiped": [1, 2, 2],  # every outlaw and every hunter dead, for the gold
	"innocents": [1, 1, 3],
	"priests_dead": [1, 2, 4],
}
# Made-up records, for trying the funeral out (--record=NAME) and for the tests.
const RECORDS := {
	"good": {"condemned": "saved", "captive": "saved", "carriers_dead": 2, "silencio_wiped": false,
		"innocents": 0, "priests_dead": 0},
	"middling": {"condemned": "hanged", "captive": "saved", "carriers_dead": 6, "silencio_wiped": false,
		"innocents": 1, "priests_dead": 0},
	"bad": {"condemned": "hanged", "captive": "dead", "carriers_dead": 9, "silencio_wiped": true,
		"innocents": 2, "priests_dead": 0},
	"worst": {"condemned": "hanged", "captive": "dead", "carriers_dead": 14, "silencio_wiped": true,
		"innocents": 4, "priests_dead": 1},
}

var game: Node
var coffin: Coffin
var padre: Civilian = null
var carpenter: Civilian = null
var digger: Civilian = null
var record: Dictionary
var lines: Array[Dictionary] = []   # each: text, nails
var phase := "wait"                 # wait, sermon, lower, fill, buried, out
var line := -1
var line_t := 0.0
var to_nail := 0
var nail_t := 0.0
var t := 0.0
var hole := Vector2.ZERO            # the grave's hole (screen)
var grave_spr: Sprite2D = null
var _shovel_t := 0.0


func setup(g: Node, c: Coffin, corner: Vector2, rec: Dictionary) -> void:
	game = g
	coffin = c
	record = rec
	hole = Iso.to_screen(corner + Vector2(1.1, 1.55))
	for r in g.placed:
		if r["type"] == "open_grave_empty":
			grave_spr = r["sprite"]
	for cv in g.civilians:
		match cv.tdata.get("funeral", ""):
			"sermon": padre = cv
			"nails": carpenter = cv
			"spade": digger = cv
	for cv in [padre, carpenter, digger]:
		if cv:
			cv.bound = true
	lines = sermon(rec)
	c.can_hammer = false
	c.burst_out.connect(_on_out)


## The nails a record's worth, all told.
static func nails_for(rec: Dictionary) -> int:
	var n := 0
	for k in WEIGHTS:
		n += _nails(k, rec.get(k, 0))
	return n


static func _nails(k: String, v) -> int:
	var w: Array = WEIGHTS[k]
	var count := 0
	if v is String:
		count = 1 if v in ["hanged", "dead"] else 0
	elif v is bool:
		count = 1 if v else 0
	else:
		count = int(v)
	return mini(int(ceil(count / float(w[0]))) * int(w[1]), int(w[2])) if count > 0 else 0


## What the padre says over him: the lines, and the nails each is worth.
static func sermon(rec: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var say := func(text: String, k := ""):
		out.append({"text": text, "nails": _nails(k, rec.get(k, 0)) if k != "" else 0})
	say.call("We are gathered to bury a stranger.")
	say.call("None here knew his name.")
	say.call("Every one of you knew his gun.")
	if rec.has("condemned"):   # (a town he's never won: the padre has nothing to say of it)
		say.call("In San Miguel he cut a man down from the rope." if rec["condemned"] == "saved"
			else "In San Miguel he let them hang a man.", "condemned")
	if rec.has("captive"):
		say.call("At Cruz Verde he brought the captive out alive." if rec["captive"] == "saved"
			else "At Cruz Verde he left the captive to die.", "captive")
	if rec.has("carriers_dead"):
		var carriers := int(rec["carriers_dead"])
		say.call("At Paso Esperanza the carriers all lived." if carriers == 0
			else "At Paso Esperanza, %d who carried the rifles died." % carriers, "carriers_dead")
	if rec.has("silencio_wiped"):
		say.call("At Silencio he left no man standing. For gold." if rec["silencio_wiped"]
			else "At Silencio he let men live, gold or no gold.", "silencio_wiped")
	var inn := int(rec.get("innocents", 0))
	if inn > 0:
		say.call("He shot a man who never wore a gun." if inn == 1 else "He shot %d who never wore a gun." % inn, "innocents")
	if int(rec.get("priests_dead", 0)) > 0:
		say.call("A man of God died where he passed.", "priests_dead")
	var n := nails_for(rec)
	if n >= LOCKED:
		say.call("He lived by the gun...")
		say.call("...and by the gun he died.")
	elif n == 0:
		say.call("A good man never dies.")
	else:
		say.call("May God weigh him kindly.")
	say.call("Amen.")
	return out


func _physics_process(delta: float) -> void:
	if game.state != "play":
		return
	t += delta
	match phase:
		"wait":
			if game.clock >= SERMON_AT:
				phase = "sermon"
				_next_line()
		"sermon":
			_sermon(delta)
		"lower":
			_lower(delta)
		"fill":
			_fill(delta)


func _sermon(delta: float) -> void:
	line_t -= delta
	if to_nail > 0:
		nail_t -= delta
		if nail_t <= 0.0:
			to_nail -= 1
			nail_t = NAIL_GAP
			coffin.nails += 1
			game.sfx("hammer", coffin.global_position, -4.0, 0.1)
			if carpenter:
				carpenter.pose = "hammer"
	elif carpenter:
		carpenter.pose = ""
	if padre:
		padre.pose = "bless" if fmod(t, 3.0) < 1.2 else ""
		padre.shout_t = maxf(padre.shout_t, line_t)
	if Input.is_action_just_pressed("knife") and coffin.inside:
		hurry()
	if line_t <= 0.0 and to_nail == 0:
		_next_line()


## E, lying in the box: the padre on to his next line (the nails still go in).
func hurry() -> void:
	line_t = minf(line_t, HURRY)
	nail_t = minf(nail_t, 0.1)


func _next_line() -> void:
	line += 1
	if line >= lines.size():
		_amen()
		return
	var l: Dictionary = lines[line]
	line_t = clampf(l["text"].length() * PER_CHAR, LINE_T.x, LINE_T.y)
	to_nail += int(l["nails"])
	nail_t = 0.6
	if padre and padre.alive:
		padre.shout = l["text"]
		padre.shout_t = line_t


## The last word: down he goes, and now he can try the lid.
func _amen() -> void:
	phase = "lower"
	t = 0.0
	if padre:
		padre.pose = ""
	if carpenter:
		carpenter.pose = ""
	coffin.can_hammer = true
	coffin.lower_to(hole, LOWER_T)
	game.stats["nails in the lid"] = coffin.nails


func _lower(_delta: float) -> void:
	if t >= LOWER_T:
		phase = "fill"
		t = 0.0
		if grave_spr:
			grave_spr.texture = game.tex(game.meta["objects"]["open_grave_in"]["file"])


func _fill(delta: float) -> void:
	if digger:
		digger.pose = "dig"
		digger.facing = (hole - digger.global_position).normalized()
		_shovel_t -= delta
		if _shovel_t <= 0.0:
			_shovel_t = SHOVEL
			game.sfx("sweep", hole, -8.0, 0.2)
	if t >= FILL_T:
		_buried()


## The earth over him, and the lid never gave: a fresh grave with a cross, and the end.
func _buried() -> void:
	phase = "buried"
	if grave_spr:
		grave_spr.visible = false
	game.fresh_grave(hole)
	_let_go()
	game.stats["buried"] = true
	game.end_level(false, "HE LIVED BY THE GUN", "and by the gun he died.   %d nails in the lid" % coffin.nails)


## He's out (see Coffin): the burial's over, and everyone's free to run.
func _on_out() -> void:
	phase = "out"
	if grave_spr and coffin.sunk:
		grave_spr.texture = game.tex(game.meta["objects"]["open_grave_empty"]["file"])
	_let_go()


func _let_go() -> void:
	for cv in [padre, carpenter, digger]:
		if cv and is_instance_valid(cv):
			cv.bound = false
			cv.pose = ""


## The fill so far, 0..1 (for the HUD).
func filled() -> float:
	return clampf(t / FILL_T, 0.0, 1.0) if phase == "fill" else (1.0 if phase == "buried" else 0.0)
