extends CanvasLayer
class_name PauseScreen

# 存档管理界面场景与脚本
const SAVE_SCREEN_SCENE: PackedScene = preload("res://scenes/save_screen.tscn")
const SaveUI = preload("res://scripts/save_screen.gd")

# 暂停界面被打开（实例化）时的帧号：用于屏蔽打开它的那次 ESC 按键，
# 避免同一次输入既打开又立即关闭暂停界面；之后的新 ESC 按键即可正常退出。
var opened_frame: int = Engine.get_process_frames()
# 打开暂停界面后，ESC 是否已经松开过一次：
# 防止打开时按住 ESC 不放，系统自动重复的按键事件被误当作“再次按下”；
# 只有松开过之后的新按下才会退出暂停。
var esc_released_once: bool = not Input.is_key_pressed(KEY_ESCAPE)
# 暂停界面是否已关闭（防止多通道重复触发）
var closed: bool = false


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


func _process(_delta: float) -> void:
	# 兜底通道：部分情况下全局暂停会阻断 _input 事件回调的派发，
	# 因此在 ALWAYS 模式下直接轮询按键状态（本节点的 _process 在暂停期间仍会执行）。
	if closed or not get_tree().paused:
		return

	# ESC 尚未松开过：跳过本帧，只记录松开动作。
	if not esc_released_once:
		if not Input.is_key_pressed(KEY_ESCAPE):
			esc_released_once = true
		return

	# 打开界面那一帧的按键忽略；存档管理界面打开时交给存档界面处理。
	if Engine.get_process_frames() == opened_frame:
		return
	if _has_save_screen_open():
		return

	# 三重检测：暂停动作、逻辑键码、物理键码，任一命中即退出暂停。
	var pressed := Input.is_action_just_pressed("pause") or Input.is_key_pressed(KEY_ESCAPE) or Input.is_physical_key_pressed(KEY_ESCAPE)
	if pressed:
		_resume_game()


func _input(event: InputEvent) -> void:
	# 主通道：再次按下暂停键（Escape）时退出暂停界面、恢复游戏。
	if closed:
		return

	# 只关心 ESC 的按下/抬起（逻辑键码或物理键码命中均可）；重复事件与其余按键一律忽略。
	var is_esc := event is InputEventKey and ((event as InputEventKey).keycode == KEY_ESCAPE or (event as InputEventKey).physical_keycode == KEY_ESCAPE)
	if is_esc:
		var key_event := event as InputEventKey
		if not key_event.pressed:
			esc_released_once = true
			return

		# ESC 尚未松开过（打开时一直按住）或打开那一帧的按键：不退出。
		if not esc_released_once or Engine.get_process_frames() == opened_frame:
			return

		# 存档管理界面打开时交给存档界面处理。
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
	var save_screen := SAVE_SCREEN_SCENE.instantiate() as SaveScreen
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
	# 恢复游戏运行并销毁暂停界面；多通道可能重复触发，用 closed 标志保证只执行一次。
	if closed:
		return
	closed = true
	print("[PauseScreen] ESC 解除暂停，恢复游戏")
	get_tree().paused = false
	queue_free()
