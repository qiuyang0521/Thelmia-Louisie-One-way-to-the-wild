extends Control
class_name StartScreen

# 引用存档管理器脚本（静态方法调用）
const SaveMgr = preload("res://scripts/save_manager.gd")
# 存档管理界面场景与脚本
const SAVE_SCREEN_SCENE: PackedScene = preload("res://scenes/save_screen.tscn")
const SaveUI = preload("res://scripts/save_screen.gd")


func _ready() -> void:
	# 获取按钮引用
	var new_game_btn: Button = $MenuContainer/NewGameButton
	var load_btn: Button = $MenuContainer/LoadButton
	var exit_btn: Button = $MenuContainer/ExitButton
	var reset_btn: Button = $ResetButton

	# 连接按钮信号
	new_game_btn.pressed.connect(_on_new_game_pressed)
	load_btn.pressed.connect(_on_load_pressed)
	exit_btn.pressed.connect(_on_exit_pressed)
	reset_btn.pressed.connect(_on_reset_pressed)


func _on_new_game_pressed() -> void:
	# 开始新游戏：重置运行时状态，跳转到人物选择场景
	SaveMgr.reset_state()
	get_tree().change_scene_to_file("res://scenes/people_selection.tscn")


func _on_load_pressed() -> void:
	# 打开存档管理界面（读取模式），让玩家选择要读取的槽位
	var save_screen := SAVE_SCREEN_SCENE.instantiate()
	save_screen.mode = SaveUI.Mode.LOAD
	add_child(save_screen)


func _on_exit_pressed() -> void:
	# 退出游戏
	get_tree().quit()


func _on_reset_pressed() -> void:
	# 重置所有存档进度：删除全部存档槽位文件
	SaveMgr.delete_all_saves()
	print("[StartScreen] 存档已全部重置")
