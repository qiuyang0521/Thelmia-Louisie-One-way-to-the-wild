extends Node2D
class_name MapGenerator

# ========== 地图生成配置 ==========
# 地图总层数：这里只生成 6 层，类似《杀戮尖塔》的横向路线地图
const LAYER_COUNT: int = 7

# 中间层最少和最多生成多少个节点；第一层和最后一层固定只有 1 个节点
const MIN_NODES_PER_LAYER: int = 2
const MAX_NODES_PER_LAYER: int = 4

# 节点之间的横向间距；横向表示层与层之间的距离
const NODE_X_SPACING: float = 160.0

# 同一层节点的固定上下边界；多节点层会在这两个位置之间均匀排布
const NODE_TOP_Y: float = -135.0
const NODE_BOTTOM_Y: float = 135.0
const NODE_CENTER_Y: float = 0.0

# 当某一层恰好只有 2 个节点时，这两个节点围绕中心上下浮动的距离
const TWO_NODE_OFFSET: float = 65.0

# 如果生成的地图节点数量分布不满足规则，最多允许重新生成的次数
const MAX_REGENERATION_ATTEMPTS: int = 20

# 镜头横向移动配置
const CAMERA_MOVE_SPEED: float = 260.0
const CAMERA_LEFT_PADDING: float = 120.0
const CAMERA_RIGHT_PADDING: float = 120.0

# 地图节点类型
const TYPE_START: String = "start"
const TYPE_EVENT: String = "event"
const TYPE_BOSS: String = "boss"

# 地图绘制资源
const EVENT_SCENE: PackedScene = preload("res://scenes/event.tscn")
const NOTATION_SCENE: PackedScene = preload("res://scenes/notation.tscn")

# 路线线条样式
const LINE_COLOR: Color = Color(0.85, 0.85, 0.85, 0.85)
const LINE_WIDTH: float = 3.0

# 生成完地图后发出信号，外部 UI 可以监听这个信号来绘制地图
signal map_generated(map_data: Array[Dictionary])

# 随机数工具
var rng := RandomNumberGenerator.new()

# 当前生成出的地图数据，每个元素代表一层
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

# 镜头可移动的横向范围
var camera_min_x: float = 0.0
var camera_max_x: float = 0.0


func _ready() -> void:
	# 获取当前地图场景中的 Camera2D，用来控制镜头左右移动
	map_camera = get_node_or_null("Camera2D") as Camera2D

	# 创建一个专门装 event 节点的容器，方便以后重新生成地图时统一清理
	event_container = Node2D.new()
	event_container.name = "EventContainer"
	add_child(event_container)

	# 如果你把这个脚本挂到场景节点上，运行时会自动生成并绘制一次地图
	generate_map()
	print_map()


func _process(delta: float) -> void:
	if map_camera == null:
		return

	# 使用项目已有的 left/right 输入动作控制镜头横向移动
	var horizontal_direction := Input.get_axis("left", "right")
	if horizontal_direction == 0.0:
		return

	map_camera.position.x += horizontal_direction * CAMERA_MOVE_SPEED * delta
	map_camera.position.x = clampf(map_camera.position.x, camera_min_x, camera_max_x)


func _draw() -> void:
	# 绘制所有节点之间的路线；因为是父节点绘制，所以线会显示在 event 节点后方
	for layer_data in map_data:
		var nodes: Array = layer_data["nodes"]
		for node in nodes:
			var from_position: Vector2 = node["position"]
			var connections: Array = node["connections"]

			for target_node_id in connections:
				var target_node: Dictionary = node_data_by_id.get(target_node_id, {})
				if target_node.has("position"):
					draw_line(from_position, target_node["position"], LINE_COLOR, LINE_WIDTH)


func generate_map(seed_value: int = 0) -> Array[Dictionary]:
	# 传入 0 表示每次随机；传入固定数字可以得到固定地图，方便调试
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value

	map_data.clear()
	_create_layers_with_validation()
	_create_paths()
	_ensure_all_nodes_connected()
	_assign_node_types()
	_build_node_data_index()
	_update_camera_limits()
	_draw_generated_map()

	map_generated.emit(map_data)
	return map_data


