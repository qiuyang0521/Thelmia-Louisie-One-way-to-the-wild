extends Node2D
class_name MapGenerator
# ========== 地图配置（从地图库随机选取） ==========
# 镜头移动配置（2D 平面移动）
const CAMERA_MOVE_SPEED: float = 520.0
# 鼠标滚轮缩放配置
const ZOOM_MIN: float = 0.8
const ZOOM_MAX: float = 2.0
const ZOOM_STEP: float = 1.1
# 地图节点类型
const TYPE_START: String = "start"
const TYPE_SMALL_EVENT: String = "small"
const TYPE_MEDIUM_EVENT: String = "medium"
const TYPE_BIG_EVENT: String = "big"
const TYPE_BOSS: String = "boss"
# 鼠标悬停地点时的放大倍率
const HOVER_SCALE: float = 1.12
# 不可点击地点的灰度化强度：0=原色，1=完全灰度（代替原先的降低不透明度表示）
const UNCLICKABLE_GRAY_AMOUNT: float = 1.0
# 地点点击区域：略小于建筑纹理原图（BUTTON_TEX_RATIO）
const BUTTON_TEX_RATIO: float = 0.9
# 地图绘制资源
const EVENT_SCENE: PackedScene = preload("res://scenes/event.tscn")
const NOTATION_SCENE: PackedScene = preload("res://scenes/notation.tscn")
const EVENT_SCREEN_SCENE: PackedScene = preload("res://scenes/event_screen.tscn")
# 暂停界面资源
const PAUSE_SCREEN_SCENE: PackedScene = preload("res://scenes/pause_screen.tscn")
# 地图库与地图基类（preload 引用，不依赖全局类名缓存）
const MAP_LIBRARY: GDScript = preload("res://scripts/map_library.gd")
const MAP_BASE: GDScript = preload("res://scripts/map_base.gd")
# 路线线条样式
const LINE_COLOR: Color = Color(0.85, 0.85, 0.85, 0.85)
const LINE_WIDTH: float = 3.0
# 骰子指示物绘制参数：每颗骰子占位宽度、形状外接圆半径、描边宽度与配色
const DICE_CELL_WIDTH: float = 44.0
const DICE_SHAPE_RADIUS: float = 15.0
const DICE_SHAPE_OUTLINE_WIDTH: float = 3.0
const DICE_COLOR_AVAILABLE: Color = Color(1.0, 0.9, 0.55, 1.0)
const DICE_COLOR_SPENT: Color = Color(0.6, 0.6, 0.65, 0.6)
# 控制台（左上角调试按钮）布局与配色
const CONSOLE_MARGIN: float = 8.0
const CONSOLE_BUTTON_WIDTH: float = 88.0
const CONSOLE_BUTTON_HEIGHT: float = 36.0
const CONSOLE_PANEL_WIDTH: float = 172.0
const CONSOLE_TIER_BUTTON_HEIGHT: float = 44.0
const CONSOLE_PANEL_PADDING: float = 8.0
const CONSOLE_BG_COLOR: Color = Color(0.08, 0.09, 0.13, 0.95)
# 生成完地图后发出信号，外部 UI 可以监听这个信号来绘制地图
signal map_generated(map_data: Array[Dictionary])
# 当前地图数据，每个元素代表一个节点
var map_data: Array[Dictionary] = []
# 地图节点实例字典：节点 id -> event 场景实例
var event_nodes: Dictionary = {}
# 地图数据索引字典：节点 id -> 节点数据
var node_data_by_id: Dictionary = {}
# 当前 notation 所在节点 id
var current_node_id: String = ""
# event 节点容器
var event_container: Node2D
# 当前玩家位置标记
var notation_node: Node2D
# 当前场景中的地图镜头
var map_camera: Camera2D
# 当前地图实例（从地图库随机选取后加入本场景）
var current_map: MAP_BASE = null
# 镜头可移动范围（2D）
var camera_min_x: float = 0.0
var camera_max_x: float = 0.0
var camera_min_y: float = 0.0
var camera_max_y: float = 0.0
# 当前正在显示的事件界面实例
var active_event_screen: Node2D = null
# 点击事件节点后暂存的节点 id，等事件界面关闭后再移动 notation
var pending_node_id: String = ""
# 屏幕顶部暴露度数值标签
var exposure_label: Label = null
# 屏幕顶部有机物数值标签
var organic_label: Label = null
# 屏幕顶部骰子指示物（自绘多边形，不依赖字体字形）
var dice_indicator: Control = null
# 左上角控制台开关按钮与其下拉面板（用于选择骰子档位 d4/d8/d12）
var console_button: Button = null
var console_panel: ColorRect = null
# 有机物归零后的游戏结束界面是否已弹出
var game_over_shown: bool = false
# 鼠标拖拽移动镜头状态：是否正在拖拽及上一帧鼠标位置（世界坐标）
var is_dragging: bool = false
var last_drag_position: Vector2 = Vector2.ZERO
# 地点悬停缩放动画：节点 id -> 当前 Tween
var hover_tweens: Dictionary = {}
# 不可点击地点共用的灰度化材质（懒加载创建）
var gray_material: ShaderMaterial = null


