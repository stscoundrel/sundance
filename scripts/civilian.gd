class_name Civilian
extends Actor
## Townsfolk: unarmed, and only in the way. They idle and stroll near home. Gunfire
## close by or in view, a round cracking past or a man dropping in front of them
## sends them running for the nearest doorway that isn't towards the shooting (or off
## the edge of town) and they're gone; the faint-hearted cower first. One in five or
## so is a snitch, and a sharp eye can tell: honest folk glance at the stranger and
## look away, a snitch keeps staring and edges off towards the bandits. Given a good
## long look he hurries to the nearest one, points him out and shouts, then makes
## himself scarce. Once the town has been quiet a while they come back out.
## The undertaker and his apprentice ("role": "undertaker") work the quiet: each
## claims a dead bandit, measures him, and drags him to boot hill to be buried. The
## padre ("role": "priest") kneels and blesses the dead first, anyone at all, and
## the church bell tolls for each; he fears no man, and neither gunfire nor the
## stranger sends him running. A brave one ("brave": Cruz Verde's) doesn't even
## wait for it to go quiet: he goes to the dead with the shooting still going. Couples ("couple" in the placement) stroll arm in
## arm while all is calm, and scatter separately when it isn't. Mourners ("role":
## "mourner", placed "indoors") stay inside until there's a fresh grave and the town
## is quiet, then come out in black to stand at it a while, and go home again.
## The gunsmith ("role": "gunsmith") gathers up the guns the dead dropped, once the
## undertaker has the body away, four or five a trip, cartridges and all, and carries
## them into his shop. Shoot him and his armful spills round him.
## The mayor ("role": "mayor", with a "stump" to speak from) is all bluster: when
## the shooting starts he hurries out to the plaza and harangues the lot of them to
## stop. A round cracking past or a man dropping near him, and he's down on his
## knees, hat in hands, until it's calmer; then back to it. Once the town has gone
## quiet he tours the damage, hands behind his back, tutting at every wrecked crate
## and scorch mark.
## Once it's quiet the town puts itself right. The carpenter ("role": "carpenter")
## mends whatever wood is broken (crates, barrels, troughs, wagons, chairs, coops),
## the mayor's list first, and cover is cover again. The saloon keeper ("keeper")
## sets his own tables and chairs back up, bottles and all. Sweepers ("sweeper")
## sweep blood, glass and scorch into the dirt, the stranger's trail with it. Hen
## women ("henwife") shoo strays back home to the coops.
## The sister ("role": "sister", placed "indoors" in the chapel) fears no one either.
## At gunfire near the chapel she comes out to the door and calls the townsfolk in,
## and those running nearby make for her door. If the padre is shot she runs out to
## him, whatever's flying, and drags him in by the shoulders; what became of him
## nobody learns. With him gone she blesses the dead in his place, once it's quiet.
## The barber-surgeon ("role": "barber") minds his porch. Only gunfire close by sends
## him in, and he's back out once it's stopped near his shop, the quiet elsewhere or
## not. The stranger wounded within sight of his door, and nobody shooting at him:
## out he comes and binds him up where he stands (once a level). He'll do the same
## for any downed man near his shop, the gang's included: he gets paid either way.
## Out in Cruz Verde's cemetery the families of the revolution's dead ("visitor") go
## from grave to grave, and the grave digger ("digger") works down a row of open
## graves, a coffin waiting by each: dug, the coffin let down, filled in, and on to
## the next. There's nearly always shooting at the fort, so only gunfire by the
## graves or at the gate nearest them ("ward") scatters them, off the edge of the
## map, and they're back as soon as it's stopped there. Anyone else placed "local"
## (Cruz Verde's carpenter and sweepers) minds only gunfire close by in the same
## way, and gets on with the work without waiting for the whole town to go quiet.
## At Paso Esperanza the revolution's carriers ("role": "carrier", "load": "case" or
## "rifles") take the train's arms to the wagons, a load at a trip (see Cargo): bent
## to a pile, up with it, across to the wagon loading, in with it, and back. They've
## a fight going on the other side of the train the whole time, so only a round
## close by (or a man dropping beside them) sends them to the boxcars, load and all,
## and they're out again in a few seconds. Their comandante ("role": "leader")
## stands by the cargo waving them on and won't take cover for anyone; shoot him and
## they carry on just the same.

enum St { IDLE, WALK, FLEE, COWER, SNITCH, GONE, TO_BODY, MEASURE, DRAG, TO_BLESS, BLESS, TO_GRAVE, MOURN,
	TO_GUN, PICK, HAUL, TO_STUMP, ORATE, TO_SCAR, SURVEY, TO_FIX, FIX, TO_SWEEP, SWEEP, HERD,
	SHELTER, TO_PADRE, CARRY_IN, TO_PATIENT, TREAT, TO_DOWNED, TEND, TO_PIT, DIG,
	TO_LOAD, LOAD, TO_WAGON, STOW, BOARD }

const WALK := 18.0
const RUN := 52.0
const VIEW := 160.0
const FOV := deg_to_rad(65.0)
const CLOSE := 110.0     # gunfire this close frightens him even unseen
const HEAR := 320.0      # and this far off if he can see where it came from
const LOOK := 2.5        # seconds a snitch stares at the stranger before he runs to tell
const DRAG_SEE := 220.0   # px: close enough to see what the stranger's dragging
const SCREAM := 0.7       # chance he cries murder (else he hides)
const SCREAM_LINES := ["¡Asesino!", "Murder! Murder!", "¡Socorro!", "He's got a dead man!"]
const GLANCE := 0.9      # how long anyone else looks before averting his eyes
const FLEE_LINES := ["Lord help us!", "¡Corran!", "Get inside!"]
const SNITCH_LINES := ["There! A stranger!", "¡Allá, un gringo!"]
const MURDER_LINES := ["Murderer!", "¡Asesino!", "He shot him down!", "¡Dios mío!"]
const WORK := [St.TO_BODY, St.MEASURE, St.DRAG, St.TO_BLESS, St.BLESS, St.TO_GRAVE, St.MOURN, St.TO_GUN,
	St.PICK, St.HAUL, St.TO_STUMP, St.ORATE, St.TO_SCAR, St.SURVEY, St.TO_FIX, St.FIX, St.TO_SWEEP, St.SWEEP,
	St.HERD, St.SHELTER, St.TO_PADRE, St.CARRY_IN, St.TO_PATIENT, St.TREAT, St.TO_DOWNED, St.TEND, St.TO_PIT, St.DIG]
const MEASURE_T := 3.5
const BLESS_T := 4.0
const MOURN_T := Vector2(20.0, 32.0)
const PICK_T := 2.0
const GATHER_NEAR := 400.0   # once he has a gun in hand, he only goes on for ones this close
const ARM := 13.0          # how far beside him she walks
const DRAG_SPEED := 0.65   # of his walk, with a man in tow
const HUSH := 8.0          # s of quiet and the mayor steps down
const SURVEY_AFTER := 12.0 # s of quiet before he goes round the damage
const SURVEY_T := 3.5      # s tutting at each
const TOUR := 4            # wrecks a tour, then home
const FIX_T := 12.0        # s at a broken crate, barrel, wagon...
const MEND_T := 6.0        # s at a chair, table or coop
const SWEEP_T := 4.0       # s sweeping a spot
const GUNFIRE := ["shot", "enemy_shot", "blast"]
const SHELTER_EAR := 320.0 # px from the chapel door: gunfire this near brings the sister out to it
const SHELTER_FOR := 10.0  # s without a shot near it and she's back inside
const NEAR_FIRE := 220.0   # px: gunfire this close to the barber, or his door, sends him in
const SAFE_T := 6.0        # s since the last of it before he'll go out to anyone
const BACK_T := 12.0       # s, and he's back out on his porch anyway
const CARE_NEAR := 120.0   # px from his door: the stranger close enough for him to see to
const THREAT_NEAR := 300.0 # px: a bandit fighting the stranger within this, in sight of him, and he stays put
const TREAT_T := 5.0       # s binding the stranger up (his own bandage takes 10)
const TEND_T := 8.0        # s over a downed man
const TEND_NEAR := 180.0   # px from his door: downed men he'll go out to
const GRAVE_EAR := 220.0   # px: gunfire this near the cemetery folk (or their gate) scatters them
const RETURN_T := 8.0      # s without it there, and they're back
const CARRY_EAR := 90.0    # px: a round this near a carrier, or a man down this near, and he takes cover
const CARRY_BACK := 4.0    # s without one, and he's back out to it
const CARRY_WALK := 34.0   # px/s with a load (a case is heavy; an armful of rifles a little less so)
const CARRY_JOG := 44.0    # px/s back for the next
const LIFT_T := 1.4        # s bent to the pile for a load
const CARRY_SET := {"mg": "mgcarry"}
const CALL_AT := 5.0       # s in, the comandante's first call to them (his "call" line)   # (the pose set each load is carried in, where it isn't the load's own name)
const STOW_T := 1.0        # s heaving it into the wagon
const VISIT_T := Vector2(10.0, 18.0)   # s at each grave
const VISIT_NEAR := 320.0  # px from where she started: the graves she goes round
const DIG_T := 24.0        # s digging a grave out
const FILL_T := 12.0       # s filling it in over the coffin

