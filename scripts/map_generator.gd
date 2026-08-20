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
# 地点点击区域上限：建筑纹理很大且相邻建筑密集，
# 交互 Button 若按纹理全尺寸覆盖会互相重叠，导致点击命中错误的地点，
# 因此命中区域按纹理缩小（BUTTON_TEX_RATIO）并钳制在该上限内
const BUTTON_MAX_SIZE: Vector2 = Vector2(160.0, 130.0)
const BUTTON_TEX_RATIO: float = 0.45
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
# 地点悬停缩放动画：节点 id -> 当前 Tween
var hover_tweens: Dictionary = {}


func _ready() -> void:
	# 获取当前地图场景中的 Camera2D，用来控制镜头 2D 移动
	map_camera = get_node_or_null("Camera2D") as Camera2D

	# 创建一个专门装 event 节点的容器，方便以后重新生成地图时统一清理
	event_container = Node2D.new()
	event_container.name = "EventContainer"
	add_child(event_container)

	# 创建屏幕顶部的暴露度显示
	_create_exposure_ui()

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

	map_camera.position.x = clampf(map_camera.position.x + horizontal_direction * CAMERA_MOVE_SPEED * delta, camera_min_x, camera_max_x)
	map_camera.position.y = clampf(map_camera.position.y + vertical_direction * CAMERA_MOVE_SPEED * delta, camera_min_y, camera_max_y)


func _input(event: InputEvent) -> void:
	# 监听暂停动作（Escape 键），弹出暂停界面
	if event.is_action_pressed("pause") and not get_tree().paused:
		var pause_screen := PAUSE_SCREEN_SCENE.instantiate() as CanvasLayer
		get_tree().current_scene.add_child(pause_screen)

	# 鼠标滚轮缩放地图
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_zoom(ZOOM_STEP)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_zoom(1.0 / ZOOM_STEP)


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

	# 动态挂一个透明 Button 处理交互；命中区域小于纹理，避免相邻建筑点击区重叠
	var button := Button.new()
	button.name = "Button"
	button.flat = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
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
	# 点击命中区域：按纹理尺寸缩小到建筑主体附近，并钳制上限，
	# 避免相邻建筑的透明 Button 互相重叠导致点击命中错误地点
	var tex_size := _get_place_texture_size(place_node)
	var hit_size := tex_size * BUTTON_TEX_RATIO
	return Vector2(minf(hit_size.x, BUTTON_MAX_SIZE.x), minf(hit_size.y, BUTTON_MAX_SIZE.y))


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
	# 玩家实际前往新地点的统一入口：更新位置、暴露度加一、移动 notation 并刷新显示
	if node_id == "" or node_id == current_node_id:
		return

	current_node_id = node_id
	SaveMgr.current_node_id = current_node_id
	SaveMgr.exposure_level += 1
	_move_notation_to(current_node_id)
	_update_clickable_events()
	_refresh_exposure_label()


func _create_exposure_ui() -> void:
	# 在屏幕顶部中央创建暴露度数值标签（CanvasLayer 不跟随地图镜头移动）
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "ExposureUI"
	add_child(ui_layer)

	exposure_label = Label.new()
	exposure_label.name = "ExposureLabel"
	exposure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exposure_label.add_theme_font_size_override("font_size", 28)
	exposure_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	exposure_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	exposure_label.add_theme_constant_override("outline_size", 6)
	# 横向铺满、高度只占顶部一条，使文字水平居中显示
	exposure_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	exposure_label.offset_top = 12.0
	exposure_label.offset_bottom = 52.0
	ui_layer.add_child(exposure_label)

	_refresh_exposure_label()


func _refresh_exposure_label() -> void:
	# 将最新暴露度同步到顶部标签
	if exposure_label != null:
		exposure_label.text = "暴露度：%d" % SaveMgr.exposure_level


func _update_clickable_events() -> void:
	# 刷新所有节点的可点击状态和视觉表现；所有节点始终可见，仅当前节点的邻接节点可点击
	var current_node_data: Dictionary = node_data_by_id.get(current_node_id, {})
	var clickable_node_ids: Array = []
	if current_node_data.has("connections"):
		clickable_node_ids = current_node_data["connections"]

	for node_id in event_nodes.keys():
		var event_node: Node2D = event_nodes[node_id]
		var button: Button = event_node.get_node_or_null("Button") as Button
		var can_click := clickable_node_ids.has(node_id)

		if button != null:
			button.disabled = not can_click

		if node_id == current_node_id:
			event_node.modulate = Color(1.0, 1.0, 0.65, 1.0)   # 当前位置高亮
		elif can_click:
			event_node.modulate = Color(1.0, 1.0, 1.0, 1.0)    # 可点击：正常亮度
		else:
			event_node.modulate = Color(0.45, 0.45, 0.45, 0.65) # 不可点击：暗色

	# 通知重绘，使连线更新为当前节点对应的邻接连线
	queue_redraw()


func _on_event_pressed(node_id: String) -> void:
	# 点击合法 event 后：event 类型节点跳转事件界面，其余直接移动 notation
	var current_node_data: Dictionary = node_data_by_id.get(current_node_id, {})
	var clickable_node_ids: Array = current_node_data.get("connections", [])
	if not clickable_node_ids.has(node_id):
		return

	var target_node: Dictionary = node_data_by_id.get(node_id, {})
	var node_type: String = target_node.get("type", "")

	var is_event_node := node_type == TYPE_SMALL_EVENT or node_type == TYPE_MEDIUM_EVENT or node_type == TYPE_BIG_EVENT

	if is_event_node:
		# 事件类型节点（小型/中型/大型房间）：暂存节点 id，弹出事件界面
		pending_node_id = node_id
		_show_event_screen(node_id)
	else:
		# 起点或终点类型节点：直接前往该地点
		_move_to_node(node_id)


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


func _on_event_screen_dismissed() -> void:
	# 事件界面关闭后：前往之前暂存的节点位置
	active_event_screen = null

	if pending_node_id != "":
		var target_node_id: String = pending_node_id
		pending_node_id = ""
		_move_to_node(target_node_id)


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