func _ready() -> void:
	# 获取当前地图场景中的 Camera2D，用来控制镜头 2D 移动
	map_camera = get_node_or_null("Camera2D") as Camera2D

	# 创建一个专门装 event 节点的容器，方便以后重新生成地图时统一清理
	event_container = Node2D.new()
	event_container.name = "EventContainer"
	add_child(event_container)

	# 创建屏幕顶部的状态显示：第一行骰子指示物，第二行暴露度与有机物
	_create_status_ui()

	# 随机从地图库选取地图生成
	generate_map()

	print_map()


func _process(delta: float) -> void:
	if map_camera == null:
		return

	# 使用项目已有的方向输入动作控制镜头 2D 移动
	var horizontal_direction := Input.get_axis("left", "right")
	var vertical_direction := Input.get_axis("up", "down")
	if horizontal_direction == 0.0 and vertical_direction == 0.0:
		return

	map_camera.position.x += horizontal_direction * CAMERA_MOVE_SPEED * delta
	map_camera.position.y += vertical_direction * CAMERA_MOVE_SPEED * delta
	_clamp_camera()


func _input(event: InputEvent) -> void:
	# 监听暂停动作（Escape 键），弹出暂停界面；游戏结束后不再响应暂停
	if event.is_action_pressed("pause") and not get_tree().paused and not game_over_shown:
		var pause_screen := PAUSE_SCREEN_SCENE.instantiate() as CanvasLayer
		get_tree().current_scene.add_child(pause_screen)

	# 鼠标滚轮缩放地图；左键按下/抬起开始/结束拖拽移动镜头；游戏结束后禁用拖拽
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_zoom(ZOOM_STEP)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_zoom(1.0 / ZOOM_STEP)
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and not game_over_shown:
			if mouse_event.pressed:
				is_dragging = true
				last_drag_position = get_global_mouse_position()
			else:
				is_dragging = false


func _unhandled_input(event: InputEvent) -> void:
	# 鼠标拖拽移动镜头：放在未处理输入阶段，避免与地点按钮的点击冲突；
	# 地图内容跟随鼠标移动，因此镜头向鼠标位移的反方向移动（按缩放比例换算）
	if event is InputEventMouseMotion and is_dragging:
		var motion := event as InputEventMouseMotion
		if map_camera != null:
			map_camera.position -= motion.relative / map_camera.zoom
			_clamp_camera()
		last_drag_position = get_global_mouse_position()


func _draw() -> void:
	# 仅绘制当前节点连接到相邻节点的路线（而非全局所有路线）
	if current_node_id == "":
		return

	var current_node_data: Dictionary = node_data_by_id.get(current_node_id, {})
	if current_node_data.is_empty():
		return

	var from_position: Vector2 = current_node_data["position"]
	var connections: Array = current_node_data["connections"]

	for target_node_id in connections:
		var target_node: Dictionary = node_data_by_id.get(target_node_id, {})
		if target_node.has("position"):
			draw_line(from_position, target_node["position"], LINE_COLOR, LINE_WIDTH)


