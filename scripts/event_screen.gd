extends Node2D
class_name EventScreen

# ========== 事件界面配置 ==========
# 四周留白边距
const SCREEN_MARGIN: float = 40.0
# 事件页面顶部留白：需避开地图顶部资源栏（骰子/暴露度/有机物，约占 0~92px），
# 否则资源栏会遮挡剧情栏顶部
const EVENT_TOP_MARGIN: float = 100.0
# 左侧图像区与右侧页面之间的半间距（两列之间实际留白 = 2 * COLUMN_GAP）
const COLUMN_GAP: float = 14.0
# 左侧图像区右边界所占屏宽比例（右侧页面从此处开始）
const IMAGE_ANCHOR_RIGHT: float = 0.54
# 右侧页面内边距
const PAGE_PADDING: float = 24.0
# 文本区与底部嵌入区（选项/结果）之间的垂直间距
const RIGHT_SECTION_SPACING: float = 16.0
# 底部嵌入区预留高度（容纳最多 4 选项 + 退回按钮，保证文本区高度稳定不跳动）
const BOTTOM_SLOT_HEIGHT: float = 290.0
# 每个选项横条的高度
const OPTION_HEIGHT: float = 44.0
# 嵌入页面的选项横条宽度（居中显示，参考图样式）
const OPTION_BAR_WIDTH: float = 320.0
# 选项之间的垂直间距
const OPTION_SPACING: float = 10.0
# 普通选项与“退回地图”按钮之间的额外间距
const BACK_BUTTON_EXTRA_GAP: float = 10.0
# 结果区骰面尺寸
const RESULT_DIE_SIZE: float = 90.0
# 逐字显示速度（字符/秒）
const TYPEWRITER_CHARS_PER_SECOND: float = 28.0
# 逐字显示最短时长（文本很短时也保留一点停顿）
const TYPEWRITER_MIN_DURATION: float = 0.25
# 背景半透明遮罩颜色
const OVERLAY_COLOR: Color = Color(0.05, 0.05, 0.1, 0.88)
# 左侧图像预留区背景色与边框色
const IMAGE_BG_COLOR: Color = Color(0.08, 0.08, 0.14, 0.9)
const IMAGE_BORDER_COLOR: Color = Color(0.45, 0.5, 0.65, 0.7)
# 右侧页面背景色
const PAGE_BG_COLOR: Color = Color(0.07, 0.08, 0.12, 0.94)
# 嵌入页面的选项横条配色（参考图的强调色横条）
const OPTION_BAR_COLOR: Color = Color(0.86, 0.2, 0.42, 1.0)
const OPTION_BAR_HOVER_COLOR: Color = Color(0.95, 0.32, 0.55, 1.0)
# 退回地图横条配色（弱化，与消耗骰子的选项区分）
const BACK_BAR_COLOR: Color = Color(0.16, 0.18, 0.26, 0.9)
const BACK_BAR_HOVER_COLOR: Color = Color(0.24, 0.27, 0.38, 0.95)
# 结果区骰面配色（亮色骰面 + 深色点数）
const RESULT_DIE_COLOR: Color = Color(0.95, 0.78, 0.25, 1.0)
const RESULT_DIE_NUMBER_COLOR: Color = Color(0.12, 0.1, 0.05, 1.0)

# 事件界面关闭时发出信号：option_index 为选中的选项索引，roll_info 为该次掷骰结果；
# option_index 为 -1 表示玩家选择了“退回地图”（不算行动、不消耗骰子，roll_info 为空）
signal dismissed(option_index: int, roll_info: Dictionary)

