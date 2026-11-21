extends RefCounted

const P := "godot_craft:"
const STICK := P + "stick"
const ARROW := P + "arrow"
const IRON := P + "iron_ingot"
const RAW_IRON := P + "raw_iron"
const COAL := P + "coal"
const FIBER := P + "fiber"
const FEATHER := P + "feather"
const FLINT := P + "flint"
const PLANK := P + "block_4"
const STONE := P + "block_2"
const WORKBENCH := P + "workbench"
const FURNACE := P + "furnace"

const ITEMS := {
	STICK: {}, ARROW: {}, IRON: {}, RAW_IRON: {}, COAL: {}, FIBER: {}, FEATHER: {}, FLINT: {},
	WORKBENCH: {"name": "Crafting table"}, FURNACE: {},
	P + "wooden_pickaxe": {"durability": 59, "tier": 1, "tool": "pickaxe", "speed": 2.0, "damage": 2, "cooldown": 17},
	P + "stone_pickaxe": {"durability": 131, "tier": 2, "tool": "pickaxe", "speed": 4.0, "damage": 3, "cooldown": 17},
	P + "iron_pickaxe": {"durability": 250, "tier": 3, "tool": "pickaxe", "speed": 6.0, "damage": 4, "cooldown": 17},
	P + "wooden_sword": {"durability": 59, "damage": 4, "cooldown": 13},
	P + "stone_sword": {"durability": 131, "damage": 5, "cooldown": 13},
	P + "iron_sword": {"durability": 250, "damage": 6, "cooldown": 13},
	P + "wooden_axe": {"durability": 59, "tool": "axe", "speed": 2.0, "damage": 7, "cooldown": 25},
	P + "stone_axe": {"durability": 131, "tool": "axe", "speed": 4.0, "damage": 9, "cooldown": 25},
	P + "iron_axe": {"durability": 250, "tool": "axe", "speed": 6.0, "damage": 9, "cooldown": 23},
	P + "bow": {"durability": 384},
	P + "shield": {"durability": 336, "slot": "offhand"},
	P + "iron_helmet": {"durability": 165, "slot": "head", "armor": 2},
	P + "iron_chestplate": {"durability": 240, "slot": "chest", "armor": 6},
	P + "iron_leggings": {"durability": 225, "slot": "legs", "armor": 5},
	P + "iron_boots": {"durability": 195, "slot": "feet", "armor": 2},
}

const LIST := [
	{"id": PLANK, "count": 4, "cost": {P + "block_5": 1}},
	{"id": PLANK, "count": 4, "cost": {P + "block_42": 1}, "name": "Planks from cherry log"},
	{"id": STICK, "count": 4, "cost": {PLANK: 2}},
	{"id": WORKBENCH, "cost": {PLANK: 4}},
	{"id": FURNACE, "cost": {STONE: 8}, "station": WORKBENCH},
	{"id": P + "wooden_pickaxe", "cost": {PLANK: 3, STICK: 2}, "station": WORKBENCH},
	{"id": P + "stone_pickaxe", "cost": {STONE: 3, STICK: 2}, "station": WORKBENCH},
	{"id": IRON, "cost": {RAW_IRON: 1, COAL: 1}, "station": FURNACE},
	{"id": P + "iron_pickaxe", "cost": {IRON: 3, STICK: 2}, "station": WORKBENCH},
	{"id": P + "wooden_sword", "cost": {PLANK: 2, STICK: 1}, "station": WORKBENCH},
	{"id": P + "stone_sword", "cost": {STONE: 2, STICK: 1}, "station": WORKBENCH},
	{"id": P + "iron_sword", "cost": {IRON: 2, STICK: 1}, "station": WORKBENCH},
	{"id": P + "wooden_axe", "cost": {PLANK: 3, STICK: 2}, "station": WORKBENCH},
	{"id": P + "stone_axe", "cost": {STONE: 3, STICK: 2}, "station": WORKBENCH},
	{"id": P + "iron_axe", "cost": {IRON: 3, STICK: 2}, "station": WORKBENCH},
	{"id": P + "bow", "cost": {STICK: 3, FIBER: 3}, "station": WORKBENCH},
	{"id": ARROW, "count": 4, "cost": {STICK: 1, FEATHER: 1, FLINT: 1}, "station": WORKBENCH},
	{"id": P + "shield", "cost": {PLANK: 6, IRON: 1}, "station": WORKBENCH},
	{"id": P + "iron_helmet", "cost": {IRON: 5}, "station": WORKBENCH},
	{"id": P + "iron_chestplate", "cost": {IRON: 8}, "station": WORKBENCH},
	{"id": P + "iron_leggings", "cost": {IRON: 7}, "station": WORKBENCH},
	{"id": P + "iron_boots", "cost": {IRON: 4}, "station": WORKBENCH},
]