func generate_map() -> void:
	# 从地图库选取地图：存档记录了有效地图索引时恢复该地图，否则随机选取新地图
	var map_index: int = SaveMgr.map_index
	if map_index < 0 or map_index >= MAP_LIBRARY.get_map_count():
		map_index = randi() % MAP_LIBRARY.get_map_count()
	SaveMgr.map_index = map_index

	_clear_current_map()

	# 将选中的地图场景直接实例化加入原地图场景（置于最底层，避免遮住节点与连线）
	current_map = MAP_LIBRARY.get_map_scene(map_index).instantiate() as MAP_BASE
	current_map.z_index = -1
	add_child(current_map)

	_build_map_data()
	_draw_generated_map()
	_update_camera_limits()
	_focus_camera_on_current_node()

	map_generated.emit(map_data)


func _build_map_data() -> void:
	# 将地图场景提供的节点数据平铺进 map_data 并建立索引；连接对展开为双向连接
	map_data.clear()
	node_data_by_id.clear()

	for raw_node in current_map.get_nodes():
		var node: Dictionary = (raw_node as Dictionary).duplicate()
		node["connections"] = []
		map_data.append(node)
		node_data_by_id[node["id"]] = node

	for pair in current_map.get_connections():
		var node_a: String = pair[0]
		var node_b: String = pair[1]
		if node_data_by_id.has(node_a) and node_data_by_id.has(node_b):
			_add_connection(node_data_by_id[node_a], node_b)
			_add_connection(node_data_by_id[node_b], node_a)


func _add_connection(from_node: Dictionary, to_node_id: String) -> void:
	# 避免同一个节点重复连接到同一个目标节点
	var conns: Array = from_node["connections"]
	if not conns.has(to_node_id):
		conns.append(to_node_id)


func get_map_data() -> Array[Dictionary]:
	# 返回当前地图数据，供外部脚本读取
	return map_data


func _update_camera_limits() -> void:
	# 根据地图尺寸与当前缩放计算镜头可移动范围（视野比地图更大时固定在中心），并钳制当前位置
	var map_size: Vector2 = Vector2.ZERO
	if current_map != null:
		map_size = current_map.get_map_size()
	var visible_size := get_viewport().get_visible_rect().size
	if map_camera != null:
		visible_size /= map_camera.zoom

	camera_min_x = -map_size.x * 0.5 + visible_size.x * 0.5
	camera_max_x = map_size.x * 0.5 - visible_size.x * 0.5
	camera_min_y = -map_size.y * 0.5 + visible_size.y * 0.5
	camera_max_y = map_size.y * 0.5 - visible_size.y * 0.5

	if camera_min_x > camera_max_x:
		camera_min_x = 0.0
		camera_max_x = 0.0
	if camera_min_y > camera_max_y:
		camera_min_y = 0.0
		camera_max_y = 0.0

	if map_camera != null:
		map_camera.position.x = clampf(map_camera.position.x, camera_min_x, camera_max_x)
		map_camera.position.y = clampf(map_camera.position.y, camera_min_y, camera_max_y)


func _focus_camera_on_current_node() -> void:
	# 将镜头移动到当前节点位置（生成地图时使用）
	if map_camera == null:
		return

	var focus_data: Dictionary = node_data_by_id.get(current_node_id, {})
	var focus_position: Vector2 = focus_data.get("position", Vector2.ZERO)
	map_camera.position.x = clampf(focus_position.x, camera_min_x, camera_max_x)
	map_camera.position.y = clampf(focus_position.y, camera_min_y, camera_max_y)


