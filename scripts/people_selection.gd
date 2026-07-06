extends Node2D
class_name PeopleSelection

# 引用存档管理器脚本
const SaveMgr = preload("res://scripts/save_manager.gd")

# ========== 角色资源配置 ==========
# 头部纹理列表 —— 展示所有可选头部供玩家挑选
const HEAD_TEXTURES: Array[String] = [
	"res://assets/Charactor/thyme.png",
	"res://assets/Charactor/robot.png",
	"res://assets/Charactor/event.png",
]

# 身体纹理列表 —— 系统会从中随机抽取 3 个供玩家选择
const BODY_TEXTURES: Array[String] = [
	"res://assets/Charactor/chomper.png",
]

# ========== UI 场景模板 ==========
const HEAD_OPTION_SCENE: PackedScene = preload("res://scenes/head_option.tscn")
const PERSON_OPTION_SCENE: PackedScene = preload("res://scenes/person_option.tscn")

# ========== 布局常量 ==========
# 头部选项水平间距（屏幕像素）
const HEAD_SPACING: float = 280.0
# 身体选项水平间距（屏幕像素）
const BODY_SPACING: float = 320.0
# 选项垂直方向相对于屏幕中心的偏移（正数=向下）
const OPTION_Y_OFFSET: float = 40.0
# 头部选项可选择时的缩放（正常大小）
const OPTION_SCALE_NORMAL: float = 1.0
# 非选择状态下的缩放（暗色提示）
const OPTION_SCALE_DIM: float = 0.9

# ========== 状态管理 ==========
enum Phase { HEAD_SELECTION, BODY_SELECTION, COMPLETE }
var current_phase: Phase = Phase.HEAD_SELECTION
var selected_head_index: int = -1
var selected_body_index: int = -1

# ========== UI 节点引用 ==========
var ui_layer: CanvasLayer
var title_label: Label
var instruction_label: Label
var head_container: Node2D
var body_container: Node2D


func _ready() -> void:
	_build_ui()
	_show_head_selection()


# ==================== UI 构建 ====================

func _build_ui() -> void:
	# 创建 CanvasLayer —— 放置标题和提示文字，使其不受 Camera2D 移动影响
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	add_child(ui_layer)

	# 全屏半透明深色背景，突出选择界面但又让下方的角色选项可见
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.06, 0.1, 0.75)
	# 关键：设置鼠标穿透，让点击事件能传递到背景下方的按钮
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(bg)

	# 顶部标题 —— 显示当前步骤名称（"选择角色头部" / "选择角色身体"）
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title_label.offset_top = 30.0
	title_label.offset_bottom = 75.0
	title_label.offset_left = -300.0
	title_label.offset_right = 300.0
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 36)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	ui_layer.add_child(title_label)

	# 底部提示文字 —— 引导玩家操作
	instruction_label = Label.new()
	instruction_label.name = "InstructionLabel"
	instruction_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	instruction_label.offset_top = -50.0
	instruction_label.offset_left = -400.0
	instruction_label.offset_right = 400.0
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 18)
	instruction_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7, 1.0))
	ui_layer.add_child(instruction_label)

	# 头部选项容器 —— 放入 CanvasLayer，确保渲染在最顶层
	head_container = Node2D.new()
	head_container.name = "HeadContainer"
	ui_layer.add_child(head_container)

	# 身体选项容器 —— 同样放入 CanvasLayer 最顶层
	body_container = Node2D.new()
	body_container.name = "BodyContainer"
	ui_layer.add_child(body_container)


# ==================== 阶段一：头部选择 ====================

func _show_head_selection() -> void:
	# 切换到头部选择阶段
	current_phase = Phase.HEAD_SELECTION
	title_label.text = "选择角色头部"
	instruction_label.text = "点击下方头像，选择一个你喜欢的头部"

	# 清空旧的头部选项，避免重复叠加
	for child in head_container.get_children():
		child.queue_free()
	body_container.visible = false

	# 以屏幕中心为基准，计算选项在 CanvasLayer 中的坐标（屏幕像素）
	var screen_center := get_viewport().get_visible_rect().size / 2.0
	var total_width := float(HEAD_TEXTURES.size() - 1) * HEAD_SPACING
	var start_x := screen_center.x - total_width / 2.0

	for i in range(HEAD_TEXTURES.size()):
		var head_option := HEAD_OPTION_SCENE.instantiate() as Node2D
		head_option.position = Vector2(start_x + float(i) * HEAD_SPACING, screen_center.y + OPTION_Y_OFFSET)
		head_container.add_child(head_option)

		# 将头部纹理设置到 AnimatedSprite2D 上
		var texture := load(HEAD_TEXTURES[i]) as Texture2D
		var sprite: AnimatedSprite2D = head_option.get_node_or_null("AnimatedSprite2D")
		if sprite != null and texture != null:
			_replace_sprite_texture(sprite, texture)

		# 连接按钮点击信号，绑定头部索引
		var button: Button = head_option.get_node_or_null("Button")
		if button != null:
			button.pressed.connect(_on_head_selected.bind(i))


