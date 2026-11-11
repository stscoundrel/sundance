class_name Record
extends RefCounted
## What the stranger did in each town, for the padre to read over him at his funeral
## (see Funeral). Each town he wins writes over what it said before (only a win
## counts: a town lost, or left halfway, leaves the last win's record standing),
## kept in user://record.json across sittings until the player forgets it (the
## level picker's "FORGET WHAT HE DID").
##
## A town's record is what it asks of him (the condemned man in San Miguel, the
## captive at Cruz Verde, the carriers at Paso Esperanza, Silencio's two gangs) and
## what any town does: the innocents he shot, the wounded he finished in the dirt
## (not shooting back), the men he shot as they dragged or bound up their wounded,
## and the priests who died. A town he's never won says nothing.
##
## The tests never touch the player's own: under "fixed_seed" nothing is kept,
## unless a test names its own file (the "record_file" meta).

const FILE := "user://record.json"


static func _file() -> String:
	if Engine.has_meta("record_file"):
		return Engine.get_meta("record_file")
	return "" if Engine.has_meta("fixed_seed") else FILE


## Every town's kept record: level id -> its record.
static func towns() -> Dictionary:
	var path := _file()
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	return d if d is Dictionary else {}


## A town won: its record kept, over whatever it said before.
static func keep(id: String, rec: Dictionary) -> void:
	var path := _file()
	if path == "":
		return
	var all := towns()
	all[id] = rec
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all, " "))


## The player's had enough of it: every town forgotten.
static func forget() -> void:
	var path := _file()
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## All of it, as the padre reads it: what each town asked of him, and the rest added
## up across the towns. Keys a town never won don't appear (and aren't read out).
static func merged(all: Dictionary) -> Dictionary:
	var out := {}
	for id in all:
		var rec: Dictionary = all[id]
		for k in rec:
			if k in ["innocents", "downed_shot", "rescuers_shot", "priests_dead", "carriers_dead"]:
				out[k] = int(out.get(k, 0)) + int(rec[k])
			else:
				out[k] = rec[k]
	return out
