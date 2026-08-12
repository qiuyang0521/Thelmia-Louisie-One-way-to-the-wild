extends Node2D
class_name MapGenerator
# ========== 地图配置（固定布局，从上向下排列） ==========
# 地图总层数（7 层纵向排列，起点在顶部，Boss 在底部）
const LAYER_COUNT: int = 7
# 层与层之间的纵向间距
const NODE_Y_SPACING: float = 160.0
# 镜头纵向移动配置
const CAMERA_MOVE_SPEED: float = 260.0
const CAMERA_TOP_PADDING: float = 120.0
const CAMERA_BOTTOM_PADDING: float = 120.0
# 地图节点类型
const TYPE_START: String = "start"
const TYPE_SMALL_EVENT: String = "small"
const TYPE_MEDIUM_EVENT: String = "medium"
const TYPE_BIG_EVENT: String = "big"
const TYPE_BOSS: String = "boss"
# 各类型对应的地图节点纹理
const TEX_SMALL: Texture2D = preload("res://assets/Charactor/small.png")
const TEX_MEDIUM: Texture2D = preload("res://assets/Charactor/midium.png")
const TEX_BIG: Texture2D = preload("res://assets/Charactor/big.png")
# 地图绘制资源
const EVENT_SCENE: PackedScene = preload("res://scenes/event.tscn")
const NOTATION_SCENE: PackedScene = preload("res://scenes/notation.tscn")
const EVENT_SCREEN_SCENE: PackedScene = preload("res://scenes/event_screen.tscn")
# 暂停界面资源
const PAUSE_SCREEN_SCENE: PackedScene = preload("res://scenes/pause_screen.tscn")
# 路线线条样式
const LINE_COLOR: Color = Color(0.85, 0.85, 0.85, 0.85)
const LINE_WIDTH: float = 3.0
# 生成完地图后发出信号，外部 UI 可以监听这个信号来绘制地图
signal map_generated(map_data: Array[Dictionary])
# 当前地图数据，每个元素代表一层
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
# 镜头可移动的纵向范围
var camera_min_y: float = 0.0
var camera_max_y: float = 0.0
# 当前正在显示的事件界面实例
var active_event_screen: Node2D = null
# 点击事件节点后暂存的节点 id，等事件界面关闭后再移动 notation
var pending_node_id: String = ""


func _ready() -> void:
	# 获取当前地图场景中的 Camera2D，用来控制镜头左右移动
	map_camera = get_node_or_null("Camera2D") as Camera2D

	# 创建一个专门装 event 节点的容器，方便以后重新生成地图时统一清理
	event_container = Node2D.new()
	event_container.name = "EventContainer"
	add_child(event_container)

	# 固定地图直接生成，不再依赖随机种子
	generate_map()

	print_map()


func _process(delta: float) -> void:
	if map_camera == null:
		return

	# 使用项目已有的 up/down 输入动作控制镜头纵向移动
	var vertical_direction := Input.get_axis("up", "down")
	if vertical_direction == 0.0:
		return

	map_camera.position.y += vertical_direction * CAMERA_MOVE_SPEED * delta
	map_camera.position.y = clampf(map_camera.position.y, camera_min_y, camera_max_y)


func _input(event: InputEvent) -> void:
	# 监听暂停动作（Escape 键），弹出暂停界面
	if event.is_action_pressed("pause") and not get_tree().paused:
		var pause_screen := PAUSE_SCREEN_SCENE.instantiate() as CanvasLayer
		get_tree().current_scene.add_child(pause_screen)


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
	# 使用固定地图布局，不再随机生成
	map_data.clear()
	_build_fixed_map()
	_build_node_data_index()
	_update_camera_limits()
	_draw_generated_map()

	map_generated.emit(map_data)


func _build_fixed_map() -> void:
	# 构建固定地图数据 —— 7 层纵向排列（从上向下），节点位置、类型和连接关系全部硬编码
	# 每层定义：[节点数量, [各节点 X 坐标], [各节点类型]]
	var layer_defs: Array = [
		{"count": 1, "xs": [0.0],             "types": [TYPE_START]},
		{"count": 3, "xs": [-135.0, 0.0, 135.0], "types": [TYPE_SMALL_EVENT, TYPE_MEDIUM_EVENT, TYPE_SMALL_EVENT]},
		{"count": 2, "xs": [-65.0, 65.0],      "types": [TYPE_SMALL_EVENT, TYPE_MEDIUM_EVENT]},
		{"count": 3, "xs": [-135.0, 0.0, 135.0], "types": [TYPE_BIG_EVENT, TYPE_BIG_EVENT, TYPE_BIG_EVENT]},
		{"count": 3, "xs": [-135.0, 0.0, 135.0], "types": [TYPE_SMALL_EVENT, TYPE_MEDIUM_EVENT, TYPE_SMALL_EVENT]},
		{"count": 2, "xs": [-65.0, 65.0],      "types": [TYPE_SMALL_EVENT, TYPE_MEDIUM_EVENT]},
		{"count": 1, "xs": [0.0],             "types": [TYPE_BOSS]},
	]

	for layer_index in range(layer_defs.size()):
		var def: Dictionary = layer_defs[layer_index]
		var nodes: Array[Dictionary] = []

		for node_index in range(def["count"]):
			var node_id := "%s_%s" % [layer_index, node_index]
			var node := {
				"id": node_id,
				"layer": layer_index,
				"index": node_index,
				"type": def["types"][node_index],
				"position": Vector2(def["xs"][node_index], layer_index * NODE_Y_SPACING),
				"connections": []
			}
			nodes.append(node)

		map_data.append({"layer": layer_index, "nodes": nodes})

	# 连接关系：[从层索引][从节点索引] = [目标节点索引数组]
	# 所有连接采用非交叉原则，每节点至少有一个入口和一个出口
	var connections: Array[Array] = [
		[[0, 1, 2]],              # Layer 0→1: 起点连接全部三个
		[[0], [0, 1], [1]],       # Layer 1→2
		[[0, 1], [1, 2]],         # Layer 2→3
		[[0, 1], [1], [1, 2]],   # Layer 3→4
		[[0], [0, 1], [1]],       # Layer 4→5
		[[0], [0]],               # Layer 5→6: 两条路线汇聚到 Boss
	]

	for layer_from in range(connections.size()):
		var from_nodes: Array = map_data[layer_from]["nodes"]
		var to_nodes: Array = map_data[layer_from + 1]["nodes"]
		var layer_conns: Array = connections[layer_from]

		for from_idx in range(layer_conns.size()):
			var from_node: Dictionary = from_nodes[from_idx]
			for to_idx in layer_conns[from_idx]:
				var to_node: Dictionary = to_nodes[to_idx]
				# 正向连接（向下推进）
				_add_connection(from_node, to_node["id"])
				# 反向连接（允许回头）
				_add_connection(to_node, from_node["id"])


