extends CharacterBody2D

# ========== 车道配置 ==========
# 三条车道的 Y 坐标（从上到下），可以根据实际道路位置调整
const LANE_TOP: float = -40.0      # 最上车道 Y 坐标
const LANE_MIDDLE: float = -8.0     # 中间车道 Y 坐标
const LANE_BOTTOM: float = 24.0    # 最下车道 Y 坐标

# 换行时的移动速度（像素/秒），数值越大换行越快
const LANE_SWITCH_SPEED: float = 100.0

# 汽车左右移动速度（像素/秒），数值越大左右移动越快
const HORIZONTAL_SPEED: float = 120.0

# 当前所在车道索引：0=上, 1=中, 2=下
var current_lane: int = 1

# 三条车道 Y 坐标数组，方便通过索引访问
var lane_positions: Array[float] = [LANE_TOP, LANE_MIDDLE, LANE_BOTTOM]

# 当前目标 Y 坐标
var target_y: float = LANE_MIDDLE


func _ready() -> void:
	# 初始化时，将车辆放到中间车道
	position.y = LANE_MIDDLE
	target_y = LANE_MIDDLE


func _process(delta: float) -> void:

	# ---------- 处理换行输入 ----------
	# 按下 up 动作：向上换一行（车道索引减小）
	if Input.is_action_just_pressed("up"):
		if current_lane > 0:
			current_lane -= 1
			target_y = lane_positions[current_lane]

	# 按下 down 动作：向下换一行（车道索引增大）
	if Input.is_action_just_pressed("down"):
		if current_lane < 2:
			current_lane += 1
			target_y = lane_positions[current_lane]

	# ---------- 处理左右移动输入 ----------
	# 使用 left 和 right 两个动作控制汽车在 X 轴上左右移动
	var horizontal_direction := Input.get_axis("left", "right")
	position.x += horizontal_direction * HORIZONTAL_SPEED * delta

	# ---------- 平滑移动到目标车道 ----------
	# 使用 move_toward 让 Y 坐标平滑过渡到目标值
	position.y = move_toward(position.y, target_y, LANE_SWITCH_SPEED * delta)
