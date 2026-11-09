extends SceneTree
## The stranger dresses for the place: each level that names his clothes in
## levels.json ("stranger") paints them on him with the palette shader, no re-bake,
## and the HUD's corner shows him in them; any slot it leaves out, and any level that
## names none, keeps his usual dust-brown duster and the usual portrait.
##   godot --headless --path . --fixed-fps 60 -s tests/test_dress.gd

var game: Node
var frame := 0
var failures := 0
var step := ""
var todo := ["silencio", "cruz_verde", "test_yard"]


func _initialize() -> void:
	Engine.set_meta("fixed_seed", true)
	Engine.set_meta("no_civilians", true)
	Engine.set_meta("no_captive", true)
	_open(todo.pop_front())


func _open(id: String) -> void:
	step = id
	Engine.set_meta("level", id)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	frame = 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		print("FAIL: [%s] %s" % [step, msg])


## The colour the shader paints a slot with on him.
func _worn(slot: String) -> Color:
	var mat: ShaderMaterial = game.player.legs_spr.material
	var pal: PackedVector3Array = mat.get_shader_parameter("pal")
	var v: Vector3 = pal[game.enemy_data["slots"].find(slot) + 1] * 255.0
	return Color8(roundi(v.x), roundi(v.y), roundi(v.z))


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	var usual: Dictionary = game.enemy_data["player"]["palette"]
	var dress: Dictionary = game.level_entry.get("stranger", {})
	check(step == "test_yard" or not dress.is_empty(), "the level names no clothes for him")
	for slot in usual:
		var want: Array = dress.get(slot, usual[slot])
		check(_worn(slot) == Color8(want[0], want[1], want[2]), "%s worn %s, not %s" % [slot, _worn(slot), want])
	check(game.player.upper_spr.material == game.player.legs_spr.material, "his top and legs painted differently")
	var faces: Dictionary = game.meta["ui"].get("portraits", {})
	check(faces.has(step) == not dress.is_empty(), "a portrait for him dressed here: %s" % faces.has(step))
	if faces.has(step):
		check(ResourceLoader.exists(faces[step]), "the portrait's missing: %s" % faces[step])
	if step == "silencio":
		check(_worn("coat").v < 0.2, "not in black in the snow: %s" % _worn("coat"))
	game.queue_free()
	if todo.is_empty():
		print("dress test: %s" % ("OK" if failures == 0 else "FAILED (%d)" % failures))
		quit(1 if failures else 0)
		return true
	_open(todo.pop_front())
	return false
