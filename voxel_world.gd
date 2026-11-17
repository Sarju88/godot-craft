extends Node3D

const Blocks = preload("res://blocks.gd")
const CHUNK := 16
const HEIGHT := 64
const SEA := 31
const FACES := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)
]
const CORNERS := [
	[Vector3(1,0,0), Vector3(1,0,1), Vector3(1,1,1), Vector3(1,1,0)],
	[Vector3(0,0,1), Vector3(0,0,0), Vector3(0,1,0), Vector3(0,1,1)],
	[Vector3(0,1,1), Vector3(0,1,0), Vector3(1,1,0), Vector3(1,1,1)],
	[Vector3(0,0,0), Vector3(0,0,1), Vector3(1,0,1), Vector3(1,0,0)],
	[Vector3(1,0,1), Vector3(0,0,1), Vector3(0,1,1), Vector3(1,1,1)],
	[Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0)]
]
const FACE_LIGHT := [0.78, 0.78, 1.0, 0.52, 0.87, 0.87]
const QUAD_UVS := [Vector2(0,1), Vector2(1,1), Vector2(1,0), Vector2(0,0)]
const TRIANGLES := [0, 1, 2, 0, 2, 3]

class Surface:
	var positions := PackedVector3Array()
	var uv := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func quad(points: Array, origin: Vector3, tile: int, light: float, water_surface := false) -> void:
		var start := positions.size()
		var tile_origin := Vector2(tile % Blocks.COLS, tile / Blocks.COLS)
		for i in 4:
			var point: Vector3 = points[i]
			if water_surface and point.y > 0.9:
				point.y = 0.88
			positions.append(origin + point)
			var pixel: Vector2 = QUAD_UVS[i] * 0.96875 + Vector2(0.015625, 0.015625)
			uv.append((tile_origin + pixel) / Vector2(Blocks.COLS, Blocks.ROWS))
			colors.append(Color(light, light, light))
		for corner in TRIANGLES:
			indices.append(start + corner)

	func add_to(mesh: ArrayMesh, material: Material) -> void:
		if indices.is_empty():
			return
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)

var edge := 128
var level_seed := 0
var voxels := PackedByteArray()
var sunlight := PackedInt32Array()
var changed: Dictionary = {}
var dirty: Dictionary = {}
var meshes: Dictionary = {}
var solid_material: StandardMaterial3D
var water_material: StandardMaterial3D
var focus := Vector2i(-100, -100)
var render_radius := 4
var pending_physics: Dictionary = {}

func configure(atlas: Texture2D) -> void:
	solid_material = StandardMaterial3D.new()
	solid_material.albedo_texture = atlas
	solid_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	solid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	solid_material.vertex_color_use_as_albedo = true
	solid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	solid_material.alpha_scissor_threshold = 0.35
	water_material = solid_material.duplicate()
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.cull_mode = BaseMaterial3D.CULL_DISABLED

func inside(p: Vector3i) -> bool:
	return p.x >= 0 and p.x < edge and p.z >= 0 and p.z < edge and p.y >= 0 and p.y < HEIGHT

func index(p: Vector3i) -> int:
	return (p.x + p.z * edge) * HEIGHT + p.y

func get_block(p: Vector3i) -> int:
	return voxels[index(p)] if inside(p) else 0

func collides(p: Vector3i) -> bool:
	return p.x < 0 or p.z < 0 or p.x >= edge or p.z >= edge or p.y < 0 or Blocks.solid(get_block(p))

func generate(new_seed: int, size: int) -> Vector3:
	for old in meshes.values():
		old.queue_free()
	meshes.clear()
	dirty.clear()
	changed.clear()
	pending_physics.clear()
	focus = Vector2i(-100, -100)
	level_seed = new_seed
	edge = size
	voxels = PackedByteArray()
	voxels.resize(edge * edge * HEIGHT)
	sunlight.resize(edge * edge)
	var noise := FastNoiseLite.new()
	noise.seed = new_seed
	noise.frequency = 0.027
	noise.fractal_octaves = 3
	var detail := FastNoiseLite.new()
	detail.seed = new_seed ^ 8399
	detail.frequency = 0.067
	detail.fractal_octaves = 2
	var random := RandomNumberGenerator.new()
	random.seed = new_seed
	var heights := PackedInt32Array()
	heights.resize(edge * edge)
	for z in edge:
		for x in edge:
			var center_bias := 1.0 - clampf(Vector2(x - edge / 2, z - edge / 2).length() / (edge * 0.52), 0.0, 1.0)
			var height := clampi(roundi(30 + center_bias * 6 + noise.get_noise_2d(x, z) * 16 + detail.get_noise_2d(x, z) * 2), 8, HEIGHT - 10)
			var column := x + z * edge
			heights[column] = height
			var i := column * HEIGHT
			voxels[i] = Blocks.BEDROCK
			for y in range(1, height - 2):
				voxels[i + y] = 1
			var top := Blocks.GRASS if height > SEA + 1 else (12 if detail.get_noise_2d(x, z) > -0.2 else 13)
			for y in range(height - 2, height + 1):
				voxels[i + y] = top if y == height or top != Blocks.GRASS else 3
			for y in range(height + 1, SEA + 1):
				voxels[i + y] = Blocks.WATER
	carve_caves(heights, random)
	for z in range(3, edge - 3):
		for x in range(3, edge - 3):
			var ground := heights[x + z * edge]
			if ground <= SEA + 1:
				continue
			var p := Vector3i(x, ground + 1, z)
			var near_center := absi(x - edge / 2) < 4 and absi(z - edge / 2) < 4
			var roll := random.randf()
			if roll < 0.025 and not near_center:
				grow_tree(p, random)
			elif roll < 0.033 and get_block(p) == 0:
				voxels[index(p)] = random.randi_range(8, 9)
	for z in edge:
		for x in edge:
			refresh_light(x, z)
	var middle := edge / 2
	var feet := heights[middle + middle * edge] + 1
	return Vector3(middle + 0.5, maxf(float(feet), SEA + 1) + 0.03, middle + 0.5)

