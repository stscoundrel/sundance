class_name Weapon
extends RefCounted
## Period-authentic firearms, described by data. Three kinds of action:
##   revolver - Colt Single Action Army: six chambers, cocked per shot, gate loading.
##              A pair ("twin") holds twelve, fired right hand, left hand, in turn.
##   lever    - Winchester 1866: tube magazine, a lever stroke between shots
##   breech   - everything that opens to load: coach gun, sawn-off, derringer, Sharps,
##              howdah.
##              Barrel count, timings and sounds come from the data below.

enum S { READY, CYCLE, OPEN, EJECT, INSERT, CLOSE }

const TUBE_CAP := 12   # plus one in the chamber
# For breech guns, open/eject/insert/close are [seconds, sound]; "hammer" means the
# hammer is thumbed back after each shot; "volley" lets the right trigger fire every
# loaded barrel at once.
const DATA := {
	"colt": {"name": "COLT SINGLE ACTION ARMY", "action": "revolver", "damage": 2, "speed": 650.0,
		"range": 380.0, "spread": 2.2, "pellets": 1, "noise": 380.0, "sfx": "colt", "cycle": 0.32,
		"shake": 2.0, "smoke": 9,
		"status": {"cycle": "COCKING", "open": "HALF-COCK, GATE OPEN", "close": "GATE CLOSED, COCKING"}},
	"rifle": {"name": "WINCHESTER 1866", "action": "lever", "damage": 2, "speed": 900.0, "range": 620.0,
		"spread": 0.6, "pellets": 1, "noise": 480.0, "sfx": "rifle", "cycle": 0.45, "shake": 2.5, "smoke": 11,
		"status": {"cycle": "LEVER", "open": "LOADING GATE", "close": ""}},
	"coach": {"name": "COACH GUN  10 GA", "action": "breech", "barrels": 2, "volley": true,
		"damage": 1, "speed": 520.0, "range": 175.0, "spread": 9.0, "pellets": 9, "noise": 460.0,
		"sfx": "coach", "cycle": 0.2, "shake": 4.0, "smoke": 20, "smoke_push": 1.5,
		"open": [0.4, "break_open"], "eject": [0.35, "eject"], "insert": [0.42, "shell_in"], "close": [0.35, "close"],
		"status": {"cycle": "", "open": "BREAKING OPEN", "close": "CLOSING"}},
	# A double gun with the barrels and the stock cut down: easy to carry under a coat,
	# useless past a few paces and murder inside them. Takes the coach gun's shells.
	"sawnoff": {"name": "SAWN-OFF 12 GA", "action": "breech", "barrels": 2, "volley": true,
		"damage": 1, "speed": 480.0, "range": 115.0, "spread": 15.0, "pellets": 9, "noise": 470.0,
		"sfx": "coach", "cycle": 0.2, "shake": 4.0, "smoke": 22, "smoke_push": 1.7, "ammo": "coach",
		"open": [0.32, "break_open"], "eject": [0.3, "eject"], "insert": [0.38, "shell_in"], "close": [0.3, "close"],
		"status": {"cycle": "", "open": "BREAKING OPEN", "close": "CLOSING"}},
	# A pair of Colts, one in each hand. Chambers alternate between the guns, so the
	# left is already cocked as the right fires; reloading is one gun at a time.
	"colts": {"name": "PAIR OF COLTS", "action": "revolver", "twin": true, "chambers": 12, "damage": 2,
		"speed": 650.0, "range": 340.0, "spread": 3.0, "pellets": 1, "noise": 380.0, "sfx": "colt",
		"cycle": 0.16, "shake": 2.0, "smoke": 9, "ammo": "colt", "drops": ["colt", "colt"],
		"status": {"cycle": "COCKING", "open": "HALF-COCK, GATE OPEN", "close": "GATE CLOSED, COCKING"}},
	# Empty hands: townsfolk. Never fires; drops nothing.
	"unarmed": {"name": "", "action": "none", "damage": 0, "speed": 0.0, "range": 0.0, "spread": 0.0,
		"pellets": 0, "noise": 0.0, "sfx": "", "cycle": 0.0, "shake": 0.0, "smoke": 0, "drops": [],
		"status": {"cycle": "", "open": "", "close": ""}},
	# Remington double derringer: two stacked barrels, cocked per shot, short and weak.
	"derringer": {"name": "REMINGTON DERRINGER", "action": "breech", "barrels": 2, "hammer": true,
		"damage": 1, "speed": 550.0, "range": 160.0, "spread": 3.0, "pellets": 1, "noise": 280.0,
		"sfx": "derringer", "cycle": 0.4, "shake": 1.0, "smoke": 4, "smoke_push": 0.6,
		"open": [0.35, "gate"], "eject": [0.35, "eject"], "insert": [0.42, "shell_in"], "close": [0.3, "cock"],
		"status": {"cycle": "COCKING", "open": "BARRELS UP", "close": "CLOSING"}},
	# Sharps 1874 buffalo rifle: one round, falling block, hits like a train, long reload.
	"sharps": {"name": "SHARPS 1874", "action": "breech", "barrels": 1, "hammer": true,
		"damage": 3, "speed": 1100.0, "range": 820.0, "spread": 0.3, "pellets": 1, "noise": 600.0,
		"sfx": "sharps", "cycle": 0.45, "shake": 4.0, "smoke": 16, "smoke_push": 1.3,
		"open": [0.4, "lever"], "eject": [0.35, "eject"], "insert": [0.55, "shell_in"], "close": [0.35, "lever"],
		"status": {"cycle": "COCKING", "open": "BLOCK DOWN", "close": "BLOCK UP"}},
	# Howdah pistol: a two-barrel .577 made for tigers, old-fashioned even now.
	"howdah": {"name": "HOWDAH PISTOL .577", "action": "breech", "barrels": 2, "hammer": true, "volley": true,
		"damage": 2, "speed": 520.0, "range": 230.0, "spread": 2.8, "pellets": 1, "noise": 520.0,
		"sfx": "howdah", "cycle": 0.38, "shake": 3.5, "smoke": 14, "smoke_push": 1.2,
		"open": [0.4, "break_open"], "eject": [0.35, "eject"], "insert": [0.45, "shell_in"], "close": [0.35, "close"],
		"status": {"cycle": "COCKING", "open": "BREAKING OPEN", "close": "CLOSING"}},
}