func _create_layers_with_validation() -> void:
	# 先随机每层节点数量，如果不符合‘不允许连续两层都是 2 个或都是 4 个’的规则，就整体重新生成
	var layer_node_counts: Array[int] = []
	var attempts: int = 0

	while attempts < MAX_REGENERATION_ATTEMPTS:
		attempts += 1
		layer_node_counts.clear()

		for layer_index in range(LAYER_COUNT):
			layer_node_counts.append(_get_node_count_for_layer(layer_index))

		if _has_valid_node_count_distribution(layer_node_counts):
			break

	for layer_index in range(LAYER_COUNT):
		_create_layer(layer_index, layer_node_counts[layer_index])


func _create_layer(layer_index: int, node_count: int) -> void:
	# 按给定的节点数量生成单层节点数据并加入 map_data
	var nodes: Array[Dictionary] = []

	for node_index in range(node_count):
		var node_id := "%s_%s" % [layer_index, node_index]
		var x := layer_index * NODE_X_SPACING
		var y := _get_node_y_position(node_index, node_count)

		var node := {
			"id": node_id,
			"layer": layer_index,
			"index": node_index,
			"type": TYPE_EVENT,
			"position": Vector2(x, y),
			"connections": []
		}
		nodes.append(node)

	map_data.append({
		"layer": layer_index,
		"nodes": nodes
	})


func _has_valid_node_count_distribution(layer_node_counts: Array[int]) -> bool:
	# 只检查中间层；如果出现连续两层都是 2 个或都是 4 个节点，或者连续三层都是 3 个节点，就视为无效分布
	for layer_index in range(1, layer_node_counts.size() - 1):
		var current_count: int = layer_node_counts[layer_index]
		var previous_count: int = layer_node_counts[layer_index - 1]

		if current_count == 2 and previous_count == 2:
			return false

		if current_count == 4 and previous_count == 4:
			return false

		if (
			current_count == 3
			and previous_count == 3
			and layer_index >= 2
			and layer_node_counts[layer_index - 2] == 3
		):
			return false

	return true


func get_map_data() -> Array[Dictionary]:
	# 返回当前地图数据，供外部脚本读取
	return map_data


func _get_node_y_position(node_index: int, node_count: int) -> float:
	# 单节点层放在中间；2 节点层在中心上下各浮动固定距离；更多节点时上下边界固定，中间等距分布
	if node_count <= 1:
		return NODE_CENTER_Y

	if node_count == 2:
		return NODE_CENTER_Y - TWO_NODE_OFFSET + float(node_index) * (TWO_NODE_OFFSET * 2.0)

	var ratio := float(node_index) / float(node_count - 1)
	return lerpf(NODE_TOP_Y, NODE_BOTTOM_Y, ratio)


func _get_node_count_for_layer(layer_index: int) -> int:
	# 第一层作为起点、最后一层作为终点，都固定只有 1 个节点
	if layer_index == 0 or layer_index == LAYER_COUNT - 1:
		return 1

	return rng.randi_range(MIN_NODES_PER_LAYER, MAX_NODES_PER_LAYER)


func _create_paths() -> void:
	# 按节点顺序连接相邻层，保证横置地图中的路线不会上下交叉
	for layer_index in range(LAYER_COUNT - 1):
		var current_nodes: Array = map_data[layer_index]["nodes"]
		var next_nodes: Array = map_data[layer_index + 1]["nodes"]
		_create_non_crossing_layer_connections(current_nodes, next_nodes)


