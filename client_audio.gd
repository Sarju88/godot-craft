extends RefCounted

const ClientCache = preload("res://client_cache.gd")

var steps: Array[AudioStreamOggVorbis] = []
var edits: Array[AudioStreamOggVorbis] = []
var music: AudioStreamOggVorbis

func load_from(client_path: String, root: String) -> void:
	for index_path in ClientCache.index_candidates(client_path, root):
		var objects: Dictionary = ClientCache.read_json(index_path).get("objects", {})
		if steps.is_empty():
			steps = load_variants(index_path, objects, "step/grass")
		if edits.is_empty():
			edits = load_variants(index_path, objects, "dig/stone")
		if music == null:
			music = load_clip(index_path, objects, "music/menu/beginning_2")
			if music != null:
				music.loop = true
		if not steps.is_empty() and not edits.is_empty() and music != null:
			return

func load_variants(index_path: String, objects: Dictionary, event: String) -> Array[AudioStreamOggVorbis]:
	var clips: Array[AudioStreamOggVorbis] = []
	for i in range(1, 5):
		var clip := load_clip(index_path, objects, event + str(i))
		if clip != null:
			clips.append(clip)
	return clips

func load_clip(index_path: String, objects: Dictionary, key: String) -> AudioStreamOggVorbis:
	var path := ClientCache.object_path(index_path, objects, "sounds/" + key + ".ogg")
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	return AudioStreamOggVorbis.load_from_buffer(FileAccess.get_file_as_bytes(path))
