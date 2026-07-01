extends TileMapLayer

# ========== 地块滚动配置 ==========
# 地块向左移动的速度（像素/秒），数值越大移动越快
const SCROLL_SPEED: float = 80.0

# 在原地块右侧额外复制几份，用来形成连续地图
const EXTRA_COPY_COUNT: int = 1

# 地图初始位置
var start_position: Vector2

# 一整段地图的宽度，用来判断何时循环回右侧
var map_width: float = 0.0


func _ready() -> void:
	# 记录地块刚进入场景时的位置，后续循环时会以这个位置为基准
	start_position = position

	# 先计算原始地块宽度，再在右侧复制一份相同地块
	map_width = _get_map_width()
	_copy_map_to_right()


func _process(delta: float) -> void:
	# 如果没有正确计算出地图宽度，就不执行滚动逻辑
	if map_width <= 0.0:
		return

	# 每一帧都让地块整体向左移动
	position.x -= SCROLL_SPEED * delta

	# 当原始地块完整移到左侧后，把整组地块向右补回一个地图宽度
	if position.x <= start_position.x - map_width:
		position.x += map_width


func _get_map_width() -> float:
	# 通过 TileMapLayer 实际使用的格子范围，计算整段地块的宽度
	var used_rect: Rect2i = get_used_rect()
	if tile_set == null or used_rect.size.x <= 0:
		return 0.0

	return used_rect.size.x * tile_set.tile_size.x * abs(scale.x)


func _copy_map_to_right() -> void:
	# 把当前已经绘制好的地块格子复制到右侧，形成一段连续地图
	var used_rect: Rect2i = get_used_rect()
	if used_rect.size.x <= 0:
		return

	var used_cells: Array[Vector2i] = get_used_cells()
	for copy_index in range(1, EXTRA_COPY_COUNT + 1):
		for cell_position in used_cells:
			var source_id: int = get_cell_source_id(cell_position)
			var atlas_coords: Vector2i = get_cell_atlas_coords(cell_position)
			var alternative_tile: int = get_cell_alternative_tile(cell_position)
			var new_cell_position := Vector2i(cell_position.x + used_rect.size.x * copy_index, cell_position.y)

			set_cell(new_cell_position, source_id, atlas_coords, alternative_tile)
