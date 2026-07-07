extends CanvasLayer
class_name SaveScreen

# 引用存档管理器脚本
const SaveMgr = preload("res://scripts/save_manager.gd")

# 操作模式：保存 / 读取
enum Mode { SAVE, LOAD }

# 由调用方在 add_child 之前设置，决定界面行为
var mode: Mode = Mode.SAVE


func _ready() -> void:
	# 确保暂停界面自身不受全局暂停影响
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 连接返回按钮
	$VBoxContainer/BackButton.pressed.connect(_on_back_pressed)

	# 连接三个槽位的操作按钮（绑定槽位索引 0/1/2）
	for i in range(3):
		var btn: Button = get_node("VBoxContainer/SlotsContainer/Slot%d/VBoxContainer/ActionButton" % (i + 1))
		btn.pressed.connect(_on_slot_pressed.bind(i))

	# 根据当前存档数据刷新界面文字
	_refresh_slots()


func _input(event: InputEvent) -> void:
	# 按下暂停键（Escape）时关闭存档界面，回到上一层
	if event.is_action_pressed("pause"):
		queue_free()


func _refresh_slots() -> void:
	# 遍历 3 个槽位，根据存档数据更新标签和按钮状态
	for i in range(3):
		var slot_root := get_node("VBoxContainer/SlotsContainer/Slot%d" % (i + 1))
		var info_label: Label = slot_root.get_node("VBoxContainer/InfoLabel")
		var action_btn: Button = slot_root.get_node("VBoxContainer/ActionButton")

		var info := SaveMgr.get_slot_info(i)

		if info.is_empty():
			# 槽位为空
			info_label.text = "空"
			if mode == Mode.LOAD:
				action_btn.disabled = true
				action_btn.text = "无存档"
			else:
				action_btn.disabled = false
				action_btn.text = "保存到此"
		else:
			# 槽位已有存档 —— 显示时间戳和角色信息
			var ts: String = info.get("timestamp", "")
			var hi: int = info.get("head_index", -1)
			var bi: int = info.get("body_index", -1)
			info_label.text = "%s\n头部: %d  身体: %d" % [ts, hi, bi]

			if mode == Mode.SAVE:
				action_btn.disabled = false
				action_btn.text = "覆盖保存"
			else:
				action_btn.disabled = false
				action_btn.text = "读取"


func _on_slot_pressed(slot: int) -> void:
	# 保存模式：将暂存数据写入选中槽位
	if mode == Mode.SAVE:
		SaveMgr.save_to_slot(slot)
		queue_free()
		return

	# 读取模式：从选中槽位加载存档并切换场景
	var data := SaveMgr.load_from_slot(slot)
	if data.is_empty():
		return

	# 恢复角色选择
	SaveMgr.head_index = data.get("head_index", -1)
	SaveMgr.body_index = data.get("body_index", -1)

	# 恢复玩家位置
	var px: float = data.get("position_x", 0.0)
	var py: float = data.get("position_y", 0.0)
	SaveMgr.pending_position = Vector2(px, py)

	# 恢复地图状态：当前节点 id 与地图随机种子
	SaveMgr.current_node_id = data.get("current_node_id", "")
	SaveMgr.map_seed = data.get("map_seed", 0)

	# 取消暂停（可能从暂停界面进入），切换场景
	get_tree().paused = false
	var scene_path: String = data.get("current_scene", "")
	if scene_path != "" and FileAccess.file_exists(scene_path):
		get_tree().change_scene_to_file(scene_path)
	else:
		get_tree().change_scene_to_file("res://scenes/map.tscn")


func _on_back_pressed() -> void:
	# 关闭存档界面，回到上一层（暂停界面或开始界面）
	queue_free()
