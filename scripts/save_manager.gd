extends Node

# ========== 存档管理器 —— 全部使用静态方法，通过 preload 引用 ==========

# 存档文件在用户目录下的固定路径
const SAVE_PATH: String = "user://savegame.cfg"

# 内存中暂存当前角色选择结果，供存档时写入
static var head_index: int = -1
static var body_index: int = -1


# ==================== 存档操作 ====================

static func save_game(current_scene: String = "") -> void:
	# 将当前游戏进度写入存档文件
	var config := ConfigFile.new()
	config.set_value("game", "current_scene", current_scene)
	config.set_value("character", "head_index", head_index)
	config.set_value("character", "body_index", body_index)
	config.set_value("meta", "timestamp", Time.get_datetime_string_from_system())
	config.save(SAVE_PATH)
	print("[SaveManager] 存档已保存 → 场景: %s, 头: %d, 身体: %d" % [current_scene, head_index, body_index])


static func load_game() -> Dictionary:
	# 从存档文件读取游戏进度，返回包含各字段的字典
	# 如果读不到文件则返回空字典
	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)
	if err != OK:
		print("[SaveManager] 未找到存档文件")
		return {}

	return {
		"current_scene": config.get_value("game", "current_scene", ""),
		"head_index": config.get_value("character", "head_index", -1),
		"body_index": config.get_value("character", "body_index", -1),
		"timestamp": config.get_value("meta", "timestamp", "")
	}


static func has_save() -> bool:
	# 检查是否存在存档文件
	return FileAccess.file_exists(SAVE_PATH)


static func delete_save() -> void:
	# 删除存档文件（可用于"新游戏"覆盖旧存档）
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		print("[SaveManager] 存档已删除")