static var rng := RandomNumberGenerator.new()   # the sister's and the barber's dice (the town's stay as seeded)

var kind := "townsman"
var tdata: Dictionary
var st := St.IDLE
var home := Vector2.ZERO
var path := PackedVector2Array()
var path_i := 0
var wait := 0.0
var walk := WALK
var run := RUN
var nerve := 0.5
var snitch := false
var threat := Vector2.ZERO
var desired := Vector2.DOWN
var saw_t := 0.0         # how long he's had the stranger in view
var watching := false    # eyes on the stranger this frame (he turns his head, not his walk)
var looked_away := false
var sidle := Vector2.ZERO  # a snitch drifting off towards the bandits
var seen_at := Vector2.ZERO
var cower_t := 0.0
var tell: Enemy          # the bandit a snitch is running to
var told_t := 0.0
var repath_t := 0.0
var hid_at := Vector2.ZERO   # the door he went in by, and comes back out of
var back_after := 0.0        # extra quiet he waits for before coming out
var inside_t := 0.0          # how long he's been indoors
var fade: Tween
var undertaker := false
var priest := false
var brave := false        # a padre who goes to the dead with the shooting still going on
var mourner := false
var mourning: Dictionary = {}   # the grave she's going to, or standing at
var gunsmith := false
var gun: Dictionary = {}        # the loose gun he's going for
var carried: Array[Dictionary] = []   # what he's gathered: {kind, ammo_kind}
var carrier := false         # one of the revolution's carriers, at the train
var carries := ""            # what he carries: "case" or "rifles"
var load_kind := ""          # what he has in his arms right now
var src: Dictionary = {}     # the pile he's making for (Cargo's)
var leader := false          # the carriers' comandante
var urge_t := 0.0
var called := false          # the comandante's had his first say
var boarded := false         # on the last wagon
var load_size := 5              # how many he'll carry this trip
var mayor := false
var stump := Vector2.INF        # where he makes his speeches
var orate_t := 0.0              # till his next line
var scar: Dictionary = {}       # the damage he's looking at
var toured := 0
var carpenter := false
var keeper := false
var sweeper := false
var henwife := false
var job: Dictionary = {}        # the broken thing he's mending
var dirt := Vector2.INF         # the mess she's sweeping
var hen: Chicken                # the stray she's shooing home
var knock_t := 0.0
var body: Actor              # the dead man he's seeing to
var partner: Civilian        # the other half of a couple
var leads := false           # he sets the way; she keeps to his arm
var work_t := 0.0
var grave := Vector2.ZERO
var trail := Vector2.ZERO    # where the last smear went down
var shout := ""
var shout_t := 0.0
var t := 0.0
var dice: RandomNumberGenerator   # null: the global dice, as the town always had
var sister := false
var barber := false
var near_shot := -100.0      # game.clock of the last gunfire near her door, or his shop
var patient: Actor           # the barber's: the stranger, or a downed man
var treated := false         # the stranger has had his once
var visitor := false
var digger := false
var wards := PackedVector2Array()   # where gunfire also concerns the cemetery folk: their gate
var pit: Dictionary = {}     # the open grave the digger's at
var kneel := false
var local := false           # minds only gunfire close by, and works through the rest
var condemned := false       # the man on the gallows (see Hanging)
var bound := false           # noosed and tied: going nowhere, whatever happens
var still := false           # hanged: he's done moving
var refuge := Vector2.INF    # where he runs once he's loose, if not just the nearest door


func setup(g: Node, k: String, pos: Vector2, facing_deg: float, overrides := {}) -> void:
	setup_body(g, pos)
	kind = k
	tdata = g.civilian_type(k, overrides)
	sister = tdata.get("role", "") == "sister"
	barber = tdata.get("role", "") == "barber"
	visitor = tdata.get("role", "") == "visitor"
	digger = tdata.get("role", "") == "digger"
	carrier = tdata.get("role", "") == "carrier"
	leader = tdata.get("role", "") == "leader"
	local = visitor or digger or carrier or tdata.get("local", false)
	condemned = tdata.get("role", "") == "condemned"
	if tdata.has("ward"):
		wards.append(Iso.to_screen(Vector2(tdata["ward"][0], tdata["ward"][1])))
	if sister or barber or local:
		dice = rng
	elif condemned:
		dice = Hanging.rng
	hp = 1
	max_hp = 1
	weapon = Weapon.new("unarmed", self)
	var palettes: Array = tdata["palettes"]
	set_character(tdata["template"], palettes[int(tdata.get("palette", _ri() % palettes.size())) % palettes.size()])
	walk = WALK * float(tdata["speed"])
	run = RUN * float(tdata["speed"])
	nerve = _rr(tdata["nerve"][0], tdata["nerve"][1])
	snitch = _rf() < float(tdata["snitch"])
	undertaker = tdata.get("role", "") == "undertaker"
	priest = tdata.get("role", "") == "priest"
	brave = priest and tdata.get("brave", false)
	mourner = tdata.get("role", "") == "mourner"
	gunsmith = tdata.get("role", "") == "gunsmith"
	mayor = tdata.get("role", "") == "mayor"
	carpenter = tdata.get("role", "") == "carpenter"
	keeper = tdata.get("role", "") == "keeper"
	sweeper = tdata.get("role", "") == "sweeper"
	henwife = tdata.get("role", "") == "henwife"
	if tdata.has("stump"):
		stump = Iso.to_screen(Vector2(tdata["stump"][0], tdata["stump"][1]))
	if undertaker:
		anim_gun = "tools"   # empty hands plus the tape and the haul
	elif priest:
		anim_gun = "prayer"  # a book in one hand, a blessing in the other
	elif mourner:
		anim_gun = "grief"   # hands clasped, and a handkerchief
	elif gunsmith:
		anim_gun = "smith"   # a gun held up to the light, and an armful of them
	elif mayor:
		anim_gun = "mayor"   # thumbs in his waistcoat, arms wide on the soapbox
	elif carpenter:
		anim_gun = "carpentry"   # a hammer in hand
	elif keeper:
		anim_gun = "keeper"      # a towel over his arm
	elif sweeper or henwife:
		anim_gun = "broom"
	elif sister:
		anim_gun = "nun"         # hands folded; beckoning, hauling, blessing
	elif barber:
		anim_gun = "barber"      # his bag, and the lint bandage
	elif visitor:
		anim_gun = "grief"
	elif digger:
		anim_gun = "spade"
	elif condemned:
		anim_gun = "bound"       # hands tied behind his back
	elif carrier:
		carries = tdata.get("load", "case")
		anim_gun = CARRY_SET.get(carries, carries)   # a case across his chest, an armful of rifles, a machine gun on his shoulder
		walk = CARRY_WALK * float(tdata["speed"])
	elif leader:
		anim_gun = "mayor"       # waving them on
		urge_t = CALL_AT         # (his first call a moment after the stranger's had his say)
	home = pos
	if sister:   # her place is the chapel's own doorstep, on open ground
		for d in g.doors:
			if d.distance_to(pos) < home.distance_to(pos) or home == pos:
				home = d
		global_position = home
	facing = Vector2.from_angle(deg_to_rad(facing_deg))
	desired = facing
	wait = _rr(1.0, 6.0)
	t = _rf() * 10.0
	if tdata.get("indoors", false):
		_go_inside(false)
		modulate.a = 0.0
		visible = false


