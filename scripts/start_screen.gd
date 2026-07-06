extends Control
class_name StartScreen

# 引用存档管理器脚本（静态方法调用）
const SaveMgr = preload("res://scripts/save_manager.gd")


func _ready() -> void:
	# 获取按钮引用
	var new_game_btn: Button = $MenuContainer/NewGameButton
	var load_btn: Button = $MenuContainer/LoadButton
	var exit_btn: Button = $MenuContainer/ExitButton

	# 连接按钮信号
	new_game_btn.pressed.connect(_on_new_game_pressed)
	load_btn.pressed.connect(_on_load_pressed)
	exit_btn.pressed.connect(_on_exit_pressed)


func _on_new_game_pressed() -> void:
	# 开始新游戏：跳转到人物选择场景
	get_tree().change_scene_to_file("res://scenes/people_selection.tscn")


func _on_load_pressed() -> void:
	# 读取存档：检查是否存在存档文件
	if not SaveMgr.has_save():
		print("[StartScreen] 没有可用的存档")
		return

	var save_data: Dictionary = SaveMgr.load_game()
	if save_data.is_empty():
		return

	# 恢复存档中的角色选择数据
	SaveMgr.head_index = save_data.get("head_index", -1)
	SaveMgr.body_index = save_data.get("body_index", -1)

	# 跳转到存档中记录的场景
	var scene_path: String = save_data.get("current_scene", "")
	if scene_path != "" and FileAccess.file_exists(scene_path):
		get_tree().change_scene_to_file(scene_path)
	else:
		# 存档场景无效时，回退到地图场景
		get_tree().change_scene_to_file("res://scenes/map.tscn")


func _on_exit_pressed() -> void:
	# 退出游戏
	get_tree().quit()
