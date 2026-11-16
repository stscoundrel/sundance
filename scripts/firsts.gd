class_name Firsts
extends RefCounted
## What the stranger's been told once (hints.json's "first": the first "?" over a
## bandit, the first wound, the first quiet kill...), kept in user://hints.json across
## sittings, so a hand who's heard it isn't told again, until the player forgets them
## (the picker's "FORGET THE HINTS"). A hint waits its turn: one at a time, under the
## HUD's (hud._draw_hint), and it only counts as told once it's been shown.
##
## The tests never touch the player's own: under "fixed_seed" nothing is kept, unless
## a test names its own file (the "hints_file" meta).

const FILE := "user://hints.json"

var lines: Dictionary        # key -> what he's told
var told := {}               # the keys he's been told
var waiting: Array[String] = []


func _init(first: Dictionary) -> void:
	lines = first
	told = _kept()


static func _file() -> String:
	if Engine.has_meta("hints_file"):
		return Engine.get_meta("hints_file")
	return "" if Engine.has_meta("fixed_seed") else FILE


static func _kept() -> Dictionary:
	var path := _file()
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	return d if d is Dictionary else {}


## The moment for hint `key`: it waits its turn, unless he's had it already (or it's
## already waiting). `now` puts it first (going down in the dirt can't wait).
func once(key: String, now := false) -> void:
	if told.has(key) or key in waiting or not lines.has(key):
		return
	if now:
		waiting.push_front(key)
	else:
		waiting.append(key)


## The next hint to show, now told and kept; "" with none waiting.
func next() -> String:
	if waiting.is_empty():
		return ""
	var key: String = waiting.pop_front()
	told[key] = true
	var path := _file()
	if path != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(told, " "))
	return lines[key]


## The player wants telling again: every hint forgotten.
func forget() -> void:
	told = {}
	waiting.clear()
	var path := _file()
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