func _change_zoom(factor: float) -> void:
	# 按倍率缩放镜头并刷新移动边界
	if map_camera == null:
		return

	var new_zoom := clampf(map_camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	map_camera.zoom = Vector2(new_zoom, new_zoom)
	_update_camera_limits()
	_clamp_camera()


func _clamp_camera() -> void:
	# 将镜头位置钳制在边界内；键盘移动、鼠标拖拽与缩放共用同一套边界，保证最外边缘一致
	if map_camera == null:
		return

	map_camera.position.x = clampf(map_camera.position.x, camera_min_x, camera_max_x)
	map_camera.position.y = clampf(map_camera.position.y, camera_min_y, camera_max_y)


func _draw_generated_map() -> void:
	# 根据 map_data 建立地点交互：优先使用地图场景内的地点节点，缺失时回退内置 event 场景
	if event_container == null:
		return

	var place_nodes: Dictionary = current_map.get_place_nodes()
	for node in map_data:
		if place_nodes.has(node["id"]):
			_bind_place_node(node, place_nodes[node["id"]])
		else:
			_create_event_node(node)

	# 如果有存档记录的上次所在节点且节点存在于当前地图，恢复到该位置；否则从起点开始
	if SaveMgr.current_node_id != "" and node_data_by_id.has(SaveMgr.current_node_id):
		current_node_id = SaveMgr.current_node_id
	else:
		current_node_id = _get_start_node_id()

	_create_notation_node()
	_move_notation_to(current_node_id)
	_update_clickable_events()


func _clear_current_map() -> void:
	# 清理旧地图实例与节点，避免重新选图时重复叠加
	event_nodes.clear()
	hover_tweens.clear()

	if event_container != null:
		for child in event_container.get_children():
			child.queue_free()

	if is_instance_valid(notation_node):
		notation_node.queue_free()

	notation_node = null

	if is_instance_valid(current_map):
		current_map.queue_free()

	current_map = null


func _bind_place_node(node_data: Dictionary, place_node: Node2D) -> void:
	# 地图场景内的地点节点承担视觉表现：注册进 event_nodes 并绑定点击与悬停交互
	var node_id: String = node_data["id"]
	event_nodes[node_id] = place_node

	if place_node is AnimatedSprite2D:
		(place_node as AnimatedSprite2D).play()

	# 动态挂一个完全透明的 Button 处理交互（任何状态均不可见、无边框），尺寸略小于纹理原图
	var button := Button.new()
	button.name = "Button"
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty_style := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(style_name, empty_style)
	var hit_size := _get_place_hit_size(place_node)
	button.offset_left = -hit_size.x * 0.5
	button.offset_top = -hit_size.y * 0.5
	button.offset_right = hit_size.x * 0.5
	button.offset_bottom = hit_size.y * 0.5
	place_node.add_child(button)

	button.pressed.connect(_on_event_pressed.bind(node_id))
	button.mouse_entered.connect(_on_place_hover.bind(node_id, place_node, true))
	button.mouse_exited.connect(_on_place_hover.bind(node_id, place_node, false))


func _get_place_hit_size(place_node: Node2D) -> Vector2:
	# 点击命中区域：按纹理尺寸略缩小，贴近建筑原图大小
	return _get_place_texture_size(place_node) * BUTTON_TEX_RATIO


func _get_place_texture_size(place_node: Node2D) -> Vector2:
	# 取地点纹理尺寸用于确定交互 Button 的范围
	if place_node is AnimatedSprite2D:
		var sprite := place_node as AnimatedSprite2D
		if sprite.sprite_frames != null:
			var tex: Texture2D = sprite.sprite_frames.get_frame_texture("default", 0)
			if tex != null:
				return tex.get_size()
	elif place_node is Sprite2D:
		var sprite2d := place_node as Sprite2D
		if sprite2d.texture != null:
			return sprite2d.texture.get_size()

	return Vector2(68.0, 58.0)


func _on_place_hover(node_id: String, place_node: Node2D, hovered: bool) -> void:
	# 鼠标悬停时地点略微放大，移出时平滑恢复
	var old_tween: Tween = hover_tweens.get(node_id, null)
	if old_tween != null and old_tween.is_valid():
		old_tween.kill()

	var target_scale: float = HOVER_SCALE if hovered else 1.0
	var tween := place_node.create_tween()
	tween.tween_property(place_node, "scale", Vector2(target_scale, target_scale), 0.12)
	hover_tweens[node_id] = tween


func _create_event_node(node_data: Dictionary) -> void:
	# 回退方案：地图场景未提供该地点的节点时，实例化内置 event 场景放到对应位置
	var node_id: String = node_data["id"]
	var event_node := EVENT_SCENE.instantiate() as Node2D
	event_node.name = "Event_%s" % node_id
	event_node.position = node_data["position"]
	event_container.add_child(event_node)
	event_nodes[node_id] = event_node

	if event_node is AnimatedSprite2D:
		(event_node as AnimatedSprite2D).play()

	var button: Button = event_node.get_node_or_null("Button") as Button
	if button != null:
		button.pressed.connect(_on_event_pressed.bind(node_id))


func _create_notation_node() -> void:
	# 实例化 notation 场景，用来表示玩家当前所在节点
	notation_node = NOTATION_SCENE.instantiate() as Node2D
	notation_node.name = "Notation"
	add_child(notation_node)

	if notation_node is AnimatedSprite2D:
		(notation_node as AnimatedSprite2D).play()


func _move_notation_to(node_id: String) -> void:
	# 将 notation 移动到指定 event 节点的位置
	var target_node: Node2D = event_nodes.get(node_id, null)
	if target_node == null or notation_node == null:
		return

	notation_node.position = target_node.position


func _move_to_node(node_id: String) -> void:
	# 玩家实际前往新地点的统一入口：更新位置、暴露度加一、有机物减一、移动 notation 并刷新显示
	if node_id == "" or node_id == current_node_id:
		return

	current_node_id = node_id
	SaveMgr.current_node_id = current_node_id
	SaveMgr.exposure_level += 1
	SaveMgr.organic_level -= 1
	_move_notation_to(current_node_id)
	_update_clickable_events()
	_refresh_exposure_label()
	_refresh_organic_label()

	# 有机物耗尽：弹出游戏结束界面
	if SaveMgr.organic_level <= 0:
		_show_game_over()


func _create_status_ui() -> void:
	# 屏幕顶部状态栏（CanvasLayer 不跟随地图镜头移动）：
	# 第一行居中显示骰子指示物，第二行左右分栏显示暴露度与有机物
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "StatusUI"
	add_child(ui_layer)

	# 第一行：骰子指示物（自绘三角/菱形/五边形，可用为实心、已消耗为空心描边）
	dice_indicator = Control.new()
	dice_indicator.name = "DiceIndicator"
	# 纯展示控件，不拦截鼠标事件，避免吞掉其下方地点的点击
	dice_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dice_indicator.set_anchors_preset(Control.PRESET_TOP_WIDE)
	dice_indicator.offset_top = 8.0
	dice_indicator.offset_bottom = 52.0
	dice_indicator.draw.connect(_on_dice_indicator_draw)
	ui_layer.add_child(dice_indicator)

	# 第二行左半：暴露度
	exposure_label = _create_status_label("ExposureLabel", Color(1.0, 0.95, 0.8))
	exposure_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	exposure_label.anchor_right = 0.5
	exposure_label.offset_top = 52.0
	exposure_label.offset_bottom = 92.0
	ui_layer.add_child(exposure_label)

	# 第二行右半：有机物
	organic_label = _create_status_label("OrganicLabel", Color(0.8, 1.0, 0.85))
	organic_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	organic_label.anchor_left = 0.5
	organic_label.offset_top = 52.0
	organic_label.offset_bottom = 92.0
	ui_layer.add_child(organic_label)

	_build_console(ui_layer)

	_refresh_dice_indicator()
	_refresh_exposure_label()
	_refresh_organic_label()


func _create_status_label(label_name: String, font_color: Color) -> Label:
	# 创建统一样式的顶部状态标签：居中文本、黑色描边、不拦截鼠标
	var label := Label.new()
	label.name = label_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 纯展示标签，不拦截鼠标事件，避免吞掉其下方地点的点击
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", font_color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	return label


func _refresh_dice_indicator() -> void:
	# 请求重绘骰子指示物（具体绘制在 _on_dice_indicator_draw 中完成）
	if dice_indicator != null:
		dice_indicator.queue_redraw()


func _on_dice_indicator_draw() -> void:
	# 自绘骰子：按槽位顺序水平居中排列；可用骰子实心填充，已消耗骰子仅描边（空心）；
	# 形状由档位决定：d4=三角形、d8=菱形、d12=五边形
	if dice_indicator == null:
		return

	var tiers: Array[int] = SaveMgr.dice_tiers
	var count: int = tiers.size()
	if count == 0:
		return

	var total_width: float = count * DICE_CELL_WIDTH
	var start_x: float = (dice_indicator.size.x - total_width) * 0.5 + DICE_CELL_WIDTH * 0.5
	var center_y: float = dice_indicator.size.y * 0.5

	for i in range(count):
		# 档位→边数：d4(0)→3、d8(1)→4、d12(2)→5
		var sides: int = clampi(tiers[i], SaveMgr.DieTier.D4, SaveMgr.DieTier.D12) + 3
		var center := Vector2(start_x + i * DICE_CELL_WIDTH, center_y)
		var points := _regular_polygon_points(center, DICE_SHAPE_RADIUS, sides)

		if i < SaveMgr.dice_spent:
			# 已消耗：仅描边（补回首点闭合轮廓）
			var outline: PackedVector2Array = points.duplicate()
			outline.append(points[0])
			dice_indicator.draw_polyline(outline, DICE_COLOR_SPENT, DICE_SHAPE_OUTLINE_WIDTH, true)
		else:
			# 可用：实心填充
			dice_indicator.draw_colored_polygon(points, DICE_COLOR_AVAILABLE)


func _regular_polygon_points(center: Vector2, radius: float, sides: int) -> PackedVector2Array:
	# 生成正多边形顶点（首个顶点朝正上方），用于绘制骰子形状
	var points := PackedVector2Array()
	for i in range(sides):
		var angle: float = -PI * 0.5 + float(i) * TAU / float(sides)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _refresh_exposure_label() -> void:
	# 将最新暴露度同步到顶部标签
	if exposure_label != null:
		exposure_label.text = "暴露度：%d" % SaveMgr.exposure_level


func _refresh_organic_label() -> void:
	# 将最新有机物数值同步到顶部标签
	if organic_label != null:
		organic_label.text = "有机物：%d" % SaveMgr.organic_level


func _build_console(parent: CanvasLayer) -> void:
	# 左上角控制台：一个开关按钮 + 下拉面板（面板内提供 d4/d8/d12 三档供选择）
	console_button = Button.new()
	console_button.name = "ConsoleButton"
	console_button.text = "控制台"
	console_button.anchor_left = 0.0
	console_button.anchor_top = 0.0
	console_button.anchor_right = 0.0
	console_button.anchor_bottom = 0.0
	console_button.offset_left = CONSOLE_MARGIN
	console_button.offset_top = CONSOLE_MARGIN
	console_button.offset_right = CONSOLE_MARGIN + CONSOLE_BUTTON_WIDTH
	console_button.offset_bottom = CONSOLE_MARGIN + CONSOLE_BUTTON_HEIGHT
	console_button.pressed.connect(_on_console_toggled)
	parent.add_child(console_button)

	# 下拉面板：默认隐藏，点开关按钮后出现
	var panel_top: float = CONSOLE_MARGIN + CONSOLE_BUTTON_HEIGHT + CONSOLE_MARGIN
	var panel_height: float = 3.0 * CONSOLE_TIER_BUTTON_HEIGHT + 2.0 * CONSOLE_PANEL_PADDING + 2.0 * CONSOLE_PANEL_PADDING
	console_panel = ColorRect.new()
	console_panel.name = "ConsolePanel"
	console_panel.color = CONSOLE_BG_COLOR
	console_panel.anchor_left = 0.0
	console_panel.anchor_top = 0.0
	console_panel.anchor_right = 0.0
	console_panel.anchor_bottom = 0.0
	console_panel.offset_left = CONSOLE_MARGIN
	console_panel.offset_top = panel_top
	console_panel.offset_right = CONSOLE_MARGIN + CONSOLE_PANEL_WIDTH
	console_panel.offset_bottom = panel_top + panel_height
	console_panel.visible = false
	parent.add_child(console_panel)

	var tier_box := VBoxContainer.new()
	tier_box.name = "TierBox"
	tier_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	tier_box.offset_left = CONSOLE_PANEL_PADDING
	tier_box.offset_top = CONSOLE_PANEL_PADDING
	tier_box.offset_right = -CONSOLE_PANEL_PADDING
	tier_box.offset_bottom = -CONSOLE_PANEL_PADDING
	tier_box.add_theme_constant_override("separation", int(CONSOLE_PANEL_PADDING))
	console_panel.add_child(tier_box)

	# 三个档位按钮：4 / 8 / 12 面
	for tier in range(3):
		var tier_button := Button.new()
		tier_button.name = "Tier_%d" % tier
		tier_button.custom_minimum_size = Vector2(0.0, CONSOLE_TIER_BUTTON_HEIGHT)
		tier_button.text = "d%d（%d 面）" % [SaveMgr.DIE_FACES[tier], SaveMgr.DIE_FACES[tier]]
		tier_button.pressed.connect(_on_console_tier_pressed.bind(tier))
		tier_box.add_child(tier_button)


func _on_console_toggled() -> void:
	# 开关控制台面板
	if console_panel != null:
		console_panel.visible = not console_panel.visible


func _on_console_tier_pressed(tier: int) -> void:
	# 控制台选择骰子档位：将所有骰子设为所选面数，刷新指示物并收起面板
	SaveMgr.set_all_dice_tier(tier)
	_refresh_dice_indicator()
	if console_panel != null:
		console_panel.visible = false
	print("[MapGenerator] 控制台：骰子已全部设为 d%d" % SaveMgr.DIE_FACES[tier])


func _show_game_over() -> void:
	# 有机物归零：弹出全屏游戏结束界面，提供返回标题按钮
	if game_over_shown:
		return
	game_over_shown = true

	var overlay := CanvasLayer.new()
	overlay.name = "GameOverUI"
	overlay.layer = 100
	add_child(overlay)

	# 半透明黑色遮罩覆盖全屏，拦截所有鼠标点击
	var background := ColorRect.new()
	background.color = Color(0.0, 0.0, 0.0, 0.75)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(background)

	# 居中容器：结束标题 + 返回标题按钮
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 32)
	overlay.add_child(box)

	var title := Label.new()
	title.text = "游戏结束"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.9, 0.25, 0.25))
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "有机物已耗尽，你们的旅程到此为止……"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 24)
	hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	box.add_child(hint)

	var back_button := Button.new()
	back_button.text = "返回标题"
	back_button.custom_minimum_size = Vector2(220.0, 56.0)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(_on_game_over_back_pressed)
	box.add_child(back_button)


