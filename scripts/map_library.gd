class_name MapLibrary
extends RefCounted

# ========== 地图库 ==========
# 统一登记所有可用地图场景；开始新游戏时由 MapGenerator 从中随机选取一个，
# 直接实例化加入原地图场景。
# 新增地图：制作继承 MapBase 的地图场景后，把它的 PackedScene 追加到下方数组即可。

const MAP_SCENES: Array[PackedScene] = [
	preload("res://scenes/maps/map_town.tscn"),
]


static func get_map_count() -> int:
	return MAP_SCENES.size()


static func get_map_scene(index: int) -> PackedScene:
	return MAP_SCENES[index]


static func get_random_scene() -> PackedScene:
	return MAP_SCENES[randi() % MAP_SCENES.size()]