func grow_tree(p: Vector3i, random: RandomNumberGenerator) -> void:
	if get_block(p) != 0 or get_block(p + Vector3i(0, 3, 0)) != 0:
		return
	var trunk := random.randi_range(4, 5)
	for y in range(trunk - 2, trunk + 2):
		var radius := 2 if y < trunk else 1
		for x in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				if absi(x) == radius and absi(z) == radius and random.randf() < 0.6:
					continue
				var leaf := p + Vector3i(x, y, z)
				if inside(leaf) and get_block(leaf) == 0:
					voxels[index(leaf)] = 6
	for y in trunk:
		voxels[index(p + Vector3i(0, y, 0))] = 5

func carve_caves(heights: PackedInt32Array, random: RandomNumberGenerator) -> void:
	for cave in edge * edge / 1200:
		var at := Vector3(random.randi_range(4, edge - 5), random.randi_range(7, SEA), random.randi_range(4, edge - 5))
		var angle := random.randf_range(0, TAU)
		for step in random.randi_range(16, 49):
			angle += random.randf_range(-0.33, 0.33)
			at += Vector3(cos(angle), random.randf_range(-0.68, 0.68), sin(angle))
			var center := Vector3i(at.floor())
			for x in range(-2, 3):
				for y in range(-1, 2):
					for z in range(-2, 3):
						var offset := Vector3i(x, y, z)
						var p := center + offset
						if not inside(p) or p.y < 2 or offset.length_squared() > 5:
							continue
						if p.y >= heights[p.x + p.z * edge] - 1 or get_block(p) != 1:
							continue
						voxels[index(p)] = 0 if p.y > 4 else Blocks.LAVA
	for vein in edge * edge / 11:
		var p := Vector3i(random.randi_range(1, edge - 2), random.randi_range(4, 20), random.randi_range(1, edge - 2))
		var ore := 37 if vein % 7 < 4 else (38 if vein % 7 < 6 else 39)
		for step in random.randi_range(2, 6):
			if get_block(p) == 1:
				voxels[index(p)] = ore
			p += FACES[random.randi_range(0, 5)]

func refresh_light(x: int, z: int) -> void:
	var i := (x + z * edge) * HEIGHT
	var y := HEIGHT - 1
	while y > 0 and (not Blocks.solid(voxels[i + y]) or voxels[i + y] in [6, 14]):
		y -= 1
	sunlight[x + z * edge] = y

func apply_block(p: Vector3i, block: int, record := true) -> void:
	if not inside(p) or voxels[index(p)] == block:
		return
	voxels[index(p)] = block
	if record:
		changed[p] = block
	refresh_light(p.x, p.z)
	mark_chunk(p)
	for side in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		mark_chunk(p + side)