# ------------------------------------------------------------------ senses

func sees(pos: Vector2) -> bool:
	var to := pos - global_position
	return to.length() < VIEW and abs(facing.angle_to(to)) < FOV and game.line_of_sight(global_position, pos, false)


## Gunfire: close, or in sight within earshot, and he's off.
func hear(pos: Vector2, radius: float, _k: String, source: Node) -> void:
	if bound:
		return
	if leader:
		return   # (he's heard worse)
	if (sister or barber or local) and alive:
		if _k in GUNFIRE and source != self:
			_hear_near(pos)
		return
	if not alive or st in [St.FLEE, St.COWER, St.GONE] or source == self:
		return
	var d := global_position.distance_to(pos)
	if d > minf(radius, HEAR):
		return
	if d < CLOSE or game.line_of_sight(global_position, pos, false):
		alarm(pos, false)


func near_miss(from: Vector2) -> void:
	alarm(from, true)


## The stranger hauling a dead man off: most cry murder (and the bandits hear);
## some, no friends of the gang, just get indoors and keep their mouths shut.
func _saw_drag(p: Player) -> void:
	set_meta("saw_drag", true)
	if _rf() < SCREAM:
		_say(_line("scream", SCREAM_LINES))
		game.make_noise(p.global_position, 340.0, "scream", self)
		game.stats["screams"] = game.stats.get("screams", 0) + 1
		alarm(p.global_position, true)
	else:
		game.stats["looks away"] = game.stats.get("looks away", 0) + 1
		alarm(p.global_position, false)   # (off indoors, without a word)


func witness_death(at: Vector2) -> void:
	if carrier and global_position.distance_to(at) > CARRY_EAR:
		return   # (men are dropping all round the train)
	if alive and global_position.distance_to(at) < 200.0 and game.line_of_sight(global_position, at, false):
		alarm(at, true)


## The stranger shot one of us: those who saw it say so.
func witness_murder(at: Vector2) -> void:
	if alive and st != St.GONE and global_position.distance_to(at) < 220.0 \
			and game.line_of_sight(global_position, at, false):
		_say(_pick(MURDER_LINES))
		alarm(at, true)


## Run for it, or (short of nerve, or caught close) cower first.
func alarm(from: Vector2, scary: bool) -> void:
	if not alive or st in [St.FLEE, St.GONE] or bound:
		return
	if barber:
		_duck_in()
		return
	if local:
		near_shot = game.clock   # (a fright of any kind: they give it a while before coming back)
	if carrier and not src.is_empty():
		game.cargo.release(src)   # (somebody else can have that pile)
		src = {}
	if priest or sister or leader:
		# a holy man (or the comandante): he stands his ground, and may have a word for it
		if shout_t <= 0.0 and _rf() < 0.4:
			_say(_line("calm", ["Peace, my son."]))
		return
	threat = from
	if mayor:
		_bluster(scary)
		return
	_drop_body()   # the dead can wait
	_leave_grave()
	_let_go_of_gun()
	_drop_job()
	if st == St.COWER:
		return
	var freeze := (1.0 - nerve) * (0.7 if scary else 0.4)
	if _rf() < freeze:
		st = St.COWER
		cower_t = _rr(2.0, 5.0)
		velocity = Vector2.ZERO
		return
	_flee()


## Cut loose (or shot down off the rope): off he runs for the nearest building, and
## stays in it. He's had enough of San Miguel's streets for one day.
func set_free(from: Vector2, thanks: String) -> void:
	bound = false
	still = false
	snitch = false
	anim_gun = ""   # (his hands his own again)
	pose = ""
	back_after = INF
	threat = from
	_say(thanks)
	_flee()
	shout = thanks   # (over whatever _flee had him cry)


func _flee() -> void:
	st = St.FLEE
	crouched = false
	hid_at = _west_edge() if visitor or digger else game.refuge_for(global_position, threat) if refuge == Vector2.INF else refuge
	path = game.find_path(global_position, hid_at)
	path_i = 0
	if _rf() < 0.5:
		_say(_line("flee", FLEE_LINES))
	game.stats["civilian flees"] = game.stats.get("civilian flees", 0) + 1


# ------------------------------------------------------------------ frame

func _physics_process(delta: float) -> void:
	t += delta
	if not alive:
		if dying():
			update_anim(delta)
		return
	if st == St.GONE:
		inside_t += delta
		if sister:
			_sister_inside()
			return
		if barber:
			_barber_inside()
			return
		if carrier:
			if game.state == "play" and inside_t > 2.0 and game.clock - near_shot > CARRY_BACK and not boarded:
				_come_out()
			return
		if local:
			if game.state == "play" and inside_t > 4.0 and game.clock - near_shot > RETURN_T:
				_come_out()
			return
		if game.state == "play" and inside_t > 10.0 and game.quiet_for() >= game.quiet_after + back_after:
			if not mourner:
				_come_out()
			else:
				_to_a_grave()
		return
	shout_t = max(0.0, shout_t - delta)
	if bound:
		if not still:
			update_anim(delta)   # (Hanging moves him, if anything does)
		return
	if game.state != "play" and game.state != "lost":
		velocity = Vector2.ZERO
		update_anim(delta)
		return
	pose = ""
	if game.state == "play":
		_perceive(delta)
	match st:
		St.IDLE, St.WALK when _on_his_arm():
			_escort()
		St.IDLE:
			_idle(delta)
		St.WALK:
			if leads and partner and partner._on_his_arm() and partner.global_position.distance_to(global_position) > ARM * 3.0:
				velocity = Vector2.ZERO   # waits for her to catch up
			elif _follow(walk):
				st = St.IDLE
				wait = _rr(2.0, 5.0) if leads else _rr(3.0, 8.0)
		St.FLEE:
			if _follow(run):
				_go_inside()
				return
		St.COWER:
			velocity = Vector2.ZERO
			crouched = true
			pose = "cower"
			cower_t -= delta
			if cower_t <= 0.0:
				if not mayor:
					_flee()
				elif game.quiet_for() < 3.0:
					cower_t = 1.0   # still shooting: he stays down
				else:
					crouched = false
					_to_stump()   # calmer: he picks himself up and starts again
		St.SNITCH:
			_snitch(delta)
		St.TO_BODY, St.MEASURE, St.DRAG:
			_work(delta)
		St.TO_BLESS, St.BLESS:
			_bless(delta)
		St.TO_GRAVE, St.MOURN:
			_mourn(delta)
		St.TO_GUN, St.PICK, St.HAUL:
			_gather(delta)
		St.TO_STUMP, St.ORATE, St.TO_SCAR, St.SURVEY:
			_mayor(delta)
		St.TO_FIX, St.FIX:
			_mend(delta)
		St.TO_SWEEP, St.SWEEP:
			_sweep(delta)
		St.HERD:
			_herd(delta)
		St.SHELTER, St.TO_PADRE, St.CARRY_IN:
			_sister(delta)
		St.TO_PATIENT, St.TREAT, St.TO_DOWNED, St.TEND:
			_barber(delta)
		St.TO_PIT, St.DIG:
			_dig(delta)
		St.TO_LOAD, St.LOAD, St.TO_WAGON, St.STOW, St.BOARD:
			_carry(delta)
	if (carried or load_kind != "") and pose == "":
		pose = "carry"
	if velocity.length() > 1.0 and not watching:
		desired = velocity.normalized()
	facing = facing.rotated(clamp(facing.angle_to(desired), -3.0 * delta, 3.0 * delta))
	move_and_slide()
	update_anim(delta)


