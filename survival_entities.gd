extends Node3D

const Motion = preload("res://survival_motion.gd")
const Inventory = preload("res://survival_inventory.gd")
const Recipes = preload("res://survival_recipes.gd")
const Blocks = preload("res://blocks.gd")
const MAX_MOBS := 12
const DAY_TICKS := 24000
const KINDS := ["grazer", "stalker", "slinger"]

var game
var mobs: Array[Dictionary] = []
var drops: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var clock := 0

func clear_level() -> void:
	for node in get_children():
		remove_child(node)
		node.queue_free()
	mobs.clear()
	drops.clear()
	projectiles.clear()
	clock = 0

func daylight() -> float:
	return clampf(cos(float(clock) / DAY_TICKS * TAU) * 0.75 + 0.5, 0.12, 1.0)

func drop(item: Dictionary, at: Vector3, delay := 12, age := 0) -> void:
	if item.is_empty():
		return
	var model := make_model(at, [Vector3(0.22, 0.22, 0.22)], [Color("ffcb7c")])
	drops.append({"item": item.duplicate(), "at": at, "delay": delay, "age": age, "model": model})

func spawn(kind: String, at: Vector3, health := -1.0) -> void:
	var color := Color("b88d65") if kind == "grazer" else (Color("64714d") if kind == "stalker" else Color("8a849f"))
	var model := make_model(at, [Vector3(0.62, 0.42, 0.7), Vector3(0.38, 0.32, 0.38)],
		[color, color.lightened(0.22)]) if kind == "grazer" else make_model(at,
		[Vector3(0.48, 0.81, 0.38), Vector3(0.38, 0.37, 0.39)], [color, color.lightened(0.22)])
	var motion := Motion.new()
	motion.reset(at)
	mobs.append({"kind": kind, "motion": motion, "health": health if health >= 0.0 else (10.0 if kind == "grazer" else 20.0),
		"model": model, "cooldown": 0, "heading": randf_range(-PI, PI), "hurt": 0})

func make_model(at: Vector3, parts: Array, colors: Array) -> Node3D:
	var model := Node3D.new()
	add_child(model)
	model.position = at
	var y := 0.05
	for i in parts.size():
		var mesh := BoxMesh.new()
		mesh.size = parts[i]
		mesh.material = game.flat_material(colors[i])
		var part := MeshInstance3D.new()
		part.mesh = mesh
		part.position.y = y + mesh.size.y * 0.5
		model.add_child(part)
		y += mesh.size.y
	return model

func read_state(data: Dictionary) -> void:
	clock = posmod(int(data.get("clock", 0)), DAY_TICKS)
	for entry in data.get("drops", []):
		var item := Inventory.valid_stack(entry.get("item", {}))
		var at: Vector3 = entry.get("at", Vector3.ZERO)
		if not item.is_empty() and game.world.inside(Vector3i(at.floor())):
			drop(item, at, 8, int(entry.get("age", 0)))
	for entry in data.get("mobs", []):
		var at: Vector3 = entry.get("at", Vector3.ZERO)
		if mobs.size() < MAX_MOBS and entry.get("kind") in KINDS and game.world.fits(at):
			spawn(entry.kind, at, float(entry.get("health", -1.0)))

func write_state() -> Dictionary:
	var saved_drops := []
	var saved_mobs := []
	for entry in drops:
		saved_drops.append({"item": entry.item, "at": entry.at, "age": entry.age})
	for mob in mobs:
		saved_mobs.append({"kind": mob.kind, "health": mob.health, "at": mob.motion.position})
	return {"clock": clock, "drops": saved_drops, "mobs": saved_mobs}

func tick() -> void:
	clock = (clock + 1) % DAY_TICKS
	if clock % 40 == 0:
		try_spawn()
	for i in range(drops.size() - 1, -1, -1):
		var entry := drops[i]
		entry.delay -= 1
		entry.age += 1
		var at: Vector3 = entry.at
		var box := AABB(at - Vector3(0.1, 0.0, 0.1), Vector3(0.2, 0.2, 0.2))
		at.y += Motion.clip_axis(game.world, box, 1, -0.16)
		entry.at = at
		entry.model.position = at + Vector3.UP * (0.1 + sin(entry.age * 0.15) * 0.07)
		entry.model.rotation.y += 0.07
		if entry.delay <= 0 and at.distance_squared_to(game.feet + Vector3.UP * 0.4) < 2.25:
			entry.item.count = game.inventory.add(entry.item.id, entry.item.count, entry.item.wear)
		if entry.age >= 6000 or entry.item.count <= 0:
			entry.model.queue_free()
			drops.remove_at(i)
	for i in range(mobs.size() - 1, -1, -1):
		if mobs[i].motion.position.distance_squared_to(game.feet) > 64.0 * 64.0:
			mobs[i].model.queue_free()
			mobs.remove_at(i)
		else:
			tick_mob(mobs[i])
	tick_projectiles()

func occupied(box: AABB) -> bool:
	for mob in mobs:
		if Motion.bounds(mob.motion.position, 0.9 if mob.kind == "grazer" else 1.55).intersects(box):
			return true
	return false

