class_name Weapon
extends RefCounted
## Period-authentic firearms: Colt Single Action Army, a side-by-side coach gun with
## external hammers, and the Winchester 1866 "Yellow Boy" carbine.

enum S { READY, CYCLE, OPEN, EJECT, INSERT, CLOSE }

const TUBE_CAP := 12   # plus one in the chamber
const DATA := {
	"colt": {"name": "COLT SINGLE ACTION ARMY", "damage": 2, "speed": 650.0, "range": 380.0,
		"spread": 2.2, "pellets": 1, "noise": 380.0, "sfx": "colt", "cycle": 0.32, "shake": 2.0},
	"coach": {"name": "COACH GUN  10 GA", "damage": 1, "speed": 520.0, "range": 175.0,
		"spread": 9.0, "pellets": 9, "noise": 460.0, "sfx": "coach", "cycle": 0.2, "shake": 4.0},
	"rifle": {"name": "WINCHESTER 1866", "damage": 2, "speed": 900.0, "range": 620.0,
		"spread": 0.6, "pellets": 1, "noise": 480.0, "sfx": "rifle", "cycle": 0.45, "shake": 2.5},
}

var kind: String
var d: Dictionary
var holder: Actor
var state := S.READY
var timer := 0.0
var reserve := 0
var stop_requested := false
var reload_idx := 0

# Colt: 0 empty, 1 live, 2 spent. `cur` is the chamber under the hammer.
var chambers: Array[int] = [1, 1, 1, 1, 1, 1]
var cur := 0
var cocked := true
var fanning := false
# Coach gun barrels, same encoding.
var barrels: Array[int] = [1, 1]
# Winchester.
var tube := TUBE_CAP
var chambered := true
var ejecting := false   # this lever stroke throws out a fired case


func _init(k: String, h: Actor) -> void:
	kind = k
	d = DATA[k]
	holder = h


func is_reloading() -> bool:
	return state in [S.OPEN, S.EJECT, S.INSERT, S.CLOSE]


func can_fire() -> bool:
	if state != S.READY:
		return false
	match kind:
		"colt":
			return cocked and chambers[cur] == 1
		"coach":
			return barrels.has(1)
		_:
			return chambered


func needs_reload() -> bool:
	match kind:
		"colt":
			return not chambers.has(1)
		"coach":
			return not barrels.has(1)
		_:
			return not chambered and tube == 0


func loaded() -> int:
	match kind:
		"colt":
			return chambers.count(1)
		"coach":
			return barrels.count(1)
		_:
			return tube + (1 if chambered else 0)


func status() -> String:
	match state:
		S.CYCLE:
			return {"colt": "COCKING", "coach": "", "rifle": "LEVER"}[kind]
		S.OPEN:
			return {"colt": "HALF-COCK, GATE OPEN", "coach": "BREAKING OPEN", "rifle": "LOADING GATE"}[kind]
		S.EJECT:
			return "EJECTING"
		S.INSERT:
			return "LOADING"
		S.CLOSE:
			return {"colt": "GATE CLOSED, COCKING", "coach": "CLOSING", "rifle": ""}[kind]
	return ""


## Left trigger. Pressing it during a reload stops the reload after the current round.
func trigger() -> void:
	if is_reloading():
		stop_requested = true
		return
	if state != S.READY:
		return
	match kind:
		"colt":
			if cocked:
				_colt_fire(false)
		"coach":
			var i := barrels.find(1)
			if i < 0:
				_dry()
				return
			barrels[i] = 2
			_shoot(1)
			_cycle(d["cycle"])
		"rifle":
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


## Right trigger on the coach gun: both barrels at once.
func alt_trigger() -> void:
	if kind != "coach" or state != S.READY:
		return
	var n := barrels.count(1)
	if n == 0:
		_dry()
		return
	for i in 2:
		if barrels[i] == 1:
			barrels[i] = 2
	_shoot(n)
	_cycle(d["cycle"] * 2.0)


func start_reload() -> bool:
	if state != S.READY or reserve <= 0:
		return false
	match kind:
		"colt":
			if not chambers.has(0) and not chambers.has(2):
				return false
		"coach":
			if not barrels.has(0) and not barrels.has(2):
				return false
		"rifle":
			if tube >= TUBE_CAP:
				return false
	stop_requested = false
	reload_idx = 0
	state = S.OPEN
	if holder.has_method("on_reload"):
		holder.on_reload()
	match kind:
		"colt":
			timer = 0.35
			cocked = false
			_snd("gate")
		"coach":
			timer = 0.4
			_snd("break_open")
		_:
			timer = 0.25
	return true


## Cancel everything instantly (weapon switch, death).
func abort() -> void:
	if is_reloading():
		state = S.READY
		if kind == "colt":
			cocked = true
	fanning = false


func update(delta: float) -> void:
	if state != S.READY:
		timer -= delta
		if timer <= 0.0:
			_advance()
	if kind == "colt" and fanning and state == S.READY and cocked:
		_colt_fire(true)


func _advance() -> void:
	match state:
		S.CYCLE:
			state = S.READY
			if kind == "colt":
				cur = (cur + 1) % 6
				cocked = true
				if not fanning:
					_snd("cock", -2.0)
			elif kind == "rifle" and not chambered and tube > 0:
				tube -= 1
				chambered = true
		S.OPEN, S.EJECT, S.INSERT:
			_reload_step()
		S.CLOSE:
			state = S.READY
			if kind == "colt":
				cocked = true
				for i in 6:
					if chambers[(cur + i) % 6] == 1:
						cur = (cur + i) % 6
						break
			elif kind == "rifle" and not chambered and tube > 0:
				_cycle(d["cycle"])
				ejecting = false
				_snd("lever")


func _reload_step() -> void:
	if stop_requested:
		_close()
		return
	match kind:
		"colt":
			while reload_idx < 6:
				var c := (cur + reload_idx) % 6
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
		"coach":
			if barrels.has(2):
				for i in 2:
					if barrels[i] == 2:
						barrels[i] = 0
				_step(S.EJECT, 0.35, "eject")
				return
			var i := barrels.find(0)
			if i >= 0 and reserve > 0:
				barrels[i] = 1
				reserve -= 1
				_step(S.INSERT, 0.42, "shell_in")
				return
		"rifle":
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
	match kind:
		"colt":
			timer = 0.3
			_snd("cock")
		"coach":
			timer = 0.35
			_snd("close")
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
		if n == 1:
			a = clamp(randfn(0.0, spread * 0.5), -spread * 1.5, spread * 1.5)
		else:
			a = randf_range(-spread, spread) * (1.25 if mult > 1 else 1.0)
			rng *= randf_range(0.75, 1.1)
		h.game.spawn_bullet(origin, dir.rotated(a) * d["speed"] * randf_range(0.93, 1.05), rng,
			d["damage"], h, h.gun_height(), n > 1)
	h.game.muzzle_flash(h, dir)
	h.play_action("fire")
	_snd(d["sfx"], 2.0 if mult > 1 else 0.0)
	h.game.make_noise(h.global_position, d["noise"], "shot" if h.is_player else "enemy_shot", h)
	h.on_fired(d["shake"] * mult)