func _perceive(delta: float) -> void:
	var p: Player = game.player
	watching = false
	if not p.alive or st in [St.FLEE, St.COWER, St.SNITCH] or st in WORK:
		return
	sidle = Vector2.ZERO
	if sees(p.global_position):
		saw_t += delta
		seen_at = p.global_position
		if p.dragging and not has_meta("saw_drag") and global_position.distance_to(p.global_position) < DRAG_SEE:
			_saw_drag(p)
			return
		var to_him := (p.global_position - global_position).normalized()
		if snitch:
			# the tell: he doesn't look away, and he starts drifting off to the bandits
			if saw_t > 0.3:
				watching = true
				desired = to_him
			if saw_t > 1.0:
				var b := _nearest_bandit()
				if b:
					sidle = (b.global_position - global_position).normalized()
			if saw_t > LOOK:
				_start_snitch()
		elif saw_t < GLANCE:
			if saw_t > 0.3:
				watching = true
				desired = to_him
		elif not looked_away:
			looked_away = true   # eyes down, none of his business
			desired = (-to_him).rotated(_rr(-1.2, 1.2))
	else:
		saw_t = max(0.0, saw_t - delta * 0.5)
		if saw_t == 0.0:
			looked_away = false


func _idle(delta: float) -> void:
	velocity = sidle * walk * 0.6
	wait -= delta
	if sister:
		_sister_idle()
		return
	if barber and _barber_idle():
		return
	if visitor:
		if wait <= 0.0:
			_next_grave()
		return
	if digger and _next_pit():
		return
	if carrier:
		if wait <= 0.0:
			_next_trip()
		return
	if leader:
		_lead(delta)
		return
	if mourner:
		_go_inside(false)   # home again, and in at the door
		return
	if undertaker and game.quiet_for() >= game.quiet_after:
		body = game.claim_body(self)
		if body:
			st = St.TO_BODY
			path = game.find_path(global_position, body.global_position)
			path_i = 0
			return
	if gunsmith and game.quiet_for() >= game.quiet_after:
		_next_gun()
		if st != St.IDLE:
			return
	if mayor:
		if game.quiet_for() < SURVEY_AFTER:
			toured = 0   # more damage to come, likely
		elif toured < TOUR:
			_next_scar()
			if st != St.IDLE:
				return
	if _calm() and _find_work():
		return
	if priest and (brave or game.quiet_for() >= game.quiet_after):
		body = game.blessing_for(self)
		if body:
			st = St.TO_BLESS
			path = game.find_path(global_position, body.global_position)
			path_i = 0
			return
	if not watching and not looked_away:
		desired = facing.rotated(sin(t * 0.4) * 0.02)
	if wait <= 0.0:
		var r: float = float(tdata["wander"])
		var to: Vector2 = game.free_point_near(home, r, dice) if r > 0.0 else home
		path = game.find_path(global_position, to)
		path_i = 0
		st = St.WALK


func _follow(speed: float) -> bool:
	while path_i < path.size() and global_position.distance_to(path[path_i]) < 4.0:
		path_i += 1
	if path_i >= path.size():
		velocity = Vector2.ZERO
		return true
	velocity = (path[path_i] - global_position).normalized() * speed
	return false


## Through the door (or off the edge of town): out of the story.
func _go_inside(hiding := true) -> void:
	st = St.GONE
	velocity = Vector2.ZERO
	occluded = false
	_sync_ghost()
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	hurtbox.set_deferred("collision_layer", 0)
	fade = create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.4)
	fade.tween_callback(func(): visible = false)
	inside_t = 0.0
	back_after = _rr(0.0, 15.0)   # they don't all come out at once
	if hiding:
		game.stats["civilian hides"] = game.stats.get("civilian hides", 0) + 1


## The town's been quiet long enough: back out the way he went in, and home.
func _come_out() -> void:
	st = St.WALK
	visible = true
	crouched = false
	saw_t = 0.0
	looked_away = false
	snitch = _rf() < float(tdata["snitch"])
	collision_layer = Iso.LAYER_ACTOR
	collision_mask = Iso.LAYER_WALL | Iso.LAYER_COVER | Iso.LAYER_POST | Iso.LAYER_ACTOR
	hurtbox.collision_layer = Iso.LAYER_HURT
	if fade:
		fade.kill()
	fade = create_tween()
	fade.tween_property(self, "modulate:a", 1.0, 0.5)
	path = game.find_path(global_position, home)
	path_i = 0
	if carrier:
		st = St.IDLE   # straight back to it, from the door
		wait = 0.0
	game.stats["civilian returns"] = game.stats.get("civilian returns", 0) + 1


# ------------------------------------------------------------------ the undertaker

func _work(delta: float) -> void:
	if body == null or body.has_meta("buried"):
		_drop_body()
		st = St.IDLE
		return
	match st:
		St.TO_BODY:
			if global_position.distance_to(body.global_position) < 14.0 or _follow(walk):
				st = St.MEASURE
				work_t = MEASURE_T
				velocity = Vector2.ZERO
				if _rf() < 0.6:
					_say(_line("work", ["Hm."]))
		St.MEASURE:
			# the tape out over him, head to boots
			velocity = Vector2.ZERO
			pose = "measure"
			desired = (body.global_position - global_position).normalized()
			work_t -= delta
			if work_t <= 0.0:
				grave = game.grave_spot()
				path = game.find_path(global_position, grave)
				path_i = 0
				trail = body.global_position
				st = St.DRAG
		St.DRAG:
			pose = "drag"
			var there := _follow(walk * DRAG_SPEED)
			if velocity.length() > 1.0:
				body.global_position = global_position - velocity.normalized() * 16.0
			if body.global_position.distance_to(trail) > 9.0:
				trail = body.global_position
				game.decals.add(trail, _rr(1.2, 2.2), Color(0.34, 0.07, 0.05, 0.4))
			if there:
				game.bury(body, grave)
				body = null
				st = St.IDLE
				wait = _rr(2.0, 4.0)


func _drop_body() -> void:
	if body and body.has_meta("claimed_by") and body.get_meta("claimed_by") == self:
		body.remove_meta("claimed_by")
	if body and body.has_meta("blessing_by") and body.get_meta("blessing_by") == self:
		body.remove_meta("blessing_by")
	crouched = false
	body = null


# ------------------------------------------------------------------ the padre

func _bless(delta: float) -> void:
	# gone, or already in the undertaker's hands: on to the next
	if body == null or body.has_meta("buried") or game.in_hand(body):
		_drop_body()
		st = St.IDLE
		return
	match st:
		St.TO_BLESS:
			if global_position.distance_to(body.global_position) < 16.0 or _follow(walk):
				st = St.BLESS
				work_t = BLESS_T
				velocity = Vector2.ZERO
				if _rf() < 0.7:
					_say(_line("work", ["Requiescat in pace."]))
		St.BLESS:
			# on one knee, the sign of the cross over him
			velocity = Vector2.ZERO
			crouched = true
			pose = "bless"
			desired = (body.global_position - global_position).normalized()
			work_t -= delta
			if work_t <= 0.0:
				body.set_meta("blessed", true)
				if priest:
					game.sfx("bell", null, -14.0, 0.0)   # the church bell, far off (the sister rings none)
				game.stats["blessings"] = game.stats.get("blessings", 0) + 1
				_drop_body()
				st = St.IDLE
				wait = _rr(1.5, 3.0)


# ------------------------------------------------------------------ mourners

## A fresh grave wants weeping over: out she comes, in black, and up to boot hill.
func _to_a_grave() -> void:
	var g: Dictionary = game.grave_to_mourn()
	if g.is_empty():
		return
	_come_out()
	mourning = g
	# beside the mound, a little apart from whoever else is there
	var spot: Vector2 = g["at"] + Vector2(_rr(-16.0, 16.0), _rr(10.0, 16.0))
	path = game.find_path(global_position, game.free_point_near(spot, 10.0))
	path_i = 0
	st = St.TO_GRAVE