var kind: String
var d: Dictionary
var action: String
var holder: Actor
var state := S.READY
var timer := 0.0
var reserve := 0
var stop_requested := false
var reload_idx := 0

# Revolver: 0 empty, 1 live, 2 spent. `cur` is the chamber under the hammer.
var chambers: Array[int] = [1, 1, 1, 1, 1, 1]
var cur := 0
var cocked := true
var fanning := false
var hand := 0   # the hand that fired last: 0 right, 1 left (a pair of guns)
# Breech guns, same encoding per barrel.
var barrels: Array[int] = []
# Lever action.
var tube := TUBE_CAP
var chambered := true
var ejecting := false   # this lever stroke throws out a fired case


func _init(k: String, h: Actor) -> void:
	kind = k
	d = DATA[k]
	action = d["action"]
	holder = h
	chambers.resize(int(d.get("chambers", 6)))
	chambers.fill(1)
	for i in int(d.get("barrels", 0)):
		barrels.append(1)


## A shotgun: a hip-carried scattergun throwing a fistful of shot.
func is_shotgun() -> bool:
	return int(d["pellets"]) > 1


func is_reloading() -> bool:
	return state in [S.OPEN, S.EJECT, S.INSERT, S.CLOSE]


func can_fire() -> bool:
	if state != S.READY:
		return false
	match action:
		"revolver":
			return cocked and chambers[cur] == 1
		"breech":
			return barrels.has(1)
		"none":
			return false
		_:
			return chambered


func needs_reload() -> bool:
	match action:
		"none":
			return false
		"revolver":
			return not chambers.has(1)
		"breech":
			return not barrels.has(1)
		_:
			return not chambered and tube == 0


func loaded() -> int:
	match action:
		"revolver":
			return chambers.count(1)
		"breech":
			return barrels.count(1)
		_:
			return tube + (1 if chambered else 0)


func status() -> String:
	var st: Dictionary = d["status"]
	match state:
		S.CYCLE:
			return st["cycle"]
		S.OPEN:
			return st["open"]
		S.EJECT:
			return "EJECTING"
		S.INSERT:
			return "LOADING"
		S.CLOSE:
			return st["close"]
	return ""


## Left trigger. Pressing it during a reload stops the reload after the current round.
func trigger() -> void:
	if is_reloading():
		stop_requested = true
		return
	if state != S.READY:
		return
	match action:
		"revolver":
			if cocked:
				_colt_fire(false)
		"breech":
			var i := barrels.find(1)
			if i < 0:
				_dry()
				return
			barrels[i] = 2
			_shoot(1)
			_cycle(d["cycle"])
		"lever":
			if chambered:
				chambered = false
				_shoot(1)
				_cycle(d["cycle"])
				ejecting = true   # the lever throws out the spent case
				_snd("lever")
			else:
				# empty chamber: the hammer falls on nothing and he works the lever
				# anyway, chambering a round if there is one; no case comes out
				if tube == 0:
					_snd("dry", 2.0)
				_cycle(d["cycle"])
				ejecting = false
				_snd("lever")


## Right trigger: every loaded barrel at once, on guns that allow it.
func alt_trigger() -> void:
	if not d.get("volley", false) or state != S.READY:
		return
	var n := barrels.count(1)
	if n == 0:
		_dry()
		return
	for i in barrels.size():
		if barrels[i] == 1:
			barrels[i] = 2
	_shoot(n)
	_cycle(d["cycle"] * 2.0)


func start_reload() -> bool:
	if state != S.READY or reserve <= 0:
		return false
	match action:
		"revolver":
			if not chambers.has(0) and not chambers.has(2):
				return false
		"breech":
			if not barrels.has(0) and not barrels.has(2):
				return false
		"lever":
			if tube >= TUBE_CAP:
				return false
	stop_requested = false
	reload_idx = 0
	state = S.OPEN
	if holder.has_method("on_reload"):
		holder.on_reload()
	match action:
		"revolver":
			timer = 0.35
			cocked = false
			_snd("gate")
		"breech":
			timer = d["open"][0]
			_snd(d["open"][1])
		_:
			timer = 0.25
	return true


