extends RefCounted

const DIRECTORY := "user://survival_worlds"
const VERSION := 2

static func list_worlds() -> Array[Dictionary]:
	var worlds: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(DIRECTORY):
		return worlds
	for file in DirAccess.get_files_at(DIRECTORY):
		if file.get_extension() != "cfg":
			continue
		var data := ConfigFile.new()
		if data.load(DIRECTORY.path_join(file)) != OK or data.get_value("world", "version", 0) not in [1, VERSION]:
			continue
		worlds.append({
			"id": file.get_basename(),
			"name": data.get_value("world", "name", "Unnamed World"),
			"seed": data.get_value("world", "seed", 0),
			"updated": data.get_value("world", "updated", 0)
		})
	worlds.sort_custom(func(a: Dictionary, b: Dictionary): return a.updated > b.updated)
	return worlds

static func read(id: String) -> ConfigFile:
	var data := ConfigFile.new()
	if data.load(DIRECTORY.path_join(id + ".cfg")) != OK or data.get_value("world", "version", 0) not in [1, VERSION]:
		return null
	return data

static func write(id: String, data: ConfigFile) -> Error:
	var directory := ProjectSettings.globalize_path(DIRECTORY)
	var result := DirAccess.make_dir_recursive_absolute(directory)
	if result != OK:
		return result
	var target := directory.path_join(id + ".cfg")
	var temporary := target + ".tmp"
	result = data.save(temporary)
	if result != OK:
		return result
	return DirAccess.rename_absolute(temporary, target)