func _mourn(delta: float) -> void:
	match st:
		St.TO_GRAVE:
			if _follow(walk):
				st = St.MOURN
				work_t = _rr(VISIT_T.x, VISIT_T.y) if visitor else _rr(MOURN_T.x, MOURN_T.y)
				kneel = visitor and _rf() < 0.4
				velocity = Vector2.ZERO
				if _rf() < 0.6:
					_say(_line("work", ["..."]))
		St.MOURN:
			velocity = Vector2.ZERO
			pose = "mourn"
			crouched = kneel
			desired = (mourning["at"] - global_position).normalized()
			work_t -= delta
			if work_t <= 0.0:
				mourning["done"] = true
				mourning = {}
				game.stats["mournings"] = game.stats.get("mournings", 0) + 1
				if visitor:   # on to another of them
					crouched = false
					st = St.IDLE
					wait = _rr(1.0, 3.0)
					return
				path = game.find_path(global_position, home)
				path_i = 0
				st = St.WALK


## Frightened off before she'd done: the grave is free for someone else.
func _leave_grave() -> void:
	if not mourning.is_empty():
		mourning["mourners"] -= 1
		mourning = {}


# ------------------------------------------------------------------ the gunsmith

## On to the next gun: the nearest one going, then only ones close by; with his
## arms full, or nothing more nearby, home with the lot.
func _next_gun() -> void:
	if carried.is_empty():
		load_size = _rir(4, 5)
	if carried.size() < load_size:
		gun = game.claim_gun(self, global_position, INF if carried.is_empty() else GATHER_NEAR)
		if not gun.is_empty():
			st = St.TO_GUN
			path = game.find_path(global_position, gun["at"])
			path_i = 0
			return
	if carried:
		st = St.HAUL
		path = game.find_path(global_position, home)
		path_i = 0


func _gather(delta: float) -> void:
	match st:
		St.TO_GUN:
			if not game.loose_guns.has(gun):
				_let_go_of_gun()
				st = St.IDLE
			elif global_position.distance_to(gun["at"]) < 12.0 or _follow(walk):
				st = St.PICK
				work_t = PICK_T
				velocity = Vector2.ZERO
		St.PICK:
			# down on one knee for it, then holding it up to the light
			velocity = Vector2.ZERO
			crouched = true
			pose = "pick"
			if not game.loose_guns.has(gun):
				_let_go_of_gun()
				st = St.IDLE
				return
			desired = (gun["at"] - global_position).normalized()
			work_t -= delta
			if work_t <= 0.0:
				game.take_gun(gun)
				carried.append({"kind": gun["kind"], "ammo_kind": gun["ammo_kind"]})
				if _rf() < 0.3:
					_say(_line("work", ["Hm."]))
				gun = {}
				crouched = false
				st = St.IDLE
				wait = 0.3
		St.HAUL:
			if _follow(walk):
				game.stats["guns stored"] = game.stats.get("guns stored", 0) + carried.size()
				carried.clear()
				_go_inside(false)   # into the shop with them


func _let_go_of_gun() -> void:
	if not gun.is_empty() and gun.get("claimed_by") == self:
		gun["claimed_by"] = null
	gun = {}
	crouched = false


# ------------------------------------------------------------------ the carriers

## A load in his arms: to the wagon with it. Empty-handed: to the next pile. With it
## all in, up on the last wagon.
func _next_trip() -> void:
	var cg: Cargo = game.cargo
	if cg == null:
		return
	if cg.done and load_kind == "":
		st = St.BOARD
		path = game.find_path(global_position, cg.wagon_at())
		path_i = 0
		return
	if load_kind != "":
		st = St.TO_WAGON
		path = game.find_path(global_position, cg.wagon_at())
		path_i = 0
		return
	src = cg.source_for(self)
	if src.is_empty() and tdata.has("then") and carries != tdata["then"]:
		carries = tdata["then"]   # the machine guns all gone: on to the cases
		anim_gun = CARRY_SET.get(carries, carries)
		src = cg.source_for(self)
	if src.is_empty():
		wait = 2.0   # nothing of his to carry: he waits on it
		return
	st = St.TO_LOAD
	path = game.find_path(global_position, src["at"])
	path_i = 0


func _carry(delta: float) -> void:
	var cg: Cargo = game.cargo
	match st:
		St.TO_LOAD:
			if not cg.sources.has(src):
				src = {}
				st = St.IDLE
			elif _follow(CARRY_JOG * float(tdata["speed"])):
				st = St.LOAD
				work_t = LIFT_T
		St.LOAD:
			velocity = Vector2.ZERO
			pose = "pick"
			desired = (src.get("at", global_position) - global_position).normalized() if not src.is_empty() else desired
			work_t -= delta
			if work_t <= 0.0:
				if cg.take(src):
					load_kind = carries
					if _rf() < 0.25:
						_say(_line("work", ["¡Ándale!"]))
				src = {}
				st = St.IDLE
		St.TO_WAGON:
			var to: Vector2 = cg.wagon_at()
			if path.size() > 0 and path[path.size() - 1].distance_to(to) > 30.0:
				path = game.find_path(global_position, to)   # that one's gone: the next
				path_i = 0
			if _follow(walk):
				st = St.STOW
				work_t = STOW_T
		St.STOW:
			velocity = Vector2.ZERO
			pose = "pick"
			work_t -= delta
			if work_t <= 0.0:
				cg.stow(self)
				load_kind = ""
				st = St.IDLE
		St.BOARD:
			if _follow(CARRY_JOG * float(tdata["speed"])):
				board()


## Up on the wagon, out of sight in it.
func board() -> void:
	boarded = true
	_go_inside(false)


## The comandante: by the cargo, turned to whoever's carrying, waving them on.
func _lead(delta: float) -> void:
	velocity = Vector2.ZERO
	urge_t -= delta
	var near: Civilian = null
	for c in game.civilians:
		if c.carrier and c.alive and c.visible and (near == null or
				c.global_position.distance_to(global_position) < near.global_position.distance_to(global_position)):
			near = c
	if near:
		desired = (near.global_position - global_position).normalized()
	if urge_t < 2.0:
		pose = "orate"
	if urge_t <= 0.0:
		urge_t = _rr(5.0, 9.0)
		if not called and tdata["shouts"].has("call"):
			called = true
			_say(_line("call", ["¡Ándale, muchachos!"]))   # (his own, first of all)
			shout_t = 3.5
		else:
			_say(_line("urge", ["¡Ándale, muchachos!"]))


## Every load in.
func say_done() -> void:
	_say(_line("done", ["¡Vámonos, muchachos!"]))
	st = St.BOARD
	path = game.find_path(global_position, game.cargo.wagon_at())
	path_i = 0


# ------------------------------------------------------------------ the mayor

## Gunfire: out to his soapbox to tell them all to stop. Something close and
## frightening, though, and he's on his knees.
func _bluster(scary: bool) -> void:
	if scary:
		if st != St.COWER:
			st = St.COWER
			velocity = Vector2.ZERO
			_say(_line("cower", ["Don't shoot!"]))
			game.stats["mayor cowers"] = game.stats.get("mayor cowers", 0) + 1
		cower_t = _rr(2.5, 4.5)
		return
	if st == St.COWER or st == St.TO_STUMP or st == St.ORATE:
		return
	_to_stump()


func _to_stump() -> void:
	scar = {}
	st = St.TO_STUMP
	var at := stump if stump != Vector2.INF else home
	path = game.find_path(global_position, at if game.is_free(at) else game.free_point_near(at, 20.0))
	path_i = 0