func _create_non_crossing_layer_connections(current_nodes: Array, next_nodes: Array) -> void:
	# 先清空本层旧连接，再按顺序重新建立非交叉连接
	for current_node in current_nodes:
		var connections: Array = current_node["connections"]
		connections.clear()

	if current_nodes.is_empty() or next_nodes.is_empty():
		return

	# 每个当前层节点至少连接到下一层中顺序对应的节点
	for current_index in range(current_nodes.size()):
		var next_index := _map_ordered_index(current_index, current_nodes.size(), next_nodes.size())
		var current_node: Dictionary = current_nodes[current_index]
		var next_node: Dictionary = next_nodes[next_index]
		_add_connection(current_node, next_node["id"])

	# 每个下一层节点也至少拥有一个来自上一层的入口，仍然按顺序分配，避免交叉
	for next_index in range(next_nodes.size()):
		var previous_index := _map_ordered_index(next_index, next_nodes.size(), current_nodes.size())
		var previous_node: Dictionary = current_nodes[previous_index]
		var next_node: Dictionary = next_nodes[next_index]
		_add_connection(previous_node, next_node["id"])


func _map_ordered_index(source_index: int, source_count: int, target_count: int) -> int:
	# 把一个有序节点序号映射到另一层的有序节点序号，不加入随机偏移，防止路线交叉
	if target_count <= 1 or source_count <= 1:
		return 0

	var normalized_position := float(source_index) / float(source_count - 1)
	return clampi(int(round(normalized_position * float(target_count - 1))), 0, target_count - 1)


func _ensure_all_nodes_connected() -> void:
	# 非交叉连接生成时已经同时保证了出口和入口，这里保留函数方便生成流程阅读
	return


func _add_connection(from_node: Dictionary, to_node_id: String) -> void:
	# 避免同一个节点重复连接到同一个目标节点
	var connections: Array = from_node["connections"]
	if not connections.has(to_node_id):
		connections.append(to_node_id)


func _assign_node_types() -> void:
	# 给节点分配房间类型：起点固定 start，终点固定 boss，中间层全部固定为 event
	for layer_data in map_data:
		var layer_index: int = layer_data["layer"]
		var nodes: Array = layer_data["nodes"]

		for node in nodes:
			if layer_index == 0:
				node["type"] = TYPE_START
			elif layer_index == LAYER_COUNT - 1:
				node["type"] = TYPE_BOSS
			else:
				node["type"] = TYPE_EVENT


func _build_node_data_index() -> void:
	# 建立节点 id 索引，后续绘制连线、判断点击是否合法都会用到
	node_data_by_id.clear()
	for layer_data in map_data:
		var nodes: Array = layer_data["nodes"]
		for node in nodes:
			node_data_by_id[node["id"]] = node


func _update_camera_limits() -> void:
	# 根据横置地图宽度计算镜头左右边界，并把镜头放回起点附近
	camera_min_x = -CAMERA_LEFT_PADDING
	camera_max_x = float(LAYER_COUNT - 1) * NODE_X_SPACING + CAMERA_RIGHT_PADDING

	if map_camera != null:
		map_camera.position.x = clampf(0.0, camera_min_x, camera_max_x)


func _draw_generated_map() -> void:
	# 根据 map_data 实例化 event 节点，并把 notation 放在起点
	if event_container == null:
		return

	_clear_drawn_map()
	queue_redraw()

	for layer_data in map_data:
		var nodes: Array = layer_data["nodes"]
		for node in nodes:
			_create_event_node(node)

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


func _update_clickable_events() -> void:
	# 只有当前节点 connections 中记录的下一个节点可以点击，其余 event 全部禁用
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
			event_node.modulate = Color(1.0, 1.0, 0.65, 1.0)
		elif can_click:
			event_node.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			event_node.modulate = Color(0.45, 0.45, 0.45, 0.65)


func _on_event_pressed(node_id: String) -> void:
	# 点击合法 event 后，移动 notation，并刷新下一批可点击节点
	var current_node_data: Dictionary = node_data_by_id.get(current_node_id, {})
	var clickable_node_ids: Array = current_node_data.get("connections", [])
	if not clickable_node_ids.has(node_id):
		return

	current_node_id = node_id
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


func print_map() -> void:
	# 在输出面板打印地图结构，方便先确认生成结果
	for layer_data in map_data:
		print("第", layer_data["layer"] + 1, "层")

		for node in layer_data["nodes"]:
			print("  节点: ", node["id"], " 类型: ", node["type"], " 连接到: ", node["connections"])
