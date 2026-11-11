extends SceneTree
## The burial ground ("A Good Man Never Dies", phase 1: the place and its guests):
##   map    - a great round cemetery under a grey sky, the mud deep: graves by the
##            hundred round the circle of stones, his open grave at its heart, crypts
##            and obelisks among them that stop a man; the mission, the undertaker's
##            and the cantina round about, the wake's dinner laid in the two northern
##            corners with the graves running up to them, the guests' wagons and
##            horses along the road, the town's first houses to the east; no
##            tumbleweed in the wet.
##   guests - twenty, from all four towns (San Miguel's gang, the revolution, the
##            federales, Silencio's hunters and outlaws), every one on the same side;
##            seven round the grave looking in at it; the padre, the undertaker, his
##            digger, three mourners, the two women who cooked the wake and a man of
##            the town besides.
##   dead   - the digger keeps to his own row (the stranger's grave isn't his to
##            fill), and the undertaker buries the day's dead in his own plot, clear
##            of the old graves.
##   guns   - no choosing: he rides in with the pair of Colts, twelve loaded and not
##            a round spare, no bandage, no stick.
##   ways   - from the south he can get to the grave, the chapel, the undertaker's,
##            the cantina, between the dinner tables in both northern corners, up
##            the town's street, and round every crypt.
##   quiet  - left alone a while, nothing ends it.
##   godot --headless --path . --fixed-fps 60 -s tests/test_funeral.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var t := 0.0
const C := Vector2(32.0, 36.0)   # the grave (tools/make_funeral.py, on the map)


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("level", "funeral")
	seed(5)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


func _reaches(a: Vector2, b: Vector2) -> bool:
	var path: PackedVector2Array = game.find_path(Iso.to_screen(a), Iso.to_screen(b))
	return path.size() > 0 and path[path.size() - 1].distance_to(Iso.to_screen(b)) < 20.0


func _map() -> void:
	step = "map"
	var count := {}
	for rec in game.placed:
		count[rec["type"]] = count.get(rec["type"], 0) + 1
	var graves := 0
	for k in game.GRAVES:
		graves += count.get(k, 0)
	check(graves > 150, "only %d graves" % graves)
	check(count.get("stone_circle", 0) == 1 and count.get("open_grave", 0) >= 1, "no circle, no grave: %s" % count)
	check(count.get("crypt", 0) + count.get("crypt_b", 0) == 8 and count.get("obelisk", 0) == 8, "crypts and obelisks: %s" % count)
	# the graves go on north to the dinner tables
	var north := 0
	for o in game.level["objects"]:
		if o["type"] in game.GRAVES and o["y"] < 10.0:
			north += 1
	check(north > 40, "only %d graves up by the tables" % north)
	# the guests came a long way: the road's lined with their wagons and horses
	var horses := 0
	for k in ["horse", "horse_grey", "horse_sorrel", "horse_black"]:
		horses += count.get(k, 0)
	check(horses >= 18 and count.get("covered_wagon", 0) >= 5 and count.get("carreta_0", 0) == 1, "horses and carriages: %s" % count)
	check(count.get("chapel", 0) == 1 and count.get("undertaker", 0) == 1 and count.get("cantina", 0) == 1, "the buildings round about: %s" % count)
	check(count.get("feast_x", 0) == 12 and count.get("bench_x", 0) == 24 and count.get("cookfire", 0) == 2, "the dinners: %s" % count)
	check(count.get("stable", 0) == 1 and count.get("store", 0) == 1, "no town to the east: %s" % count)
	# a crypt stops a man: the middle of its footprint is solid ground for nobody
	for o in game.level["objects"]:
		if o["type"] in ["crypt", "crypt_b"]:
			var fp: Array = game.meta["objects"][o["type"]]["footprint"]
			var mid := Iso.to_screen(Vector2(o["x"] + fp[0] * 0.5, o["y"] + fp[1] * 0.5))
			check(game.astar.is_point_solid(game._cell(mid)), "the crypt at %s,%s can be walked through" % [o["x"], o["y"]])
	# his own grave is nobody's to fill: the digger has only his row by the undertaker's
	check(game.open_graves.size() == 3 and game.open_graves.all(func(gr): return gr["g"].x < 20.0),
		"the digger's graves: %s" % [game.open_graves.map(func(gr): return gr["g"])])
	# the day's dead go in the undertaker's own plot, not on top of the old graves
	var plot: Array = game.level["boothills"][0]
	for i in 5:
		var g := Iso.to_grid(game.grave_spot())
		check(g.x > plot[0] and g.x < plot[2] and g.y > plot[1] and g.y < plot[3], "a fresh grave at %s, off his plot" % g)
	game.graves.clear()
	check(game.meta.has("ground_funeral") and game.level["ground"] == "ground_funeral", "no ground of its own")
	var mat := game.post.material as ShaderMaterial
	check(mat.get_shader_parameter("sat") < 0.7 and mat.get_shader_parameter("tint").z > 1.0, "still the desert's sun")
	check(game.level.get("weather", "") == "grey", "no grey sky")


