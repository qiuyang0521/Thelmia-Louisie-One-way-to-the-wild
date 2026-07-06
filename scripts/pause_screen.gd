extends CanvasLayer
class_name PauseScreen

# 引用存档管理器脚本
const SaveMgr = preload("res://scripts/save_manager.gd")


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
	if event.is_action_pressed("pause"):
		_resume_game()


func _on_resume_pressed() -> void:
	# 继续游戏：取消暂停并移除暂停界面
	_resume_game()


func _on_save_pressed() -> void:
	# 保存当前游戏进度：写入当前场景路径和角色选择数据
	var current_scene := get_tree().current_scene.scene_file_path
	SaveMgr.save_game(current_scene)


func _on_quit_pressed() -> void:
	# 返回标题画面：先取消暂停，再切换场景
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/start_screen.tscn")


func _resume_game() -> void:
	# 恢复游戏运行并销毁暂停界面
	get_tree().paused = false
	queue_free()