# 左侧图像预留区（后续可在此面板内挂接事件插图 TextureRect）
var image_panel: Panel = null
# 右侧页面（剧情文本与嵌入选项/结果的容器）
var right_page: ColorRect = null
# 剧情文本标签（逐字显示）
var description_label: RichTextLabel = null
# 页面底部嵌入区（选项与结果共用，预留高度避免文本跳动）
var bottom_slot: Control = null
# 嵌入页面的选项容器（逐字显示完成后再出现）
var options_container: VBoxContainer = null
# 四个选项按钮数组
var option_buttons: Array[Button] = []
# 退回地图按钮（不消耗骰子）
var back_to_map_button: Button = null
# 结果容器（选完选项后出现：骰面 + 点数/结果文字 + 确认按钮）
var result_container: VBoxContainer = null
# 结果区骰面（自绘档位形状）与其上的点数标签
var result_die: Control = null
var result_die_number: Label = null
# 结果说明文字（告知玩家骰子点数与事件结果）
var result_text: Label = null
# 结果确认按钮
var result_confirm: Button = null
# 当前结果对应的骰子档位（供骰面绘制）
var result_tier: int = 0
# 暂存本次选择与掷骰结果，待玩家确认后随 dismissed 信号回传地图
var _pending_option: int = -1
var _pending_roll: Dictionary = {}
# 当前逐字显示动画（用于重入时终止上一段）
var typewriter_tween: Tween = null


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# 用 CanvasLayer 保证 UI 始终覆盖在游戏世界之上，不受 Camera2D 移动影响
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "UILayer"
	add_child(canvas_layer)

	# 全屏半透明遮罩，让地图画面变暗，突出事件界面
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = OVERLAY_COLOR
	canvas_layer.add_child(overlay)

	# 左列：图像预留区；右列：整页（剧情文本 + 嵌入的选项/结果）
	_build_image_panel(canvas_layer)
	_build_right_page(canvas_layer)


func _build_image_panel(parent: CanvasLayer) -> void:
	# 左侧图像预留窗口：带边框的深色面板，暂不放置图像，仅预留位置
	image_panel = Panel.new()
	image_panel.name = "ImagePanel"
	image_panel.anchor_left = 0.0
	image_panel.anchor_top = 0.0
	image_panel.anchor_right = IMAGE_ANCHOR_RIGHT
	image_panel.anchor_bottom = 1.0
	image_panel.offset_left = SCREEN_MARGIN
	image_panel.offset_top = EVENT_TOP_MARGIN
	image_panel.offset_right = -COLUMN_GAP
	image_panel.offset_bottom = -SCREEN_MARGIN

	var style := StyleBoxFlat.new()
	style.bg_color = IMAGE_BG_COLOR
	style.border_color = IMAGE_BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	image_panel.add_theme_stylebox_override("panel", style)
	parent.add_child(image_panel)

	# 居中淡色提示文字，标明此处为图像预留区（后续接入插图后可移除）
	var hint := Label.new()
	hint.name = "ImageHint"
	hint.text = "图像预留区"
	hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.16))
	image_panel.add_child(hint)


func _build_right_page(parent: CanvasLayer) -> void:
	# 右侧整页：深色页面背景，内部自上而下为剧情文本与底部嵌入区（选项/结果）
	right_page = ColorRect.new()
	right_page.name = "RightPage"
	right_page.color = PAGE_BG_COLOR
	right_page.anchor_left = IMAGE_ANCHOR_RIGHT
	right_page.anchor_top = 0.0
	right_page.anchor_right = 1.0
	right_page.anchor_bottom = 1.0
	right_page.offset_left = COLUMN_GAP
	right_page.offset_top = EVENT_TOP_MARGIN
	right_page.offset_right = -SCREEN_MARGIN
	right_page.offset_bottom = -SCREEN_MARGIN
	parent.add_child(right_page)

	var page_box := VBoxContainer.new()
	page_box.name = "PageBox"
	page_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	page_box.offset_left = PAGE_PADDING
	page_box.offset_top = PAGE_PADDING
	page_box.offset_right = -PAGE_PADDING
	page_box.offset_bottom = -PAGE_PADDING
	page_box.add_theme_constant_override("separation", int(RIGHT_SECTION_SPACING))
	right_page.add_child(page_box)

	_build_text_area(page_box)
	_build_bottom_slot(page_box)


func _build_text_area(parent: Control) -> void:
	# 剧情文本：直接铺在页面上（支持 bbcode，逐字显示），占据底部嵌入区以外的空间
	description_label = RichTextLabel.new()
	description_label.name = "DescLabel"
	description_label.bbcode_enabled = true
	description_label.fit_content = false
	description_label.scroll_active = true
	description_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	description_label.add_theme_font_size_override("normal_font_size", 22)
	description_label.add_theme_color_override("default_color", Color(0.95, 0.95, 0.95))
	description_label.text = ""
	description_label.visible_ratio = 0.0
	parent.add_child(description_label)


func _build_bottom_slot(parent: Control) -> void:
	# 页面底部嵌入区：预留固定高度，选项与结果在此切换显示，保证文本区高度稳定
	bottom_slot = Control.new()
	bottom_slot.name = "BottomSlot"
	bottom_slot.custom_minimum_size = Vector2(0.0, BOTTOM_SLOT_HEIGHT)
	parent.add_child(bottom_slot)

	_build_option_buttons(bottom_slot)
	_build_result_panel(bottom_slot)


