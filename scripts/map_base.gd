class_name MapBase
extends Node2D

# ========== 地图基类 ==========
# 每个地图场景都继承本类，并提供自己的节点、连接与尺寸数据。
# 地图库（MapLibrary）统一登记所有地图场景，MapGenerator 随机选取后实例化加入地图场景。

# 节点数据：每个元素为 {"id": String, "type": String, "position": Vector2}
# type 取值见 MapGenerator 的 TYPE_* 常量（start/small/medium/big/boss）
func get_nodes() -> Array:
	return []


# 连接数据：每个元素为一条无向连接对 [节点A_id, 节点B_id]，双向通行
func get_connections() -> Array:
	return []


# 地点节点：{"id": String -> Node2D}，地图场景内承担地点视觉表现的节点，
# MapGenerator 会在其上绑定点击与悬停交互；返回空字典则由生成器回退为内置 event 节点
func get_place_nodes() -> Dictionary:
	return {}


# 地图区域尺寸（以场景原点为中心的矩形范围），用于计算镜头移动边界
func get_map_size() -> Vector2:
	return Vector2(1920.0, 1080.0)
