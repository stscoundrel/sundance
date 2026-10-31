extends SceneTree
## Bandit type data sanity:  godot --headless --path . -s tests/test_types.gd
## Every type must have a baked template with animations for each gun it carries, guns
## the game knows, palettes using real slot names and sensible numbers; every bandit
## placed in town must use a defined type.

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: ", msg)


func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/meta.json"))
	var level: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/town.json"))
	var slots: Array = data["slots"]
	check(slots.size() < 16, "at most 15 palette slots (the shader holds 16)")
	for name in data["types"]:
		var t: Dictionary = data["defaults"].duplicate(true)
		t.merge(data["types"][name], true)
		var where := "type %s: " % name
		check(data["templates"].has(t["template"]), where + "unknown template " + str(t["template"]))
		check(meta["chars"].has(t["template"]), where + "template not baked: " + str(t["template"]))
		var anims: Dictionary = meta["chars"].get(t["template"], {}).get("anims", {})
		check(not t["loadout"].is_empty(), where + "carries no gun")
		for g in t["loadout"]:
			check(Weapon.DATA.has(g), where + "unknown gun " + str(g))
			for a in ["aim", "fire", "reload_open", "reload_insert", "reload_close", "point", "hit_gut"]:
				check(anims.has("upper/%s/%s" % [g, a]), where + "no %s animation for %s" % [a, g])
		check(not t["palettes"].is_empty(), where + "no palette")
		for p in t["palettes"]:
			for k in p:
				check(k in slots, where + "unknown palette slot " + k)
		check(int(t["hp"]) > 0, where + "hp must be positive")
		check(t["range"][0] < t["range"][1], where + "range must be [near, far]")
		check(t["cadence"][0] <= t["cadence"][1] and t["cadence"][0] > 0.0, where + "bad cadence")
		check(t["reflex"][0] <= t["reflex"][1] and t["reflex"][0] > 0.0, where + "bad reflex range")
		check(t["nerve"][0] >= 0.0 and t["nerve"][1] <= 1.0 and t["nerve"][0] <= t["nerve"][1], where + "nerve must be within 0..1")
		check(float(t["aim"]) > 0.0 and float(t["speed"]) > 0.0, where + "aim and speed must be positive")
		check(t["draw_sidearm"] == 0.0 or t["loadout"].size() > 1, where + "draws a sidearm he doesn't carry")
	for e in level["enemies"]:
		check(data["types"].has(e["kind"]), "town places unknown type " + str(e["kind"]))
		check(not e.has("loadout"), "placements can't change loadouts (the art is baked per type)")
	print("types: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures else 0)
