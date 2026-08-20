extends "res://scripts/map_base.gd"

# ========== 城镇地图 ==========
# 基于 assets/Charactor/map.png 的俯视城镇地图，
# 地图上的 9 处建筑作为可交互地点（港口为起点，教堂为 Boss 点）。
# 地点的视觉表现由场景内 Background 下的同名 AnimatedSprite2D 子节点承担，
# 坐标以地图中心为原点（map.png 为 1920x1080，背景 Sprite2D 默认居中）。

func get_nodes() -> Array:
	# id 与场景内地点子节点名一致，position 与子节点摆放位置一致
	return [
		{"id": "harbor",      "type": "start",  "position": Vector2(17.0, 399.0)},    # 港口（起点）
		{"id": "ocean_park",  "type": "medium", "position": Vector2(-583.0, 159.0)},  # 海洋公园
		{"id": "711",         "type": "small",  "position": Vector2(502.0, -51.0)},   # 披萨店
		{"id": "center_park", "type": "big",    "position": Vector2(21.0, 102.0)},    # 中心公园
		{"id": "gas_station", "type": "small",  "position": Vector2(-425.0, -81.0)},  # 加油站
		{"id": "diner",       "type": "small",  "position": Vector2(628.0, 161.0)},   # 24h 便利店
		{"id": "scraper",     "type": "medium", "position": Vector2(-625.0, -318.0)}, # 高楼区
		{"id": "hill",        "type": "medium", "position": Vector2(53.0, -322.0)},   # 山丘
		{"id": "church",      "type": "boss",   "position": Vector2(678.0, -335.0)},  # 教堂（Boss）
	]


func get_connections() -> Array:
	# 沿城镇道路布置的无向连接，保证全图连通且可回头
	return [
		["harbor", "center_park"],
		["harbor", "ocean_park"],
		["harbor", "711"],
		["center_park", "gas_station"],
		["center_park", "diner"],
		["center_park", "hill"],
		["ocean_park", "gas_station"],
		["gas_station", "scraper"],
		["scraper", "hill"],
		["hill", "church"],
		["diner", "church"],
		["diner", "711"],
	]


func get_place_nodes() -> Dictionary:
	# 地点 id -> 场景内的地点节点（AnimatedSprite2D），供 MapGenerator 绑定交互
	return {
		"harbor": get_node("Background/harbor"),
		"ocean_park": get_node("Background/ocean_park"),
		"711": get_node("Background/711"),
		"center_park": get_node("Background/center_park"),
		"gas_station": get_node("Background/gas_station"),
		"diner": get_node("Background/diner"),
		"scraper": get_node("Background/scraper"),
		"hill": get_node("Background/hill"),
		"church": get_node("Background/church"),
	}