## Cancel everything instantly (weapon switch, death).
func abort() -> void:
	if is_reloading():
		state = S.READY
		if action == "revolver":
			cocked = true
	fanning = false


func update(delta: float) -> void:
	if state != S.READY:
		timer -= delta
		if timer <= 0.0:
			_advance()
	if action == "revolver" and fanning and state == S.READY and cocked:
		_colt_fire(true)


func _advance() -> void:
	match state:
		S.CYCLE:
			state = S.READY
			if action == "revolver":
				cur = (cur + 1) % chambers.size()
				cocked = true
				if not fanning:
					_snd("cock", -2.0)
			elif action == "breech" and d.get("hammer", false) and barrels.has(1):
				_snd("cock", -4.0)
			elif action == "lever" and not chambered and tube > 0:
				tube -= 1
				chambered = true
		S.OPEN, S.EJECT, S.INSERT:
			_reload_step()
		S.CLOSE:
			state = S.READY
			if action == "revolver":
				cocked = true
				var n := chambers.size()
				for i in n:
					if chambers[(cur + i) % n] == 1:
						cur = (cur + i) % n
						break
			elif action == "lever" and not chambered and tube > 0:
				_cycle(d["cycle"])
				ejecting = false
				_snd("lever")


func _reload_step() -> void:
	if stop_requested:
		_close()
		return
	match action:
		"revolver":
			while reload_idx < chambers.size():
				var c := (cur + reload_idx) % chambers.size()
				if chambers[c] == 2:
					chambers[c] = 0
					_step(S.EJECT, 0.26, "eject")
					return
				if chambers[c] == 0 and reserve > 0:
					chambers[c] = 1
					reserve -= 1
					reload_idx += 1
					_step(S.INSERT, 0.36, "shell_in")
					return
				reload_idx += 1
		"breech":
			if barrels.has(2):
				for i in barrels.size():
					if barrels[i] == 2:
						barrels[i] = 0
				_step(S.EJECT, d["eject"][0], d["eject"][1])
				return
			var i := barrels.find(0)
			if i >= 0 and reserve > 0:
				barrels[i] = 1
				reserve -= 1
				_step(S.INSERT, d["insert"][0], d["insert"][1])
				return
		"lever":
			if tube < TUBE_CAP and reserve > 0:
				tube += 1
				reserve -= 1
				_step(S.INSERT, 0.4, "shell_in")
				return
	_close()


func _step(s: S, t: float, snd: String) -> void:
	state = s
	timer = t
	_snd(snd)


func _close() -> void:
	state = S.CLOSE
	match action:
		"revolver":
			timer = 0.3
			_snd("cock")
		"breech":
			timer = d["close"][0]
			_snd(d["close"][1])
		_:
			timer = 0.15


func _cycle(t: float) -> void:
	state = S.CYCLE
	timer = t


## The hero's own gun is heard up close at full volume; a bandit's is placed in the
## world and fades with distance.
func _snd(name: String, vol := 0.0) -> void:
	if holder.is_player:
		holder.game.sfx(name, null, vol, 0.04)
	else:
		holder.game.sfx(name, holder.global_position, vol - 3.0)


func _dry() -> void:
	_snd("dry", 2.0)
	_cycle(0.15)


func _colt_fire(fan: bool) -> void:
	if d.get("twin", false):
		hand = cur % 2   # even chambers are the right gun's, odd the left's
	if chambers[cur] == 1:
		chambers[cur] = 2
		_shoot(1, 11.0 if fan else 0.0)
	else:
		_snd("dry", 2.0)
	cocked = false
	_cycle(0.12 if fan else d["cycle"])


func _shoot(mult: int, extra_spread := 0.0) -> void:
	var h := holder
	var dir := h.facing
	var spread := deg_to_rad(d["spread"] * h.accuracy_mult() + extra_spread)
	var n: int = d["pellets"] * mult
	var origin := h.global_position + dir * 5.0
	for i in n:
		var a: float
		var rng: float = d["range"]
		if d["pellets"] == 1:
			a = clamp(randfn(0.0, spread * 0.5), -spread * 1.5, spread * 1.5)
		else:
			a = randf_range(-spread, spread) * (1.25 if mult > 1 else 1.0)
			rng *= randf_range(0.75, 1.1)
		h.game.spawn_bullet(origin, dir.rotated(a) * d["speed"] * randf_range(0.93, 1.05), rng,
			d["damage"], h, h.gun_height(), d["pellets"] > 1)
	h.game.muzzle_flash(h, dir)
	h.play_action("fire_l" if hand == 1 else "fire")
	_snd(d["sfx"], 2.0 if mult > 1 else 0.0)
	h.game.make_noise(h.global_position, d["noise"], "shot" if h.is_player else "enemy_shot", h)
	h.on_fired(d["shake"] * mult)
