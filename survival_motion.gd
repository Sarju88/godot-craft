extends RefCounted

const World = preload("res://voxel_world.gd")
const Blocks = preload("res://blocks.gd")
const STEP := 0.05
const WIDTH := 0.6
const STANDING := 1.8
const CROUCHING := 1.5
const STEP_HEIGHT := 0.6
const EPSILON := 0.00001

var position := Vector3.ZERO
var velocity := Vector3.ZERO
var grounded := false
var crouching := false
var fall_distance := 0.0
var landed_distance := 0.0
var jump_delay := 0

func reset(at: Vector3) -> void:
	position = at
	velocity = Vector3.ZERO
	grounded = false
	crouching = false
	fall_distance = 0.0
	landed_distance = 0.0
	jump_delay = 0

func tick(world: World, direction: Vector3, jump: bool, sprint: bool, sneak: bool) -> void:
	crouching = sneak or world.overlaps_solid(bounds(position, STANDING))
	var height := CROUCHING if crouching else STANDING
	var box := bounds(position, height)
	var fluid := world.fluid_in(box)
	var in_water := fluid == Blocks.WATER
	var in_lava := fluid == Blocks.LAVA
	var wet := in_water or in_lava
	var on_ground := clip_axis(world, box, 1, -0.04) > -0.04 + EPSILON
	var drag := 0.546 if on_ground else 0.91
	var acceleration := (0.1 if on_ground else 0.02) * (1.3 if sprint else 1.0)
	if wet:
		drag = (0.9 if sprint else 0.8) if in_water else 0.5
		acceleration = 0.02
	velocity += direction.limit_length() * acceleration * (0.3 if crouching and not wet else 1.0)
	if jump_delay > 0:
		jump_delay -= 1
	if not jump:
		jump_delay = 0
	if jump and wet:
		velocity.y += 0.04
	elif jump and on_ground and jump_delay == 0:
		velocity.y = 0.42
		if sprint:
			velocity += direction.normalized() * 0.2
		jump_delay = 10
	if sneak and wet:
		velocity.y -= 0.04

	var requested := velocity
	if crouching and on_ground and not wet and requested.y <= 0.0:
		requested = protect_edge(world, box, requested)
	var moved := sweep(world, box, requested)
	if (on_ground or moved.y > requested.y + EPSILON) and requested.y <= 0.0 and not wet:
		if horizontal_squared(moved) + EPSILON < horizontal_squared(requested):
			var raised := clip_axis(world, box, 1, STEP_HEIGHT)
			var step_box := translated(box, Vector3.UP * raised)
			var step := sweep(world, step_box, Vector3(requested.x, 0, requested.z))
			step_box = translated(step_box, step)
			step.y = raised + clip_axis(world, step_box, 1, requested.y - raised)
			if horizontal_squared(step) > horizontal_squared(moved) + EPSILON:
				moved = step
	position += moved
	grounded = requested.y <= 0.0 and clip_axis(world, bounds(position, height), 1, -0.001) > -0.001 + EPSILON
	for axis in 3:
		if absf(moved[axis] - requested[axis]) > EPSILON:
			velocity[axis] = 0.0
	velocity.x *= drag
	velocity.z *= drag
	if wet:
		velocity.y = velocity.y * (0.8 if in_water else 0.5) - (0.005 if in_water else 0.02)
	else:
		velocity.y = (velocity.y - 0.08) * 0.98

	landed_distance = 0.0
	if world.fluid_in(bounds(position, height)) == Blocks.WATER:
		fall_distance = 0.0
	else:
		fall_distance += maxf(0.0, -moved.y)
		if grounded:
			landed_distance = fall_distance
			fall_distance = 0.0

static func horizontal_squared(vector: Vector3) -> float:
	return vector.x * vector.x + vector.z * vector.z

static func bounds(at: Vector3, height := STANDING) -> AABB:
	return AABB(at - Vector3(WIDTH * 0.5, 0.0, WIDTH * 0.5), Vector3(WIDTH, height, WIDTH))

static func translated(box: AABB, offset: Vector3) -> AABB:
	return AABB(box.position + offset, box.size)

static func protect_edge(world: World, box: AABB, requested: Vector3) -> Vector3:
	for axis in [0, 2]:
		var offset := Vector3.DOWN * STEP_HEIGHT
		offset[axis] = requested[axis]
		while absf(requested[axis]) > EPSILON and not world.overlaps_solid(translated(box, offset)):
			requested[axis] = move_toward(requested[axis], 0.0, 0.05)
			offset[axis] = requested[axis]
	while horizontal_squared(requested) > EPSILON:
		var offset := Vector3(requested.x, -STEP_HEIGHT, requested.z)
		if world.overlaps_solid(translated(box, offset)):
			break
		requested.x = move_toward(requested.x, 0.0, 0.05)
		requested.z = move_toward(requested.z, 0.0, 0.05)
	return requested

static func sweep(world: World, box: AABB, requested: Vector3) -> Vector3:
	var result := Vector3.ZERO
	var first := 0 if absf(requested.x) >= absf(requested.z) else 2
	for axis: int in [1, first, 2 - first]:
		result[axis] = clip_axis(world, box, axis, requested[axis])
		var offset := Vector3.ZERO
		offset[axis] = result[axis]
		box = translated(box, offset)
	return result

static func clip_axis(world: World, box: AABB, axis: int, distance: float) -> float:
	if absf(distance) < EPSILON:
		return 0.0
	var offset := Vector3.ZERO
	offset[axis] = distance
	var swept := box.merge(translated(box, offset))
	var low := Vector3i((swept.position + Vector3.ONE * EPSILON).floor())
	var high := Vector3i((swept.end - Vector3.ONE * EPSILON).floor())
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1):
				var cell := Vector3i(x, y, z)
				if not world.collides(cell):
					continue
				if distance > 0.0 and cell[axis] >= box.end[axis] - EPSILON:
					distance = minf(distance, maxf(0.0, cell[axis] - box.end[axis]))
				elif distance < 0.0 and cell[axis] + 1 <= box.position[axis] + EPSILON:
					distance = maxf(distance, minf(0.0, cell[axis] + 1 - box.position[axis]))
	return distance