## Hurrying out, then holding forth; down again once it's been quiet a while. Then,
## when it's been quiet longer, round the damage one wreck at a time.
func _mayor(delta: float) -> void:
	if st in [St.TO_STUMP, St.ORATE] and game.quiet_for() >= HUSH:
		st = St.IDLE
		wait = _rr(2.0, 4.0)
		return
	match st:
		St.TO_STUMP:
			if _follow(run * 0.75):
				st = St.ORATE
				orate_t = 0.3
		St.ORATE:
			velocity = Vector2.ZERO
			pose = "orate"
			desired = (threat - global_position).normalized()
			orate_t -= delta
			if orate_t <= 0.0:
				orate_t = _rr(3.0, 4.5)
				_say(_line("calm", ["Gentlemen, please!"]))
				game.stats["mayor speeches"] = game.stats.get("mayor speeches", 0) + 1
		St.TO_SCAR:
			pose = "survey"
			if _follow(walk):
				st = St.SURVEY
				work_t = SURVEY_T
		St.SURVEY:
			velocity = Vector2.ZERO
			pose = "survey"
			desired = (scar["at"] - global_position).normalized()
			work_t -= delta
			if work_t <= SURVEY_T - 0.6 and work_t + delta > SURVEY_T - 0.6 and _rf() < 0.75:
				_say(_line("work", ["Tsk."]))
			if work_t <= 0.0:
				game.stats["damage surveyed"] = game.stats.get("damage surveyed", 0) + 1
				toured += 1
				scar = {}
				st = St.IDLE
				wait = 0.5


## The next wreck to tut over, or home when there's none (or he's seen enough).
func _next_scar() -> void:
	scar = game.scar_to_survey(global_position) if toured < TOUR else {}
	if scar.is_empty():
		if toured > 0 and global_position.distance_to(home) > 10.0:
			path = game.find_path(global_position, home)
			path_i = 0
			st = St.WALK
		toured = TOUR   # done for now
		return
	var at: Vector2 = scar["at"] + Vector2.from_angle(_rf() * TAU) * 22.0 * Vector2(1.0, 0.5)
	path = game.find_path(global_position, at if game.is_free(at) else game.free_point_near(at, 20.0))
	path_i = 0
	st = St.TO_SCAR


# ------------------------------------------------------------------ the town tidies up

## The quiet's back: anything for him to see to?
func _find_work() -> bool:
	if carpenter or keeper:
		job = game.repair_job(self)
		if not job.is_empty():
			var at: Vector2 = game.job_at(job)
			var stand := at + (global_position - at).normalized() * 16.0
			path = game.find_path(global_position, stand if game.is_free(stand) else game.free_point_near(stand, 16.0, dice))
			path_i = 0
			st = St.TO_FIX
			return true
	if sweeper:
		dirt = game.dirt_job(self)
		if dirt != Vector2.INF:
			path = game.find_path(global_position, dirt if game.is_free(dirt) else game.free_point_near(dirt, 12.0, dice))
			path_i = 0
			st = St.TO_SWEEP
			return true
	if henwife:
		hen = game.stray_hen(self)
		if hen:
			st = St.HERD
			work_t = 40.0   # (she gives up on one that won't be shooed)
			repath_t = 0.0
			return true
		job = game.laundry_job(self)   # the washing shot through, or down in the dirt: out again
		if not job.is_empty():
			var at: Vector2 = game.job_at(job)
			path = game.find_path(global_position, at if game.is_free(at) else game.free_point_near(at, 14.0))
			path_i = 0
			st = St.TO_FIX
			return true
	return false


func _mend(delta: float) -> void:
	if job.is_empty() or job["state"] == 0:
		_drop_job()
		st = St.IDLE
		return
	match st:
		St.TO_FIX:
			if _follow(walk):
				st = St.FIX
				work_t = MEND_T if keeper or not job.has("hp") else FIX_T
				knock_t = 0.0
		St.FIX:
			velocity = Vector2.ZERO
			desired = (game.job_at(job) - global_position).normalized()
			if keeper:
				pose = "tidy"
			elif henwife:
				pose = "shoo"   # (pegging it out again)
			else:
				crouched = true
				pose = "hammer"
				knock_t -= delta
				if knock_t <= 0.0:
					knock_t = 1.1
					game.sfx("hammer", global_position, -12.0, 0.1, dice)
			work_t -= delta
			if work_t > 0.0:
				return
			if game.in_the_way(job, self):
				work_t = 1.0   # someone's standing right there
				return
			game.repair(job)
			job = {}
			crouched = false
			if _rf() < 0.5:
				_say(_line("work", ["There."]))
			st = St.IDLE
			wait = 0.4


func _sweep(delta: float) -> void:
	match st:
		St.TO_SWEEP:
			if _follow(walk):
				st = St.SWEEP
				work_t = SWEEP_T
				knock_t = 0.0
		St.SWEEP:
			velocity = Vector2.ZERO
			pose = "sweep"
			desired = (dirt - global_position).normalized() if global_position.distance_to(dirt) > 4.0 else desired
			knock_t -= delta
			if knock_t <= 0.0:
				knock_t = 0.9
				game.sfx("sweep", global_position, -14.0, 0.15, dice)
			work_t -= delta
			if work_t <= 0.0:
				game.sweep_at(dirt, self)
				dirt = Vector2.INF
				if _rf() < 0.2:
					_say(_line("work", ["..."]))
				st = St.IDLE
				wait = 0.3


## Round behind the stray, broom up, and on towards the coop she goes.
func _herd(delta: float) -> void:
	work_t -= delta
	if hen == null or not is_instance_valid(hen) or not hen in game.hens or work_t <= 0.0:
		_drop_job()
		st = St.IDLE
		wait = 0.5
		return
	if hen.st != Chicken.S.HERD and hen.herder != self:
		_drop_job()
		st = St.IDLE
		return
	var coop: Dictionary = game.coop_for(hen.position)
	var ahead: Vector2 = hen.heading() if hen.st == Chicken.S.HERD else coop["at"]
	var behind: Vector2 = hen.position + (hen.position - ahead).normalized() * 16.0
	if global_position.distance_to(behind) > 12.0:
		repath_t -= delta
		if repath_t <= 0.0 or path_i >= path.size():
			repath_t = 0.8
			path = game.find_path(global_position, behind if game.is_free(behind) else hen.position)
			path_i = 0
		_follow(run * 0.55 if hen.st == Chicken.S.HERD else walk * 1.2)
	else:
		velocity = (behind - global_position) * 2.0
	pose = "shoo"
	if hen.st != Chicken.S.HERD and global_position.distance_to(hen.position) < 26.0:
		hen.herd(coop)
		if shout_t <= 0.0 and _rf() < 0.5:
			_say(_line("work", ["¡Fuera!"]))


## Frightened off (or done): whatever he'd taken on is free for someone else.
func _drop_job() -> void:
	if not job.is_empty() and job.get("fixer") == self:
		job["fixer"] = null
	job = {}
	if dirt != Vector2.INF:
		game.sweeping.erase(self)
		dirt = Vector2.INF
	if hen and is_instance_valid(hen) and hen.herder == self:
		hen.herder = null
		if hen.st == Chicken.S.HERD:
			hen.st = Chicken.S.PECK
	hen = null


# ------------------------------------------------------------------ the sister

## Gunfire: to her it means folk to get indoors; to him, his shop's in the line of it.
func _hear_near(pos: Vector2) -> void:
	if carrier:
		if pos.distance_to(global_position) < CARRY_EAR:
			near_shot = game.clock
			if not st in [St.FLEE, St.GONE, St.COWER, St.BOARD]:
				alarm(pos, false)
		return
	if local:
		var near := pos.distance_to(global_position) < GRAVE_EAR or pos.distance_to(home) < GRAVE_EAR
		for w in wards:
			near = near or pos.distance_to(w) < GRAVE_EAR
		if near:
			near_shot = game.clock
			if not st in [St.FLEE, St.GONE, St.COWER]:
				alarm(pos, false)
		return
	if sister:
		if pos.distance_to(home) < SHELTER_EAR or pos.distance_to(global_position) < SHELTER_EAR:
			near_shot = game.clock
			if st in [St.IDLE, St.WALK, St.TO_BLESS, St.BLESS]:
				_drop_body()
				_shelter()
		return
	if pos.distance_to(home) < NEAR_FIRE or pos.distance_to(global_position) < NEAR_FIRE:
		near_shot = game.clock
		_duck_in()