func _add_connection(from_node: Dictionary, to_node_id: String) -> void:
	# 避免同一个节点重复连接到同一个目标节点
	var conns: Array = from_node["connections"]
	if not conns.has(to_node_id):
		conns.append(to_node_id)


func get_map_data() -> Array[Dictionary]:
	# 返回当前地图数据，供外部脚本读取
	return map_data


func _build_node_data_index() -> void:
	# 建立节点 id 索引，后续绘制连线、判断点击是否合法都会用到
	node_data_by_id.clear()
	for layer_data in map_data:
		var nodes: Array = layer_data["nodes"]
		for node in nodes:
			node_data_by_id[node["id"]] = node


func _update_camera_limits() -> void:
	# 根据纵向地图高度计算镜头上下边界，并把镜头放回起点附近
	camera_min_y = -CAMERA_TOP_PADDING
	camera_max_y = float(LAYER_COUNT - 1) * NODE_Y_SPACING + CAMERA_BOTTOM_PADDING

	if map_camera != null:
		map_camera.position.y = clampf(0.0, camera_min_y, camera_max_y)


func _draw_generated_map() -> void:
	# 根据 map_data 实例化 event 节点，并把 notation 放在起点
	if event_container == null:
		return

	_clear_drawn_map()

	for layer_data in map_data:
		var nodes: Array = layer_data["nodes"]
		for node in nodes:
			_create_event_node(node)

	# 如果有存档记录的上次所在节点且节点存在于当前地图，恢复到该位置；否则从起点开始
	if SaveMgr.current_node_id != "" and node_data_by_id.has(SaveMgr.current_node_id):
		current_node_id = SaveMgr.current_node_id
	else:
		current_node_id = _get_start_node_id()

	_create_notation_node()
	_move_notation_to(current_node_id)
	_update_clickable_events()


func _clear_drawn_map() -> void:
	# 清理旧地图节点，避免重新生成地图时重复叠加
	event_nodes.clear()

	for child in event_container.get_children():
		child.queue_free()

	if is_instance_valid(notation_node):
		notation_node.queue_free()

	notation_node = null


func _create_event_node(node_data: Dictionary) -> void:
	# 实例化一个 event 场景，并把它放到对应地图节点的位置
	var node_id: String = node_data["id"]
	var node_type: String = node_data.get("type", "")
	var event_node := EVENT_SCENE.instantiate() as Node2D
	event_node.name = "Event_%s" % node_id
	event_node.position = node_data["position"]
	event_container.add_child(event_node)
	event_nodes[node_id] = event_node

	# 根据节点类型替换对应纹理
	if event_node is AnimatedSprite2D:
		var sprite := event_node as AnimatedSprite2D
		var tex := _get_texture_for_type(node_type)
		var frames := SpriteFrames.new()
		frames.add_frame("default", tex)
		frames.set_animation_loop("default", true)
		frames.set_animation_speed("default", 5.0)
		sprite.sprite_frames = frames
		sprite.play()

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
		# 起点或终点类型节点：直接移动 notation
		current_node_id = node_id
		SaveMgr.current_node_id = current_node_id
		_move_notation_to(current_node_id)
		_update_clickable_events()


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
	# 事件界面关闭后：移动 notation 到之前暂存的节点位置，并刷新可点击状态
	active_event_screen = null

	if pending_node_id != "":
		current_node_id = pending_node_id
		pending_node_id = ""
		SaveMgr.current_node_id = current_node_id

	_move_notation_to(current_node_id)
	_update_clickable_events()


func _get_start_node_id() -> String:
	# 起始点固定是第 1 层第 1 个节点
	if map_data.is_empty():
		return ""

	var first_layer_nodes: Array = map_data[0]["nodes"]
	if first_layer_nodes.is_empty():
		return ""

	return first_layer_nodes[0]["id"]


func _get_texture_for_type(node_type: String) -> Texture2D:
	# 根据节点类型返回对应的纹理资源
	match node_type:
		TYPE_SMALL_EVENT:
			return TEX_SMALL
		TYPE_MEDIUM_EVENT:
			return TEX_MEDIUM
		TYPE_BIG_EVENT:
			return TEX_BIG
		_:
			return TEX_SMALL


func print_map() -> void:
	# 在输出面板打印地图结构，方便先确认布局
	for layer_data in map_data:
		print("第", layer_data["layer"] + 1, "层")

		for node in layer_data["nodes"]:
			print("  节点: ", node["id"], " 类型: ", node["type"], " 连接到: ", node["connections"])