func _on_game_over_back_pressed() -> void:
	# 游戏结束后返回标题画面：重置运行时状态并切换场景
	SaveMgr.reset_state()
	get_tree().change_scene_to_file("res://scenes/start_screen.tscn")


func _update_clickable_events() -> void:
	# 刷新所有节点的可点击状态和视觉表现；所有节点始终可见，仅当前节点的邻接节点可点击
	var current_node_data: Dictionary = node_data_by_id.get(current_node_id, {})
	var clickable_node_ids: Array = []
	if current_node_data.has("connections"):
		clickable_node_ids = current_node_data["connections"]

	for node_id in event_nodes.keys():
		var event_node: Node2D = event_nodes[node_id]
		var button: Button = event_node.get_node_or_null("Button") as Button
		# 当前位置若是事件类型地点，也可点击以重新进入事件选择界面（不发生移动）
		var node_type: String = node_data_by_id.get(node_id, {}).get("type", "")
		var is_current_event: bool = (node_id == current_node_id) and _is_event_type(node_type)
		var can_click: bool = clickable_node_ids.has(node_id) or is_current_event

		if button != null:
			button.disabled = not can_click

		if node_id == current_node_id:
			event_node.modulate = Color(1.0, 1.0, 0.65, 1.0)   # 当前位置高亮
			event_node.material = null
		elif can_click:
			event_node.modulate = Color(1.0, 1.0, 1.0, 1.0)    # 可点击：正常亮度
			event_node.material = null
		else:
			event_node.modulate = Color(1.0, 1.0, 1.0, 1.0)    # 不可点击：保持不透明
			event_node.material = _get_gray_material()         # 改用提升灰度值表示

	# 通知重绘，使连线更新为当前节点对应的邻接连线
	queue_redraw()