func _guests() -> void:
	step = "guests"
	check(game.enemies.size() == 20, "guests: %d" % game.enemies.size())
	check(game.enemies.all(func(e): return e.gang == ""), "two sides at a funeral: %s" % [game.enemies.map(func(e): return e.gang)])
	var kinds: Array = game.enemies.map(func(e): return e.kind)
	for town in [["pistolero", "bandido", "redscarf", "cowboy"], ["revolucionario", "sargento", "soldadera", "tirador"],
			["soldado", "cabo", "rural", "teniente"], ["manhunter", "trapper", "sharpshooter", "mountainman"]]:
		check(town.any(func(k): return k in kinds), "nobody from %s" % [town])
	var at_grave: Array = game.enemies.filter(func(e): return Iso.to_grid(e.global_position).distance_to(C) < 3.0)
	check(at_grave.size() == 7, "%d round the grave" % at_grave.size())
	for e in at_grave:
		var to_grave: Vector2 = Iso.to_screen(C) - e.global_position
		check(e.facing.dot(to_grave.normalized()) > 0.7, "%s looks away from the grave" % e.kind)
	check(game.civilians.size() == 9, "townsfolk: %d" % game.civilians.size())
	check(game.civilians.any(func(c): return c.priest) and game.civilians.any(func(c): return c.undertaker), "no padre or no undertaker")


func _ways() -> void:
	step = "ways"
	var start := Vector2(game.level["player"]["x"], game.level["player"]["y"])
	for to in [C + Vector2(0, 2.0), Vector2(32.0, 15.4), Vector2(10.4, 37.6), Vector2(55.0, 33.6), Vector2(0.8, 57.5),
			Vector2(75.0, 57.5), Vector2(13.0, 4.5), Vector2(53.5, 4.5), Vector2(67.0, 30.0), Vector2(67.0, 1.0)]:
		check(_reaches(start, to), "no way from the south to %s" % to)
	for o in game.level["objects"]:
		if o["type"] in ["crypt", "crypt_b"]:
			check(_reaches(start, Vector2(o["x"] + 1.0, o["y"] - 0.6)), "no way round behind the crypt at %s,%s" % [o["x"], o["y"]])


func _guns() -> void:
	step = "guns"
	check(game.state == "play", "the guns were offered: %s" % game.state)
	var p: Player = game.player
	check(p.owned.size() == 1 and p.weapon.kind == "colts", "rode in with %s, %s" % [p.owned, p.weapon.kind])
	check(p.weapon.loaded() == 12 and p.weapon.reserve == 0, "loaded %d, spare %d" % [p.weapon.loaded(), p.weapon.reserve])
	check(p.bandages == 0 and p.sticks == 0, "kit: %d bandages, %d sticks" % [p.bandages, p.sticks])


func _process(delta: float) -> bool:
	frame += 1
	if frame == 3:
		_map()
		_guests()
		_ways()
		game._to_loadout()   # (as the picker does: this town skips the guns)
		_guns()
	if frame <= 3:
		return false
	t += delta
	if t < 10.0:
		return false
	step = "quiet"
	check(game.state == "play", "it ended by itself: %s" % game.state)
	check(game.enemies.all(func(e): return e.alive), "someone died in the quiet")
	print("funeral test: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(failures)
	return true
