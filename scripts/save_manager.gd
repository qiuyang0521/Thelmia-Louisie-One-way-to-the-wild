extends Node

# ========== 存档管理器 —— 3 槽位存档系统 ==========
# 每个槽位独立存储：场景路径、角色选择、玩家位置、地图状态、时间戳

const SAVE_SLOT_COUNT: int = 3
const SAVE_BASE_PATH: String = "user://save_"

# 内存中暂存当前角色选择结果，供存档时写入
static var head_index: int = -1
static var body_index: int = -1

# 临时暂存：调用方在保存前需填充这些字段
static var pending_scene: String = ""
static var pending_position: Vector2 = Vector2.ZERO

# 地图状态：当前所在节点 id 与随机种子（供读档恢复地图）
static var current_node_id: String = ""
static var map_seed: int = 0


# ==================== 工具方法 ====================

static func _slot_path(slot: int) -> String:
	return SAVE_BASE_PATH + str(slot) + ".cfg"


# ==================== 存档操作 ====================

static func save_to_slot(slot: int) -> void:
	# 将 pending_* 暂存数据写入指定槽位
	if slot < 0 or slot >= SAVE_SLOT_COUNT:
		return

	var config := ConfigFile.new()
	config.set_value("game", "current_scene", pending_scene)
	config.set_value("game", "position_x", pending_position.x)
	config.set_value("game", "position_y", pending_position.y)
	config.set_value("character", "head_index", head_index)
	config.set_value("character", "body_index", body_index)
	config.set_value("map", "current_node_id", current_node_id)
	config.set_value("map", "seed", map_seed)
	config.set_value("meta", "timestamp", Time.get_datetime_string_from_system())
	config.save(_slot_path(slot))

	print("[SaveManager] 存档 %d 已保存" % slot)


static func load_from_slot(slot: int) -> Dictionary:
	# 从指定槽位读取完整存档数据，无存档则返回空字典
	var config := ConfigFile.new()
	if config.load(_slot_path(slot)) != OK:
		return {}

	return {
		"current_scene": config.get_value("game", "current_scene", ""),
		"position_x": config.get_value("game", "position_x", 0.0),
		"position_y": config.get_value("game", "position_y", 0.0),
		"head_index": config.get_value("character", "head_index", -1),
		"body_index": config.get_value("character", "body_index", -1),
		"current_node_id": config.get_value("map", "current_node_id", ""),
		"map_seed": config.get_value("map", "seed", 0),
		"timestamp": config.get_value("meta", "timestamp", "")
	}


static func slot_has_save(slot: int) -> bool:
	# 检查指定槽位是否有存档
	return FileAccess.file_exists(_slot_path(slot))


static func get_slot_info(slot: int) -> Dictionary:
	# 返回槽位摘要信息（用于 UI 展示），无存档则返回空字典
	var config := ConfigFile.new()
	if config.load(_slot_path(slot)) != OK:
		return {}

	return {
		"timestamp": config.get_value("meta", "timestamp", ""),
		"head_index": config.get_value("character", "head_index", -1),
		"body_index": config.get_value("character", "body_index", -1),
		"current_scene": config.get_value("game", "current_scene", "")
	}


static func has_any_save() -> bool:
	# 检查是否有任意槽位存有数据（用于开始界面判断）
	for i in range(SAVE_SLOT_COUNT):
		if FileAccess.file_exists(_slot_path(i)):
			return true
	return false


static func reset_state() -> void:
	# 重置所有运行时状态（开始新游戏时调用），不删除存档文件
	head_index = -1
	body_index = -1
	pending_scene = ""
	pending_position = Vector2.ZERO
	current_node_id = ""
	map_seed = 0
	print("[SaveManager] 运行时状态已重置")


static func delete_all_saves() -> void:
	# 重置所有存档进度：删除全部槽位文件并清空角色选择
	for i in range(SAVE_SLOT_COUNT):
		var path := _slot_path(i)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

	# 重置变量
	head_index = -1
	body_index = -1
	pending_scene = ""
	pending_position = Vector2.ZERO
	current_node_id = ""
	map_seed = 0

	print("[SaveManager] 所有存档已清除")