func _get_gray_material() -> ShaderMaterial:
	# 懒加载创建所有不可点击地点共用的灰度化材质
	# 按亮度权重（Rec.601）去饱和，amount 控制灰度强度
	if gray_material == null:
		var shader := Shader.new()
		shader.code = """shader_type canvas_item;
uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	float gray = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(tex_color.rgb, vec3(gray), amount), tex_color.a);
}
"""
		gray_material = ShaderMaterial.new()
		gray_material.shader = shader
		gray_material.set_shader_parameter("amount", UNCLICKABLE_GRAY_AMOUNT)
	return gray_material


func _on_event_pressed(node_id: String) -> void:
	# 点击合法 event 后：event 类型节点跳转事件界面，其余直接移动 notation
	if node_id == current_node_id:
		# 点击当前位置：事件类型地点可再次进入事件选择界面；
		# 仅重新打开界面，不算移动，不消耗有机物、不增加暴露度
		if _is_event_type(node_data_by_id.get(node_id, {}).get("type", "")):
			pending_node_id = ""
			_show_event_screen(node_id)
		return

	var current_node_data: Dictionary = node_data_by_id.get(current_node_id, {})
	var clickable_node_ids: Array = current_node_data.get("connections", [])
	if not clickable_node_ids.has(node_id):
		return

	var target_node: Dictionary = node_data_by_id.get(node_id, {})
	var node_type: String = target_node.get("type", "")

	if _is_event_type(node_type):
		# 事件类型节点（小型/中型/大型房间与 Boss 点）：暂存节点 id，弹出事件界面
		pending_node_id = node_id
		_show_event_screen(node_id)
	else:
		# 起点类型节点：直接前往该地点
		_move_to_node(node_id)