## Indoors in the chapel: out to the padre if he's down, to the door if there's
## shooting, and out to the dead once it's quiet if he's not there to see to them.
func _sister_inside() -> void:
	if game.state != "play":
		return
	var padre: Civilian = _fallen_padre()
	if padre:
		_come_out()
		_to_padre(padre)
	elif game.clock - near_shot < SHELTER_FOR and inside_t > 0.5:
		_come_out()
		_shelter()
	elif inside_t > 10.0 and _padre_gone() and game.quiet_for() >= game.quiet_after + back_after:
		var b: Actor = game.blessing_for(self)
		if b:
			_come_out()
			_to_bless(b)


func _sister_idle() -> void:
	velocity = Vector2.ZERO
	if _padre_gone() and game.quiet_for() >= game.quiet_after:
		var b: Actor = game.blessing_for(self)
		if b:
			_to_bless(b)
			return
	if global_position.distance_to(home) > 6.0:
		path = game.find_path(global_position, home)
		path_i = 0
		st = St.WALK
		return
	_go_inside(false)


func _to_bless(b: Actor) -> void:
	body = b
	st = St.TO_BLESS
	path = game.find_path(global_position, b.global_position)
	path_i = 0


## The padre shot, and nobody yet gone to him.
func _fallen_padre() -> Civilian:
	for c in game.civilians:
		if c.priest and not c.alive and not c.has_meta("buried") \
				and (not c.has_meta("rescued_by") or c.get_meta("rescued_by") == self):
			return c
	return null


## No padre about to see to the dead: shot, or taken in.
func _padre_gone() -> bool:
	return not game.civilians.any(func(c): return c.priest and c.alive)


func _shelter() -> void:
	st = St.SHELTER
	path = game.find_path(global_position, home)
	path_i = 0
	orate_t = 0.4


func _to_padre(p: Civilian) -> void:
	body = p
	p.set_meta("rescued_by", self)
	st = St.TO_PADRE
	path = game.find_path(global_position, p.global_position)
	path_i = 0
	_say(_line("rescue", ["Father!"]))
	game.stats["padre rescues"] = game.stats.get("padre rescues", 0) + 1


func _sister(delta: float) -> void:
	match st:
		St.SHELTER:
			var padre: Civilian = _fallen_padre()
			if padre:
				_to_padre(padre)
				return
			if _follow(run * 0.8):
				# in the doorway, waving them in
				pose = "beckon"
				var near: Civilian = _nearest_fleeing()
				desired = (near.global_position - global_position).normalized() if near \
					else (game.last_gunfire_at - global_position).normalized()
				orate_t -= delta
				if orate_t <= 0.0:
					orate_t = _rr(2.5, 4.0)
					_say(_line("shelter", ["In here!"]))
				if game.clock - near_shot > SHELTER_FOR:
					_go_inside(false)
		St.TO_PADRE:
			if global_position.distance_to(body.global_position) < 14.0 or _follow(run):
				st = St.CARRY_IN
				path = game.find_path(global_position, home)
				path_i = 0
				trail = body.global_position
		St.CARRY_IN:
			# by the shoulders, backwards to the chapel door, as fast as she can
			pose = "drag"
			var there := _follow(walk * DRAG_SPEED * 1.2)
			if velocity.length() > 1.0:
				body.global_position = global_position - velocity.normalized() * 16.0
			if body.global_position.distance_to(trail) > 9.0:
				trail = body.global_position
				game.decals.add(trail, _rr(1.2, 2.2), Color(0.34, 0.07, 0.05, 0.4))
			if there:
				_take_in(body)
				body = null
				_go_inside(false)


## In through the door with him, and that's the last anyone sees of the padre.
func _take_in(p: Actor) -> void:
	p.set_meta("buried", true)   # (out of the story, as a buried man is)
	p.set_meta("taken_in", true)
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): p.visible = false)
	game.stats["padre taken in"] = 1


func _nearest_fleeing() -> Civilian:
	var best := 260.0
	var out: Civilian = null
	for c in game.civilians:
		if c != self and c.alive and c.st == St.FLEE:
			var d: float = global_position.distance_to(c.global_position)
			if d < best:
				best = d
				out = c
	return out


# ------------------------------------------------------------------ the barber-surgeon

## Shooting near his shop: in he goes, whoever he was seeing to.
func _duck_in() -> void:
	if st in [St.FLEE, St.GONE]:
		return
	_let_go_of_patient()
	st = St.FLEE
	crouched = false
	hid_at = home
	path = game.find_path(global_position, home)
	path_i = 0
	if shout_t <= 0.0 and _rf() < 0.5:
		_say(_line("flee", FLEE_LINES))
	game.stats["barber ducks in"] = game.stats.get("barber ducks in", 0) + 1


func _barber_inside() -> void:
	if game.state != "play" or inside_t < 3.0 or game.clock - near_shot < SAFE_T:
		return
	if _wants_care() or _downed_near() or game.clock - near_shot >= BACK_T:
		_come_out()


## Anyone for him? The stranger first, then a man lying in the dirt nearby.
func _barber_idle() -> bool:
	if game.clock - near_shot < SAFE_T:
		return false
	if _wants_care():
		patient = game.player
		st = St.TO_PATIENT
		repath_t = 0.0
		_say(_line("care", ["Hold still."]))
		return true
	var d: Enemy = _downed_near()
	if d:
		patient = d
		d.medic = self
		st = St.TO_DOWNED
		path = game.find_path(global_position, d.global_position)
		path_i = 0
		return true
	return false


## The stranger hurt, close by his door and in sight of it, and nobody at him.
func _wants_care() -> bool:
	var p: Player = game.player
	if treated or not p.alive or game.state != "play" or game.clock - near_shot < SAFE_T:
		return false
	if p.hp >= p.max_hp and not p.bleeding and p.limp_t <= 0.0 and not p.down:
		return false
	if p.global_position.distance_to(home) > CARE_NEAR or not game.line_of_sight(home, p.global_position, false):
		return false
	return not _under_fire(p)


func _under_fire(p: Player) -> bool:
	for e in game.enemies:
		if e.alive and e.revealed and e.st == Enemy.St.COMBAT \
				and e.global_position.distance_to(p.global_position) < THREAT_NEAR \
				and game.line_of_sight(e.global_position, p.global_position, false):
			return true
	return false


## A downed man near the shop that none of his own have come for.
func _downed_near() -> Enemy:
	var best := TEND_NEAR
	var out: Enemy = null
	for e in game.enemies:
		if not e.downed or e.rescuer != null or e.gasp != "" or (e.medic != null and e.medic != self):
			continue
		var d: float = e.global_position.distance_to(home)
		if d < best:
			best = d
			out = e
	return out


func _barber(delta: float) -> void:
	match st:
		St.TO_PATIENT:
			var p: Player = game.player
			if not p.alive or p.global_position.distance_to(home) > CARE_NEAR * 1.6 or _under_fire(p):
				_send_home()
				return
			if global_position.distance_to(p.global_position) < 16.0:
				st = St.TREAT
				work_t = TREAT_T
				p.medic = self
				game.sfx("tear", global_position, -8.0, 0.1, dice)
				return
			repath_t -= delta
			if repath_t <= 0.0 or path_i >= path.size():
				repath_t = 0.5
				path = game.find_path(global_position, p.global_position)
				path_i = 0
			_follow(run * 0.6)
		St.TREAT:
			# binding him up where he stands (or lies): he keeps still, or it's to start over
			var p: Player = game.player
			velocity = Vector2.ZERO
			desired = (p.global_position - global_position).normalized()
			crouched = p.down
			pose = "tend" if p.down else "treat"
			if not p.alive or p.velocity.length() > 1.0 or global_position.distance_to(p.global_position) > 22.0:
				p.medic = null
				crouched = false
				st = St.TO_PATIENT
				return
			work_t -= delta
			if work_t <= 0.0:
				p.medic = null
				p.patched_up()
				treated = true
				_say(_line("done", ["There."]))
				_send_home()
		St.TO_DOWNED:
			var d := patient as Enemy
			if d == null or not is_instance_valid(d) or not d.downed or d.rescuer != null or d.gasp != "":
				_send_home()
				return
			if global_position.distance_to(d.global_position) < 14.0 or _follow(run * 0.6):
				st = St.TEND
				work_t = TEND_T
				game.sfx("tear", global_position, -8.0, 0.1, dice)
				if _rf() < 0.6:
					_say(_line("tend", ["Easy."]))
		St.TEND:
			var d := patient as Enemy
			if d == null or not is_instance_valid(d) or not d.downed or d.gasp != "":
				_send_home()
				return
			velocity = Vector2.ZERO
			crouched = true
			pose = "tend"
			desired = (d.global_position - global_position).normalized()
			work_t -= delta
			if work_t <= 0.0:
				d.medic = null
				d.revive()
				game.stats["barber saves"] = game.stats.get("barber saves", 0) + 1
				_send_home()


