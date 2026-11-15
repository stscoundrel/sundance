class_name Posse
extends RefCounted
## The last of the gang band together. Once SIZE or fewer bandits are left, they
## gather on a leader and then ride the town as one group: the leader walks from
## street to street, always towards the parts they've seen least lately, and the
## others keep their places around him, each watching his own side. A fight breaks
## the formation as usual; afterwards each man falls back in on the leader.
##
## At the stranger's funeral the guests, whatever their faction, band together the
## same way, but only once every faction's help is on the field (or isn't coming):
## they sweep the burial ground's own places (the map's "posse_route": the grave, the
## mission, the dinners, the town, the road...) instead of streets, and they don't
## run ("posse_stands"): it's them or him.

const SIZE := 7              # a band of seven: too many for one man's six shots
const GATHER_MAX := 30.0   # set off with whoever has arrived by then
const TOGETHER := 70.0     # gathered: everyone this close to the leader
const LAG := 110.0         # the leader waits for anyone further behind than this
const WAIT_MAX := 6.0      # but not for ever: then he moves on and they catch up
const SPACING := 8.0       # tiles between route points along a street
# Formation slots around the leader: [metres back, metres to the side] in his
# frame, and the bearing each man keeps watch on when they stop.
const SLOTS := [[1.6, 1.3], [1.6, -1.3], [3.2, 0.0], [3.0, 2.4], [3.0, -2.4], [4.6, 1.3], [4.6, -1.3]]
const WATCH := [0.9, -0.9, PI, 2.0, -2.0, 2.6, -2.6]
const RALLY_LINES := ["¡A mí, muchachos!", "To me, boys!", "Stick together!", "¡Juntos!"]

var game: Node
var members: Array[Enemy] = []
var leader: Enemy
var gathering := true
var gather_t := 0.0
var lag_t := 0.0   # how long the leader has been waiting on stragglers
var points := PackedVector2Array()   # where the posse can go: along every street
var visited := {}                    # point index -> game clock when last reached
var goal := -1


func _init(g: Node) -> void:
	game = g
	_build_points()


## Route points along the middle of every street and the plaza (a town without
## streets drawn: its guard posts; a map with places named for it: those).
func _build_points() -> void:
	if game.level.has("posse_route"):
		for r in game.level["posse_route"]:
			var p: Vector2 = Iso.to_screen(Vector2(r["x"], r["y"]))
			if not game.is_free(p):
				p = game.free_point_near(p, 40.0)
			if p != Vector2.INF:
				points.append(p)
		return
	if game.level.get("streets", []).is_empty():
		for p in game.level.get("posts", []):
			points.append(Iso.to_screen(Vector2(p["x"], p["y"])))
	for r in game.level.get("streets", []):
		var a := Vector2(r[0], r[1])
		var b := Vector2(r[2], r[3])
		var mid := (a + b) * 0.5
		var along_x: bool = (b.x - a.x) >= (b.y - a.y)
		var length: float = (b.x - a.x) if along_x else (b.y - a.y)
		var n := maxi(1, int(round(length / SPACING)))
		for i in n:
			var f := (i + 0.5) / n
			var g := Vector2(lerpf(a.x, b.x, f), mid.y) if along_x else Vector2(mid.x, lerpf(a.y, b.y, f))
			var p: Vector2 = Iso.to_screen(g)
			if not game.is_free(p):
				p = game.free_point_near(p, 30.0)
			if p != Vector2.INF:
				points.append(p)


## Form up: everyone still standing joins, the steadiest man leads, and they meet
## where he is.
func form() -> void:
	for e in game.enemies:
		if e.alive and not e.posted():   # (he stays by his gallows, or his pole)
			members.append(e)
	_pick_leader()
	gathering = true
	gather_t = 0.0
	for i in members.size():
		members[i].join_posse(i)
	if leader.st == Enemy.St.POSSE:
		leader.say_line("rally", RALLY_LINES)
	game.stats["posse forms"] = game.stats.get("posse forms", 0) + 1


## Highest rank first; among equals, someone not busy fighting, nearest the others.
func _pick_leader() -> void:
	var centre := Vector2.ZERO
	var alive: Array[Enemy] = []
	for e in members:
		if e.alive:
			alive.append(e)
			centre += e.global_position
	if alive.is_empty():
		leader = null
		return
	centre /= alive.size()
	var best: Enemy = null
	var best_score := INF
	for e in alive:
		var score: float = -e.rank * 1000.0 + e.global_position.distance_to(centre) \
			+ (300.0 if e.st == Enemy.St.COMBAT else 0.0)
		if score < best_score:
			best_score = score
			best = e
	leader = best
	var slot := 0
	for e in alive:
		if e != leader:
			e.posse_slot = slot
			slot += 1


func update(delta: float) -> void:
	lag_t += delta
	if leader == null or not leader.alive:
		_pick_leader()
		if leader == null:
			return
		goal = -1
	if gathering:
		gather_t += delta
		if gather_t > GATHER_MAX or _all_close(TOGETHER):
			gathering = false
			game.stats["posse sets off"] = game.stats.get("posse sets off", 0) + 1


func _all_close(r: float) -> bool:
	for e in members:
		if e.alive and e != leader and e.st == Enemy.St.POSSE and e.global_position.distance_to(leader.global_position) > r:
			return false
	return true


## The leader holds up while anyone in formation is straggling, a while.
func lagging() -> bool:
	if _all_close(LAG):
		lag_t = 0.0
		return false
	return lag_t < WAIT_MAX


## Where a man keeps station: his slot behind and beside the leader.
func slot_of(e: Enemy) -> Vector2:
	var s: Array = SLOTS[e.posse_slot % SLOTS.size()]
	var fwd: Vector2 = leader.facing
	var side := fwd.orthogonal()
	# metres to screen space: a tile is about 1 m and 18 px across the diamond
	var p: Vector2 = leader.global_position - fwd * s[0] * 18.0 + side * s[1] * 18.0
	if game.is_free(p):
		return p
	var half := leader.global_position.lerp(p, 0.5)   # a wall in the way: close up
	if game.is_free(half):
		return half
	# no room beside him (an alley): fall in behind, single file, never on top of him
	for k in [1.5, 2.5, 3.5, 4.5]:
		var behind: Vector2 = leader.global_position - fwd * 18.0 * (k + e.posse_slot * 0.6)
		if game.is_free(behind):
			return behind
	return leader.global_position - fwd * 24.0


func watch_of(e: Enemy) -> Vector2:
	var a: float = WATCH[e.posse_slot % WATCH.size()]
	return leader.facing.rotated(a + sin(game.clock * 0.5 + e.posse_slot) * 0.5)


## The next street to walk: the nearest of the points seen least lately (never,
## or within half a minute of the stalest), so they sweep on instead of doubling back.
func next_point(from: Vector2) -> Vector2:
	var stalest := INF
	for i in points.size():
		stalest = minf(stalest, visited.get(i, -1e9))
	var best := -1
	var best_d := INF
	for i in points.size():
		var d := from.distance_to(points[i])
		if visited.get(i, -1e9) <= stalest + 30.0 and d > 40.0 and d < best_d:
			best_d = d
			best = i
	if best < 0:
		best = randi() % points.size()
	goal = best
	return points[best]


func reached() -> void:
	if goal >= 0:
		visited[goal] = game.clock
	# everything within sight of here counts as seen too
	for i in points.size():
		if points[i].distance_to(leader.global_position) < 90.0:
			visited[i] = game.clock
	goal = -1
