extends CanvasLayer
class_name PauseScreen

# 引用存档管理器脚本
const SaveMgr = preload("res://scripts/save_manager.gd")
# 存档管理界面场景与脚本
const SAVE_SCREEN_SCENE: PackedScene = preload("res://scenes/save_screen.tscn")
const SaveUI = preload("res://scripts/save_screen.gd")


func _ready() -> void:
	# 关键：设置为 ALWAYS 模式，使暂停界面在全局暂停期间仍能接收输入
	# 否则 get_tree().paused = true 会同时冻结本节点的按钮点击和按键监听
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 暂停整个游戏逻辑（物理、_process 等全部冻结）
	get_tree().paused = true

	# 连接按钮信号
	$MenuContainer/ResumeButton.pressed.connect(_on_resume_pressed)
	$MenuContainer/SaveButton.pressed.connect(_on_save_pressed)
	$MenuContainer/QuitButton.pressed.connect(_on_quit_pressed)


func _input(event: InputEvent) -> void:
	# 再次按下暂停键（Escape）时恢复游戏
	# 但如果存档管理界面正在显示，则不处理（交给存档界面）
	if event.is_action_pressed("pause"):
		if _has_save_screen_open():
			return
		_resume_game()


func _on_resume_pressed() -> void:
	# 继续游戏：取消暂停并移除暂停界面
	_resume_game()


func _on_save_pressed() -> void:
	# 收集当前游戏状态，暂存到 SaveManager
	SaveMgr.pending_scene = get_tree().current_scene.scene_file_path
	SaveMgr.pending_position = _get_player_position()

	# 打开存档管理界面（保存模式）
	var save_screen := SAVE_SCREEN_SCENE.instantiate()
	save_screen.mode = SaveUI.Mode.SAVE
	get_tree().current_scene.add_child(save_screen)


func _on_quit_pressed() -> void:
	# 返回标题画面：重置运行时状态，取消暂停，切换场景
	SaveMgr.reset_state()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/start_screen.tscn")


func _get_player_position() -> Vector2:
	# 从当前场景中获取玩家位置（汽车或地图标记）
	var scene := get_tree().current_scene
	# 优先取 CharacterBody2D（驾驶场景中的汽车）
	var car := scene.get_node_or_null("CharacterBody2D") as Node2D
	if car:
		return car.position
	# 其次取 Notation（地图场景中的位置标记）
	var notation := scene.get_node_or_null("Notation") as Node2D
	if notation:
		return notation.position
	return Vector2.ZERO


func _has_save_screen_open() -> bool:
	# 检查当前场景中是否已有存档管理界面
	for child in get_tree().current_scene.get_children():
		if child.get_script() == SaveUI:
			return true
	return false


func _resume_game() -> void:
	# 恢复游戏运行并销毁暂停界面
	get_tree().paused = false
	queue_free()