## Done, or given up on him: back to the porch.
func _send_home() -> void:
	_let_go_of_patient()
	crouched = false
	st = St.WALK
	path = game.find_path(global_position, home)
	path_i = 0


func _let_go_of_patient() -> void:
	if patient is Enemy and is_instance_valid(patient) and (patient as Enemy).medic == self:
		(patient as Enemy).medic = null
	if patient is Player and (patient as Player).medic == self:
		(patient as Player).medic = null
	patient = null
	crouched = false


## Quiet enough to get on with the work: the whole town quiet a while, or, for
## those who only mind what's close, nothing near them for a few seconds.
func _calm() -> bool:
	return game.clock - near_shot > RETURN_T if local else game.quiet_for() >= game.quiet_after


# ------------------------------------------------------------------ the cemetery

## Another grave to stand at: a fresh one if there's one nobody's wept over, else one
## of the old ones round about.
func _next_grave() -> void:
	var g: Dictionary = game.grave_to_mourn()
	if g.is_empty():
		var near: Array[Vector2] = []
		for p in game.old_graves:
			if p.distance_to(home) < VISIT_NEAR:
				near.append(p)
		if near.is_empty():
			return
		g = {"at": near[_ri() % near.size()], "mourners": 1, "done": false}
	mourning = g
	var spot: Vector2 = g["at"] + Vector2(_rr(-14.0, 14.0), _rr(10.0, 16.0))
	path = game.find_path(global_position, spot if game.is_free(spot) else game.free_point_near(spot, 12.0, dice))
	path_i = 0
	st = St.TO_GRAVE


## Off the west edge of the map: the cemetery's nearest way out of it all.
func _west_edge() -> Vector2:
	var g := Iso.to_grid(global_position)
	for dy in [0.0, 1.0, -1.0, 2.0, -2.0, 3.0, -3.0]:
		var e := Iso.to_screen(Vector2(0.6, g.y + dy))
		if game.is_free(e):
			return e
	return game.refuge_for(global_position, threat)


## The next open grave in his row, the nearest first.
func _next_pit() -> bool:
	var best := INF
	pit = {}
	for gr in game.open_graves:
		if gr["done"] or (gr["digger"] != null and gr["digger"] != self):
			continue
		var d: float = global_position.distance_to(gr["at"])
		if d < best:
			best = d
			pit = gr
	if pit.is_empty():
		return false
	pit["digger"] = self
	var stand := Iso.to_screen(pit["g"] + Vector2(2.45, 1.55))   # at the end of it
	path = game.find_path(global_position, stand if game.is_free(stand) else game.free_point_near(stand, 10.0, dice))
	path_i = 0
	st = St.TO_PIT
	return true


func _dig(delta: float) -> void:
	match st:
		St.TO_PIT:
			if _follow(walk):
				st = St.DIG
				knock_t = 0.0
		St.DIG:
			velocity = Vector2.ZERO
			pose = "dig"
			desired = (pit["at"] - global_position).normalized()
			knock_t -= delta
			if knock_t <= 0.0:
				knock_t = 2.0   # (a spadeful a turn of the swing)
				game.sfx("sweep", global_position, -16.0, 0.2, dice)
			if not pit["in"]:
				pit["dug"] += delta
				if pit["dug"] >= DIG_T:
					game.lower_coffin(pit)
					if _rf() < 0.6:
						_say(_line("work", ["Hm."]))
			else:
				pit["filled"] += delta
				if pit["filled"] >= FILL_T:
					game.fill_grave(pit)
					pit = {}
					st = St.IDLE
					wait = _rr(2.0, 4.0)


# ------------------------------------------------------------------ couples

## She's on his arm while they're both just out for a stroll.
func _on_his_arm() -> bool:
	return partner != null and not leads and partner.alive and partner.st in [St.IDLE, St.WALK] \
		and st in [St.IDLE, St.WALK]


func _escort() -> void:
	var at := partner.global_position + partner.facing.orthogonal() * ARM
	var d := global_position.distance_to(at)
	if d > ARM * 2.0 or not game.clear_path(global_position, at):
		# fallen behind, or something in the way: find her way round to him
		repath_t -= get_physics_process_delta_time()
		if repath_t <= 0.0 or path_i >= path.size():
			repath_t = 0.6
			path = game.find_path(global_position, partner.global_position)
			path_i = 0
		_follow(run * 0.7)
	elif d > 3.0:
		velocity = (at - global_position).normalized() * minf(run * 0.7, maxf(walk, d * 3.0))
	else:
		velocity = Vector2.ZERO
		if not watching:
			desired = partner.facing


# ------------------------------------------------------------------ snitching

func _nearest_bandit() -> Enemy:
	var best := 420.0
	var out: Enemy = null
	for e in game.enemies:
		if e.alive and e.st != Enemy.St.COMBAT:
			var d := global_position.distance_to(e.global_position)
			if d < best:
				best = d
				out = e
	return out


func _start_snitch() -> void:
	tell = _nearest_bandit()
	snitch = false   # once is enough
	if tell == null:
		return
	st = St.SNITCH
	told_t = 0.0
	repath_t = 0.0
	game.stats["snitch runs"] = game.stats.get("snitch runs", 0) + 1


func _snitch(delta: float) -> void:
	if tell == null or not tell.alive:
		_flee_from(seen_at)
		return
	if told_t > 0.0:
		# pointing the way, then off he goes
		told_t -= delta
		velocity = Vector2.ZERO
		pose = "point"
		desired = (seen_at - global_position).normalized()
		if told_t <= 0.0:
			_flee_from(seen_at)
		return
	if global_position.distance_to(tell.global_position) < 34.0:
		_say(_line("snitch", SNITCH_LINES))
		told_t = 1.8
		tell.enter_combat(seen_at, false, true)
		game.stats["snitch tells"] = game.stats.get("snitch tells", 0) + 1
		return
	repath_t -= delta
	if repath_t <= 0.0:
		repath_t = 1.0
		path = game.find_path(global_position, tell.global_position)
		path_i = 0
	_follow(run * 0.8)


func _flee_from(at: Vector2) -> void:
	threat = at
	_flee()


# ------------------------------------------------------------------ talk

func _say(s: String) -> void:
	shout = s
	shout_t = 1.8


func _line(key: String, stock: Array) -> String:
	var own: Dictionary = tdata.get("shouts", {})
	return _pick(own[key] if own.has(key) else stock)


func gone() -> bool:
	return st == St.GONE


# ------------------------------------------------------------------ dice

func _rf() -> float:
	return dice.randf() if dice else randf()


func _rr(a: float, b: float) -> float:
	return dice.randf_range(a, b) if dice else randf_range(a, b)


func _ri() -> int:
	return dice.randi() if dice else randi()


func _rir(a: int, b: int) -> int:
	return dice.randi_range(a, b) if dice else randi_range(a, b)


func _pick(a: Array) -> Variant:
	return a[dice.randi() % a.size()] if dice else a.pick_random()