func queue_fluids(cell: Vector3i) -> void:
	for offset in [Vector3i.ZERO, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		var p: Vector3i = cell + offset
		if inside(p) and get_block(p) == 0:
			pending_physics[p] = true

func near_sponge(cell: Vector3i) -> bool:
	for x in range(-2, 3):
		for y in range(-2, 3):
			for z in range(-2, 3):
				if get_block(cell + Vector3i(x, y, z)) == 15:
					return true
	return false

func mark_chunk(p: Vector3i) -> void:
	if inside(p):
		dirty[Vector2i(p.x / CHUNK, p.z / CHUNK)] = true

func tick_build(at: Vector3, radius: int, budget := 1) -> void:
	var next := Vector2i(floori(at.x / CHUNK), floori(at.z / CHUNK))
	if next != focus or radius != render_radius:
		focus = next
		render_radius = radius
		for chunk in meshes:
			meshes[chunk].visible = in_view(chunk)
		for z in range(maxi(0, next.y - radius), mini(edge / CHUNK, next.y + radius + 1)):
			for x in range(maxi(0, next.x - radius), mini(edge / CHUNK, next.x + radius + 1)):
				var chunk := Vector2i(x, z)
				if not meshes.has(chunk):
					dirty[chunk] = true
	for i in budget:
		var best := Vector2i(-1, -1)
		var dist := 100000
		for chunk: Vector2i in dirty:
			var distance := (chunk - focus).length_squared()
			if in_view(chunk) and distance < dist:
				best = chunk
				dist = distance
		if best.x < 0:
			break
		dirty.erase(best)
		build_chunk(best)

func in_view(chunk: Vector2i) -> bool:
	return absi(chunk.x - focus.x) <= render_radius and absi(chunk.y - focus.y) <= render_radius

func build_chunk(chunk: Vector2i) -> void:
	var faces := Surface.new()
	var fluids := Surface.new()
	var cx := chunk.x * CHUNK
	var cz := chunk.y * CHUNK
	for z in range(cz, cz + CHUNK):
		for x in range(cx, cx + CHUNK):
			var i := (x + z * edge) * HEIGHT
			for y in HEIGHT:
				var block := int(voxels[i + y])
				if block == 0:
					continue
				var p := Vector3i(x, y, z)
				var origin := Vector3(x - cx, y, z - cz)
				if Blocks.plant(block):
					for corners in [
						[Vector3(0.12,0,0.12),Vector3(0.88,0,0.88),Vector3(0.88,1,0.88),Vector3(0.12,1,0.12)],
						[Vector3(0.88,0,0.12),Vector3(0.12,0,0.88),Vector3(0.12,1,0.88),Vector3(0.88,1,0.12)]
					]:
						faces.quad(corners, origin, block, 1.0)
						faces.quad([corners[1],corners[0],corners[3],corners[2]], origin, block, 0.87)
					continue
				var lowered := Blocks.liquid(block) and get_block(p + Vector3i.UP) != block
				for side in 6:
					var next: Vector3i = p + FACES[side]
					if side == 3 and y == 0:
						continue
					var neighbor := get_block(next)
					if neighbor == block and block in [6, 14, Blocks.WATER, Blocks.LAVA]:
						continue
					if Blocks.solid(neighbor) and neighbor != 6 and neighbor != 14:
						continue
					if Blocks.liquid(block) and Blocks.liquid(neighbor):
						continue
					var light: float = FACE_LIGHT[side]
					if inside(next) and next.y <= sunlight[next.x + next.z * edge] and block != Blocks.LAVA:
						light *= 0.69
					var surface := fluids if block == Blocks.WATER else faces
					surface.quad(CORNERS[side], origin, Blocks.tile_for(block, side), light, lowered)
	var mesh := ArrayMesh.new()
	faces.add_to(mesh, solid_material)
	fluids.add_to(mesh, water_material)
	var instance: MeshInstance3D = meshes.get(chunk)
	if not is_instance_valid(instance):
		instance = MeshInstance3D.new()
		instance.position = Vector3(cx, 0, cz)
		add_child(instance)
		meshes[chunk] = instance
	instance.mesh = mesh
	instance.visible = true

func ray(origin: Vector3, direction: Vector3, distance: float) -> Dictionary:
	var p := Vector3i(origin.floor())
	var step := Vector3i(signf(direction.x), signf(direction.y), signf(direction.z))
	var t := Vector3(INF, INF, INF)
	var interval := Vector3(INF, INF, INF)
	for axis in 3:
		if step[axis] != 0:
			var edge_pos := float(p[axis] + (1 if step[axis] > 0 else 0))
			t[axis] = (edge_pos - origin[axis]) / direction[axis]
			interval[axis] = absf(1.0 / direction[axis])
	var entered := 0.0
	var normal := Vector3i.ZERO
	while entered <= distance:
		var block := get_block(p)
		if block != 0 and not Blocks.liquid(block):
			return {"cell": p, "normal": normal, "block": block}
		var axis := 0 if t.x <= t.y and t.x <= t.z else (1 if t.y <= t.z else 2)
		entered = t[axis]
		p[axis] += step[axis]
		t[axis] += interval[axis]
		normal = Vector3i.ZERO
		normal[axis] = -step[axis]
	return {}

func fits(feet: Vector3) -> bool:
	var lo := Vector3i((feet + Vector3(-0.3, 0.001, -0.3)).floor())
	var hi := Vector3i((feet + Vector3(0.3, 1.799, 0.3)).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				if collides(Vector3i(x, y, z)):
					return false
	return true
