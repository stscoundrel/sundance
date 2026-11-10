class_name Drifts
extends Node
## The snow covering what's left lying out in it (Silencio's, with its weather: see
## Snowfall). A body in the open slowly goes under: a dusting first, then a drift the
## shape of him (the palette shader's "snow"), a few minutes of the steady snow, far quicker in a squall. Under it,
## he's as good as buried: nobody finds him, nobody drags him out. The blood under
## him fills in at the same pace (and a pool left where a body was dragged from), and
## the gun he dropped goes under with him. Hauling him off shakes the snow off him.
## All of it on game time; no dice.

const BURY_T := 240.0     # s for a body to go under in the steady snow
const STORM_BURY := 6.0   # as many times faster in the worst of a squall
const TICK := 0.2         # s between snowings

var game: Node
var _tick := 0.0


func setup(g: Node) -> void:
	game = g


## How much snow falls in `dt` seconds now: a body's worth is 1.
func fall(dt: float) -> float:
	var storm: float = game.snowfall.storm if game.snowfall else 0.0
	return dt / BURY_T * (1.0 + (STORM_BURY - 1.0) * storm)


func _physics_process(delta: float) -> void:
	if game.state != "play":
		return
	_tick -= delta
	if _tick > 0.0:
		return
	var snow := fall(TICK - _tick)
	_tick = TICK
	var all: Array = []
	all.append_array(game.enemies)
	all.append_array(game.civilians)
	for a in all:
		_snow_on(a, snow)
	for i in range(game.blood_pools.size() - 1, -1, -1):
		var pl: Dictionary = game.blood_pools[i]
		pl["snow"] = minf(1.0, float(pl.get("snow", 0.0)) + snow)
		var s: Sprite2D = pl.get("sprite")
		if s and is_instance_valid(s):
			s.self_modulate.a = 1.0 - pl["snow"]
		if pl["snow"] >= 1.0:
			game.blood_pools.remove_at(i)   # (nothing there to find any more)
			if s and is_instance_valid(s):
				s.queue_free()


## The snow settling on a body lying out in it (not one on the move in someone's
## hands: that shakes it off him).
func _snow_on(a: Actor, snow: float) -> void:
	if a.alive or (a is Enemy and a.downed) or a.dying() or a.has_meta("buried") or not a.visible:
		return
	var mat := a.upper_spr.material as ShaderMaterial
	if a.has_meta("dragged") or game.in_hand(a):
		a.set_meta("snow", 0.0)
		mat.set_shader_parameter("snow", 0.0)
		return
	var depth := minf(1.0, float(a.get_meta("snow", 0.0)) + snow)
	a.set_meta("snow", depth)
	mat.set_shader_parameter("snow", depth)   # (the palette shader whitens him: a drift his shape)
	for g in game.loose_guns:
		if g["under"] == a and is_instance_valid(g["sprite"]):
			g["sprite"].self_modulate.a = 1.0 - depth
	if depth >= 1.0:
		a.set_meta("buried", true)   # (under the snow: as good as in the ground)
		a.set_meta("snowed", true)
		game.stats["snowed over"] = game.stats.get("snowed over", 0) + 1
		for i in range(game.blood_pools.size() - 1, -1, -1):   # (the blood under him with him)
			var pl: Dictionary = game.blood_pools[i]
			if pl["body"] == a and pl["at"].distance_to(a.global_position) < 40.0:
				game.blood_pools.remove_at(i)
				if pl.get("sprite") and is_instance_valid(pl["sprite"]):
					pl["sprite"].queue_free()
		for g in game.loose_guns.duplicate():
			if g["under"] == a:
				game.loose_guns.erase(g)
				if is_instance_valid(g["sprite"]):
					g["sprite"].queue_free()
				if g["ammo"] != null and is_instance_valid(g["ammo"]):
					g["ammo"].queue_free()

