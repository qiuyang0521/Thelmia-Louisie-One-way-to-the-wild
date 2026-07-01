extends Node2D
class_name EventScreen

# ========== 事件界面配置 ==========
# 底部描述面板高度
const DESC_PANEL_HEIGHT: float = 160.0

# 描述面板左右边距
const DESC_PANEL_MARGIN: float = 40.0

# 右侧选项容器宽度
const OPTION_WIDTH: float = 260.0

# 每个选项的高度
const OPTION_HEIGHT: float = 50.0

# 选项之间的垂直间距
const OPTION_SPACING: float = 12.0

# 选项容器距离右边缘的距离
const OPTION_RIGHT_MARGIN: float = 60.0

# 背景半透明遮罩颜色
const OVERLAY_COLOR: Color = Color(0.05, 0.05, 0.1, 0.88)

# 描述面板背景色
const DESC_BG_COLOR: Color = Color(0.1, 0.1, 0.18, 0.92)

# 选项按钮背景色
const OPTION_BG_COLOR: Color = Color(0.15, 0.15, 0.25, 0.9)

# 选项按钮悬停色
const OPTION_HOVER_COLOR: Color = Color(0.25, 0.25, 0.4, 0.95)

# 事件界面关闭时发出信号，通知地图更新玩家位置
signal dismissed

# 事件描述文本标签
var description_label: RichTextLabel

# 四个选项按钮数组
var option_buttons: Array[Button] = []


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

	_build_description_panel(canvas_layer)
	_build_option_buttons(canvas_layer)


func _build_description_panel(parent: CanvasLayer) -> void:
	# 底部描述面板：深色背景 + 白色文字，用来显示当前事件的内容描述
	var desc_panel := ColorRect.new()
	desc_panel.name = "DescPanel"
	desc_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	desc_panel.offset_top = -DESC_PANEL_HEIGHT
	desc_panel.offset_left = DESC_PANEL_MARGIN
	desc_panel.offset_right = -DESC_PANEL_MARGIN
	desc_panel.color = DESC_BG_COLOR
	parent.add_child(desc_panel)

	# 描述文本使用 RichTextLabel，支持 bbcode 格式（加粗、换色等）
	description_label = RichTextLabel.new()
	description_label.name = "DescLabel"
	description_label.bbcode_enabled = true
	description_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	description_label.offset_left = 24.0
	description_label.offset_top = 16.0
	description_label.offset_right = -24.0
	description_label.offset_bottom = -16.0
	description_label.fit_content = false
	description_label.scroll_active = true
	description_label.text = ""
	desc_panel.add_child(description_label)


func _build_option_buttons(parent: CanvasLayer) -> void:
	# 右侧选项容器：垂直排列 4 个按钮，整体居中于屏幕右侧中间
	var options_container := VBoxContainer.new()
	options_container.name = "OptionsContainer"
	options_container.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	options_container.offset_left = -(OPTION_WIDTH + OPTION_RIGHT_MARGIN)
	options_container.offset_right = -OPTION_RIGHT_MARGIN

	# 4 个选项按钮总高度 = 4 * 按钮高度 + 3 * 间距
	var total_height: float = 4.0 * OPTION_HEIGHT + 3.0 * OPTION_SPACING
	options_container.offset_top = -(total_height / 2.0)
	options_container.offset_bottom = total_height / 2.0
	options_container.add_theme_constant_override("separation", int(OPTION_SPACING))
	parent.add_child(options_container)

	# 逐个创建选项按钮并连接到点击回调
	for i in range(4):
		var option_button := Button.new()
		option_button.name = "Option_%d" % i
		option_button.custom_minimum_size = Vector2(OPTION_WIDTH, OPTION_HEIGHT)
		option_button.text = "选项 %d" % (i + 1)
		option_button.pressed.connect(_on_option_pressed.bind(i))
		options_container.add_child(option_button)
		option_buttons.append(option_button)


func show_event(description: String, options: Array = []) -> void:
	# 外部调用来设置事件界面的具体内容
	# description: 事件描述文本，支持 bbcode
	# options: 字符串数组，最多 4 个选项；不足 4 个时隐藏多余按钮
	description_label.text = description

	for i in range(option_buttons.size()):
		if i < options.size():
			option_buttons[i].text = options[i]
			option_buttons[i].visible = true
		else:
			option_buttons[i].visible = false


func _on_option_pressed(option_index: int) -> void:
	# 点击任意选项后，关闭事件界面并通知地图
	print("[EventScreen] 玩家选择了选项 ", option_index + 1)
	dismiss_and_return()


func dismiss_and_return() -> void:
	# 发出关闭信号后从场景树中移除自己
	dismissed.emit()
	queue_free()
