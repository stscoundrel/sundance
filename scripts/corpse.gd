class_name Corpse
extends Actor
## One of those who died before the stranger rode in (the train's guards and crew):
## a body in the dirt, drawn from the last frame of his death, his blood dried under
## him. He's scenery: rounds go over him, nobody hauls, buries or finds him.


func setup(g: Node, d: Dictionary) -> void:
	setup_body(g, Iso.to_screen(Vector2(d["x"], d["y"])))
	set_character(d["template"], d.get("palette", {}))
	collision_layer = 0
	collision_mask = 0
	hurtbox.collision_layer = 0
	alive = false
	_death = d.get("death", "death_back")
	facing = Vector2.from_angle(deg_to_rad(d.get("facing", 90.0)))
	var a := anim("full/" + _death)
	_show(upper_spr, a, a["frames"][0].size() - 1, Iso.dir8(facing))
	legs_spr.visible = false