func _is_event_type(node_type: String) -> bool:
	# 判断节点类型是否会触发事件选择界面
	return node_type == TYPE_SMALL_EVENT or node_type == TYPE_MEDIUM_EVENT or node_type == TYPE_BIG_EVENT or node_type == TYPE_BOSS


func _show_event_screen(node_id: String) -> void:
	# 实例化事件界面并叠加到地图场景上
	if active_event_screen != null:
		active_event_screen.queue_free()

	active_event_screen = EVENT_SCREEN_SCENE.instantiate()
	get_tree().current_scene.add_child(active_event_screen)

	# 监听事件界面关闭信号，回到地图后更新玩家位置
	active_event_screen.dismissed.connect(_on_event_screen_dismissed)

	# 填入示例事件内容和选项（后续可替换为真实事件数据）
	var event_screen := active_event_screen as EventScreen
	if event_screen != null:
		event_screen.show_event(
			"你在荒野中发现了一处遗迹，残破的石门上刻着奇怪的符文……",
			["探索遗迹", "搜索周围", "查看背包", "继续前进"]
		)


func _on_event_screen_dismissed(option_index: int, roll_info: Dictionary) -> void:
	# 事件界面关闭后：
	# - 选择普通选项（option_index >= 0）：骰子已在事件界面内消耗并掷出，
	#   此处用回传的 roll_info 结算事件并刷新骰子指示物；
	# - 选择退回地图（option_index == -1）：不算行动、不消耗骰子；
	# 随后前往暂存的节点位置
	active_event_screen = null

	if option_index >= 0:
		_refresh_dice_indicator()
		_resolve_event_outcome(option_index, roll_info)

	if pending_node_id != "":
		var target_node_id: String = pending_node_id
		pending_node_id = ""
		_move_to_node(target_node_id)


