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

# 地图状态：当前所在节点 id、随机种子与地图库索引（供读档恢复地图）
static var current_node_id: String = ""
static var map_seed: int = 0
static var map_index: int = -1

# 暴露度：玩家每进入一个新地点自动加一
static var exposure_level: int = 0

# 有机物：初始 10，玩家每移动一次减一，归零时游戏结束
const ORGANIC_INITIAL: int = 10
static var organic_level: int = ORGANIC_INITIAL

# 金币：初始 0，玩家每次使用骰子行动后，按掷骰结果等级（1-5）增加对应数量的金币
const GOLD_INITIAL: int = 0
static var gold_count: int = GOLD_INITIAL

# ========== 骰子系统（由原“行动点”改造而来） ==========
# 每个骰子代表一次行动机会：在事件界面选择选项时消耗一个骰子并掷骰，
# 掷出的点数按固定映射转换为 1-5 的结果，用于影响事件结算（退回地图不消耗）。
# 骰子分 d4 / d8 / d12 三档，可提升档位（提升的触发方式待定，此处仅提供档位与升档接口）。
enum DieTier { D4, D8, D12 }
# 初始骰子数量（与原行动点上限保持一致）
const DICE_INITIAL_COUNT: int = 5
# 各档骰子的面数，按 DieTier 索引（d4=4、d8=8、d12=12）
const DIE_FACES: Array[int] = [4, 8, 12]
# 每个骰子槽位的档位（长度 = 骰子总数）
static var dice_tiers: Array[int] = []
# 已消耗骰子数量：槽位 i 在 i < dice_spent 时视为已消耗（消耗顺序为由前向后）
static var dice_spent: int = 0
# 最近一次掷骰映射得到的结果（1-5），0 表示尚未掷骰或无骰可用
static var last_roll_result: int = 0


func _ready() -> void:
	# 自动加载启动时确保骰子已初始化（直接运行地图等未走新游戏/读档流程时也有效）
	if dice_tiers.is_empty():
		reset_dice()


# ==================== 骰子操作 ====================

static func reset_dice() -> void:
	# 重置为初始骰子组：DICE_INITIAL_COUNT 个 d4，均未消耗
	dice_tiers.clear()
	for i in range(DICE_INITIAL_COUNT):
		dice_tiers.append(DieTier.D4)
	dice_spent = 0
	last_roll_result = 0


static func dice_available_count() -> int:
	# 当前可用（未消耗）骰子数量
	return maxi(dice_tiers.size() - dice_spent, 0)


static func has_available_dice() -> bool:
	# 是否还有可用骰子
	return dice_available_count() > 0


static func consume_and_roll() -> Dictionary:
	# 消耗一个可用骰子并掷骰：返回 {"tier": 档位, "roll": 点数, "result": 映射结果}；
	# 无骰可用时返回空字典（调用方据此判断是否触发掷骰）
	if not has_available_dice():
		return {}

	var tier: int = dice_tiers[dice_spent]
	dice_spent += 1

	var faces: int = DIE_FACES[tier]
	var roll: int = randi_range(1, faces)
	var result: int = roll_result_from_roll(roll)
	last_roll_result = result
	return {"tier": tier, "roll": roll, "result": result}


static func roll_result_from_roll(roll: int) -> int:
	# 将掷骰点数按固定规则映射为 1-5 的结果：
	# 1→1；2、3→2；4、5、6→3；7、8、9、10→4；11、12→5
	if roll <= 1:
		return 1
	if roll <= 3:
		return 2
	if roll <= 6:
		return 3
	if roll <= 10:
		return 4
	return 5


static func upgrade_die(index: int) -> bool:
	# 将指定槽位骰子提升一档（d4→d8→d12）；索引非法或已是最高档时返回 false。
	# 说明：提升的触发方式待定，此处仅提供升档能力，暂未接入任何调用点。
	if index < 0 or index >= dice_tiers.size():
		return false
	if dice_tiers[index] >= DieTier.D12:
		return false
	dice_tiers[index] += 1
	return true


static func set_all_dice_tier(tier: int) -> void:
	# 控制台/调试用：将所有骰子设为指定档位（d4/d8/d12）
	var t: int = clampi(tier, DieTier.D4, DieTier.D12)
	for i in range(dice_tiers.size()):
		dice_tiers[i] = t


static func set_dice_from_save(tiers_raw: Variant, spent: int) -> void:
	# 从存档数据恢复骰子：tiers_raw 为读档得到的普通数组（类型信息已丢失），spent 为已消耗数量；
	# 数据缺失或非法时回退为初始骰子组
	dice_tiers.clear()
	if typeof(tiers_raw) == TYPE_ARRAY:
		for t in tiers_raw:
			dice_tiers.append(clampi(int(t), DieTier.D4, DieTier.D12))

	if dice_tiers.is_empty():
		reset_dice()
		return

	dice_spent = clampi(spent, 0, dice_tiers.size())
	last_roll_result = 0


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
	config.set_value("map", "map_index", map_index)
	config.set_value("map", "exposure_level", exposure_level)
	config.set_value("map", "organic_level", organic_level)
	config.set_value("map", "gold_count", gold_count)
	config.set_value("map", "dice_tiers", dice_tiers)
	config.set_value("map", "dice_spent", dice_spent)
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
		"map_index": config.get_value("map", "map_index", -1),
		"exposure_level": config.get_value("map", "exposure_level", 0),
		"organic_level": config.get_value("map", "organic_level", ORGANIC_INITIAL),
		"gold_count": config.get_value("map", "gold_count", GOLD_INITIAL),
		"dice_tiers": config.get_value("map", "dice_tiers", []),
		"dice_spent": config.get_value("map", "dice_spent", 0),
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
	map_index = -1
	exposure_level = 0
	organic_level = ORGANIC_INITIAL
	gold_count = GOLD_INITIAL
	reset_dice()
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
	map_index = -1
	exposure_level = 0
	organic_level = ORGANIC_INITIAL
	gold_count = GOLD_INITIAL
	reset_dice()

	print("[SaveManager] 所有存档已清除")