func _on_head_selected(head_index: int) -> void:
	# 防止重复点击或非当前阶段的回调
	if current_phase != Phase.HEAD_SELECTION:
		return

	selected_head_index = head_index
	print("[PeopleSelection] 玩家选择了头部: ", HEAD_TEXTURES[head_index].get_file())

	_show_body_selection()


# ==================== 阶段二：身体选择 ====================

func _show_body_selection() -> void:
	# 切换到身体选择阶段
	current_phase = Phase.BODY_SELECTION
	title_label.text = "选择角色身体"
	instruction_label.text = "选择一具身体（3选1）"

	# 隐藏头部容器，显示身体容器
	head_container.visible = false
	for child in body_container.get_children():
		child.queue_free()
	body_container.visible = true

	# 从身体纹理列表中随机抽取 3 个（不足时允许重复）
	var selected_body_indices: Array[int] = _pick_random_bodies(3)
	var screen_center := get_viewport().get_visible_rect().size / 2.0
	var start_x := screen_center.x - BODY_SPACING

	for i in range(selected_body_indices.size()):
		var body_option := PERSON_OPTION_SCENE.instantiate() as Node2D
		body_option.position = Vector2(start_x + float(i) * BODY_SPACING, screen_center.y + OPTION_Y_OFFSET)
		body_container.add_child(body_option)

		# 设置身体纹理
		var body_index: int = selected_body_indices[i]
		var texture := load(BODY_TEXTURES[body_index]) as Texture2D
		var sprite: AnimatedSprite2D = body_option.get_node_or_null("AnimatedSprite2D")
		if sprite != null and texture != null:
			_replace_sprite_texture(sprite, texture)

		# 连接按钮
		var button: Button = body_option.get_node_or_null("Button")
		if button != null:
			button.pressed.connect(_on_body_selected.bind(body_index))


func _pick_random_bodies(count: int) -> Array[int]:
	# 从身体纹理列表中随机挑选指定数量的索引
	# 如果可用身体数量不足 count，允许重复使用
	var available: Array[int] = []
	for i in range(BODY_TEXTURES.size()):
		available.append(i)

	if available.size() <= count:
		# 可用数量不足：先全部加入，再随机补充至 count 个
		while available.size() < count:
			available.append(randi() % BODY_TEXTURES.size())
		return available.slice(0, count)

	# Fisher-Yates 洗牌后取前 count 个，确保不重复
	available.shuffle()
	return available.slice(0, count)


func _on_body_selected(body_index: int) -> void:
	# 防止重复点击或非当前阶段的回调
	if current_phase != Phase.BODY_SELECTION:
		return

	selected_body_index = body_index
	current_phase = Phase.COMPLETE

	print("[PeopleSelection] 玩家选择了身体: ", BODY_TEXTURES[body_index].get_file())
	print("[PeopleSelection] 最终选择 —— 头: %d, 身体: %d" % [selected_head_index, selected_body_index])

	_on_selection_complete()


# ==================== 工具函数 ====================

func _replace_sprite_texture(sprite: AnimatedSprite2D, texture: Texture2D) -> void:
	# 用指定纹理替换 AnimatedSprite2D 的 sprite_frames 中的默认动画帧
	# 创建新的 SpriteFrames 资源，避免影响场景模板中的共享资源
	var frames := SpriteFrames.new()
	frames.add_frame("default", texture)
	sprite.sprite_frames = frames
	sprite.play("default")


# ==================== 选择完成 ====================

func _on_selection_complete() -> void:
	# 将角色选择结果存入 SaveManager，供存档和游戏内使用
	SaveMgr.head_index = selected_head_index
	SaveMgr.body_index = selected_body_index

	# 简短延迟后切换到主游戏场景，给玩家一个视觉反馈
	await get_tree().create_timer(0.4).timeout
	get_tree().change_scene_to_file("res://scenes/map.tscn")