func _resolve_event_outcome(option_index: int, roll_info: Dictionary) -> void:
	# 事件结算入口：根据所选选项与掷骰结果影响事件走向。
	# roll_info 形如 {"tier": 档位, "roll": 点数, "result": 1-5}；无骰可用时为空字典。
	# 说明：当前事件为占位内容，尚未接入按 result 分支的真实效果；
	# 后续可在本函数内依据 result(1-5) 展开事件结算（成功/失败/收益等）。
	if roll_info.is_empty():
		print("[MapGenerator] 无可用骰子，选项 %d 未触发掷骰" % (option_index + 1))
		return

	var faces: int = SaveMgr.DIE_FACES[roll_info["tier"]]
	print("[MapGenerator] 选项 %d 掷骰：d%d 掷出 %d → 结果 %d" % [
		option_index + 1, faces, roll_info["roll"], roll_info["result"]
	])


func _get_start_node_id() -> String:
	# 查找类型为 start 的节点作为起点；没有时退回第一个节点
	for node in map_data:
		if node["type"] == TYPE_START:
			return node["id"]

	if map_data.is_empty():
		return ""

	return map_data[0]["id"]


func print_map() -> void:
	# 在输出面板打印地图结构，方便先确认布局
	for node in map_data:
		print("节点: ", node["id"], " 类型: ", node["type"], " 位置: ", node["position"], " 连接到: ", node["connections"])
