extends RefCounted

static func index_candidates(client_path: String, default_root: String) -> PackedStringArray:
	var candidates := PackedStringArray()
	var roots := PackedStringArray([default_root])
	if not client_path.is_empty():
		var root := client_path.get_base_dir().get_base_dir().get_base_dir()
		if root != default_root:
			roots.insert(0, root)
	var metadata := read_json(client_path.get_basename() + ".json") if not client_path.is_empty() else {}
	var expected: String = metadata.get("assetIndex", {}).get("id", "")
	for root in roots:
		var indexes := root.path_join("assets/indexes")
		if not DirAccess.dir_exists_absolute(indexes):
			continue
		var files := Array(DirAccess.get_files_at(indexes))
		files.sort_custom(func(a: String, b: String): return a.naturalnocasecmp_to(b) > 0)
		if files.has(expected + ".json"):
			files.erase(expected + ".json")
			files.push_front(expected + ".json")
		for file: String in files:
			if file.get_extension() == "json":
				candidates.append(indexes.path_join(file))
	return candidates

static func object_path(index_path: String, objects: Dictionary, key: String) -> String:
	var entry: Dictionary = objects.get("minecraft/" + key, {})
	var hash_value: String = entry.get("hash", "")
	if hash_value.length() != 40 or not hash_value.is_valid_hex_number():
		return ""
	return index_path.get_base_dir().get_base_dir().path_join("objects").path_join(hash_value.left(2)).path_join(hash_value)

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}