func try_spawn() -> void:
	if mobs.size() >= MAX_MOBS:
		return
	var angle := randf_range(-PI, PI)
	var at: Vector3 = game.feet + Vector3(cos(angle), 0, sin(angle)) * randf_range(15, 26)
	var x := floori(at.x)
	var z := floori(at.z)
	if x < 1 or z < 1 or x >= game.world.edge - 1 or z >= game.world.edge - 1:
		return
	var y: int = game.world.sunlight[x + z * game.world.edge]
	at = Vector3(x + 0.5, y + 1.0, z + 0.5)
	var ground: int = game.world.get_block(Vector3i(x, y, z))
	if not game.world.fits(at) or game.world.get_block(Vector3i(at.floor())) != 0:
		return
	if occupied(Motion.bounds(at)):
		return
	var grazers := 0
	for mob in mobs:
		if mob.kind == "grazer":
			grazers += 1
	if daylight() > 0.5 and ground == Blocks.GRASS and grazers < 4:
		spawn("grazer", at)
	elif daylight() < 0.35 and Blocks.solid(ground) and mobs.size() - grazers < 8:
		spawn(["stalker", "slinger"].pick_random(), at)

func tick_mob(mob: Dictionary) -> void:
	var motion: Motion = mob.motion
	var offset: Vector3 = game.feet - motion.position
	var distance := offset.length()
	var hostile: bool = mob.kind != "grazer"
	var chasing := hostile and distance < 20.0
	var facing := Vector3(offset.x, 0, offset.z).normalized()
	var direction := facing * 0.45 if chasing else Vector3(cos(mob.heading), 0, sin(mob.heading)) * 0.25
	if chasing and mob.kind == "slinger" and distance < 10.0:
		direction = -facing * 0.25 if distance < 4.0 else Vector3.ZERO
	if chasing and mob.kind == "stalker" and distance < 1.4:
		direction = Vector3.ZERO
	if not chasing and clock % 120 == 0:
		mob.heading += randf_range(-1.4, 1.4)
	mob.cooldown = maxi(0, mob.cooldown - 1)
	mob.hurt = maxi(0, mob.hurt - 1)
	var low: Vector3 = motion.position + direction.normalized() * 0.68
	var jump: bool = not direction.is_zero_approx() and game.world.collides(Vector3i((low + Vector3.UP * 0.1).floor()))
	motion.tick(game.world, direction, jump, false, false)
	mob.model.position = motion.position
	if not direction.is_zero_approx():
		mob.model.rotation.y = atan2(direction.x, direction.z)
	if not chasing or mob.cooldown > 0:
		return
	var from := motion.position + Vector3.UP
	var to: Vector3 = game.feet + Vector3.UP
	var obstruction: Dictionary = game.world.ray(from, (to - from).normalized(), from.distance_to(to))
	if not obstruction.is_empty():
		return
	if mob.kind == "stalker" and distance < 1.65:
		if game.hurt_player(3.0, from, true):
			game.motion.velocity += facing * 0.27
		mob.cooldown = 20
	elif mob.kind == "slinger" and distance < 13.0:
		shoot(from, (to - from + Vector3.UP * 0.12 * distance).normalized(), 0.68, 3.0, false)
		mob.cooldown = 45

func find_target(origin: Vector3, direction: Vector3, reach: float) -> int:
	var result := -1
	for i in mobs.size():
		var mob := mobs[i]
		var height := 0.9 if mob.kind == "grazer" else 1.55
		var box := Motion.bounds(mob.motion.position, height)
		var hit: Variant = box.intersects_segment(origin, origin + direction * reach)
		if hit != null:
			reach = origin.distance_to(hit)
			if game.world.ray(origin, direction, reach).is_empty():
				result = i
	return result

func hurt_mob(index: int, amount: float, impulse: Vector3) -> void:
	var mob := mobs[index]
	if mob.hurt > 0:
		return
	mob.health -= amount
	mob.hurt = 10
	mob.motion.velocity += impulse
	if mob.health > 0:
		return
	var at: Vector3 = mob.motion.position
	if mob.kind == "grazer":
		drop(Inventory.stack(Recipes.FEATHER, 2), at)
	elif mob.kind == "stalker":
		drop(Inventory.stack(Recipes.FIBER, 2), at)
	else:
		drop(Inventory.stack(Recipes.ARROW, 2), at)
	mob.model.queue_free()
	mobs.remove_at(index)

func shoot(from: Vector3, direction: Vector3, speed: float, damage: float, friendly: bool) -> void:
	var model := make_model(from, [Vector3(0.07, 0.07, 0.22)], [Color("eee2bf")])
	projectiles.append({"at": from, "velocity": direction * speed, "damage": damage,
		"friendly": friendly, "life": 100, "model": model})

func tick_projectiles() -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var shot := projectiles[i]
		var velocity: Vector3 = shot.velocity
		var from: Vector3 = shot.at
		var to := from + velocity
		var direction := velocity.normalized()
		var distance := velocity.length()
		var hit_block: Dictionary = game.world.ray(from, direction, distance)
		var struck := false
		if shot.friendly:
			var target := find_target(from, direction, distance)
			if target >= 0:
				hurt_mob(target, shot.damage, direction * 0.25 + Vector3.UP * 0.1)
				struck = true
		else:
			var intersection: Variant = game.player_bounds(game.feet).intersects_segment(from, to)
			if intersection != null and game.world.ray(from, direction, from.distance_to(intersection)).is_empty():
				game.hurt_player(shot.damage, from, true)
				struck = true
		shot.life -= 1
		if struck or not hit_block.is_empty() or shot.life <= 0:
			shot.model.queue_free()
			projectiles.remove_at(i)
		else:
			shot.at = to
			shot.velocity = velocity * 0.99 + Vector3.DOWN * 0.05
			shot.model.position = to