func _build_option_buttons(parent: Control) -> void:
	# 嵌入页面的选项横条：垂直排列 4 个选项 + “退回地图”；
	# 初始隐藏，待剧情文本逐字显示完成后再出现
	options_container = VBoxContainer.new()
	options_container.name = "OptionsContainer"
	options_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	options_container.add_theme_constant_override("separation", int(OPTION_SPACING))
	options_container.visible = false
	parent.add_child(options_container)

	# 逐个创建选项横条并连接到点击回调
	for i in range(4):
		var option_button := Button.new()
		option_button.name = "Option_%d" % i
		option_button.custom_minimum_size = Vector2(OPTION_BAR_WIDTH, OPTION_HEIGHT)
		option_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		option_button.text = "选项 %d" % (i + 1)
		_style_as_bar(option_button, OPTION_BAR_COLOR, OPTION_BAR_HOVER_COLOR)
		option_button.pressed.connect(_on_option_pressed.bind(i))
		options_container.add_child(option_button)
		option_buttons.append(option_button)

	# 退回地图按钮：额外加一段间距与普通选项分隔，点击后直接回到地图
	# 不算一次行动，不消耗骰子（但仍会正常执行移动结算）
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, BACK_BUTTON_EXTRA_GAP)
	options_container.add_child(spacer)

	back_to_map_button = Button.new()
	back_to_map_button.name = "BackToMapButton"
	back_to_map_button.custom_minimum_size = Vector2(OPTION_BAR_WIDTH, OPTION_HEIGHT)
	back_to_map_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_to_map_button.text = "退回地图"
	_style_as_bar(back_to_map_button, BACK_BAR_COLOR, BACK_BAR_HOVER_COLOR)
	back_to_map_button.add_theme_color_override("font_color", Color(0.65, 0.8, 0.95))
	back_to_map_button.add_theme_color_override("font_hover_color", Color(0.65, 0.8, 0.95))
	back_to_map_button.pressed.connect(_on_back_to_map_pressed)
	options_container.add_child(back_to_map_button)


func _build_result_panel(parent: Control) -> void:
	# 结果区：选完选项后出现，展示骰面点数与事件结果，确认后关闭界面
	result_container = VBoxContainer.new()
	result_container.name = "ResultContainer"
	result_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_container.alignment = BoxContainer.ALIGNMENT_CENTER
	result_container.add_theme_constant_override("separation", 12)
	result_container.visible = false
	parent.add_child(result_container)

	# 骰面：自绘档位形状（三角/菱形/五边形），中心显示掷出的点数
	result_die = Control.new()
	result_die.name = "ResultDie"
	result_die.custom_minimum_size = Vector2(RESULT_DIE_SIZE, RESULT_DIE_SIZE)
	result_die.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result_die.draw.connect(_on_result_die_draw)
	result_container.add_child(result_die)

	result_die_number = Label.new()
	result_die_number.name = "ResultDieNumber"
	result_die_number.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_die_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_die_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_die_number.add_theme_font_size_override("font_size", 36)
	result_die_number.add_theme_color_override("font_color", RESULT_DIE_NUMBER_COLOR)
	result_die.add_child(result_die_number)

	# 结果说明：告知玩家骰子点数与事件结果
	result_text = Label.new()
	result_text.name = "ResultText"
	result_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_text.add_theme_font_size_override("font_size", 22)
	result_text.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	result_container.add_child(result_text)

	# 确认按钮：关闭事件界面并把选择与掷骰结果回传地图
	result_confirm = Button.new()
	result_confirm.name = "ResultConfirm"
	result_confirm.custom_minimum_size = Vector2(240.0, 46.0)
	result_confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result_confirm.text = "继续"
	_style_as_bar(result_confirm, OPTION_BAR_COLOR, OPTION_BAR_HOVER_COLOR)
	result_confirm.pressed.connect(_on_result_confirm_pressed)
	result_container.add_child(result_confirm)


func _style_as_bar(button: Button, base_color: Color, hover_color: Color) -> void:
	# 将按钮样式化为嵌入页面的扁平横条（参考图样式）
	var normal := StyleBoxFlat.new()
	normal.bg_color = base_color
	normal.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = hover_color
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)


func show_event(description: String, options: Array = []) -> void:
	# 外部调用来设置事件界面的具体内容
	# description: 事件描述文本，支持 bbcode，将以逐字方式显示
	# options: 字符串数组，最多 4 个选项；不足 4 个时隐藏多余按钮
	description_label.text = description

	# 先配置好各选项文本与可见性，但选项与结果容器都保持隐藏，待逐字显示完成后再出现选项
	for i in range(option_buttons.size()):
		if i < options.size():
			option_buttons[i].text = options[i]
			option_buttons[i].visible = true
		else:
			option_buttons[i].visible = false

	if options_container != null:
		options_container.visible = false
	if result_container != null:
		result_container.visible = false

	_start_typewriter()


func _start_typewriter() -> void:
	# 逐字显示剧情文本：按字符数估算时长，用 Tween 将 visible_ratio 从 0 过渡到 1，
	# 完成后回调显示选项
	if typewriter_tween != null and typewriter_tween.is_valid():
		typewriter_tween.kill()

	description_label.visible_ratio = 0.0
	var total_chars: int = description_label.get_total_character_count()
	var duration: float = maxf(float(total_chars) / TYPEWRITER_CHARS_PER_SECOND, TYPEWRITER_MIN_DURATION)

	typewriter_tween = create_tween()
	typewriter_tween.tween_property(description_label, "visible_ratio", 1.0, duration)
	typewriter_tween.tween_callback(_reveal_options)


func _reveal_options() -> void:
	# 剧情文本逐字显示完毕：显示嵌入页面的选项横条
	typewriter_tween = null
	if options_container != null:
		options_container.visible = true


func _on_option_pressed(option_index: int) -> void:
	# 点击普通选项：在本界面内消耗一个骰子并掷骰，先展示点数与事件结果，
	# 待玩家点击“继续”确认后才关闭界面并回传地图结算
	print("[EventScreen] 玩家选择了选项 ", option_index + 1)

	_pending_option = option_index
	_pending_roll = SaveMgr.consume_and_roll()

	if options_container != null:
		options_container.visible = false
	_show_result(_pending_roll)


func _show_result(roll_info: Dictionary) -> void:
	# 在结果区展示骰面点数与事件结果
	if roll_info.is_empty():
		# 无可用骰子：不掷骰，仅提示
		if result_die != null:
			result_die.visible = false
		result_text.text = "没有可用骰子，本次行动未掷骰。"
	else:
		result_tier = roll_info["tier"]
		if result_die != null:
			result_die.visible = true
			result_die.queue_redraw()
		if result_die_number != null:
			result_die_number.text = str(roll_info["roll"])
		var faces: int = SaveMgr.DIE_FACES[roll_info["tier"]]
		result_text.text = "骰子点数：%d（d%d）　事件结果：%d" % [
			roll_info["roll"], faces, roll_info["result"]
		]

	if result_container != null:
		result_container.visible = true


func _on_result_die_draw() -> void:
	# 自绘结果骰面：按档位画三角/菱形/五边形并填充，点数由中心标签显示
	if result_die == null:
		return

	var sides: int = clampi(result_tier, 0, 2) + 3
	var center := result_die.size * 0.5
	var radius: float = minf(result_die.size.x, result_die.size.y) * 0.5 - 4.0
	var points := _regular_polygon_points(center, radius, sides)
	result_die.draw_colored_polygon(points, RESULT_DIE_COLOR)


func _regular_polygon_points(center: Vector2, radius: float, sides: int) -> PackedVector2Array:
	# 生成正多边形顶点（首个顶点朝正上方），用于绘制骰面形状
	var points := PackedVector2Array()
	for i in range(sides):
		var angle: float = -PI * 0.5 + float(i) * TAU / float(sides)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _on_result_confirm_pressed() -> void:
	# 玩家确认结果：关闭事件界面并把选择与掷骰结果回传地图
	print("[EventScreen] 玩家确认结果，返回地图")
	dismiss_and_return(_pending_option, _pending_roll)


func _on_back_to_map_pressed() -> void:
	# 点击退回地图：不算行动、不消耗骰子，仅关闭事件界面
	print("[EventScreen] 玩家选择退回地图")
	dismiss_and_return(-1, {})


func dismiss_and_return(option_index: int = -1, roll_info: Dictionary = {}) -> void:
	# 发出关闭信号（携带选项索引与掷骰结果）后从场景树中移除自己
	dismissed.emit(option_index, roll_info)
	queue_free()
