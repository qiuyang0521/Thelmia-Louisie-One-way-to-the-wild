extends Node

# ========== 画面拉伸守卫 ==========
# 游戏画面以 1920x1080（16:9）为设计分辨率：
# 窗口可任意拉伸为任何尺寸与比例，画面自动适应窗口内 16:9 比例下的最大显示区域
# （等比缩放，窗口比例不匹配时其余区域留黑边），不再强制修改窗口大小。
# 配置以代码强制生效（等价于 project.godot 的 stretch 设置），
# 防止配置文件丢失或被破坏时内容被非等比拉伸，导致画面变形与鼠标错位。

const BASE_WIDTH: int = 1920
const BASE_HEIGHT: int = 1080


func _ready() -> void:
	var window := get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_size = Vector2i(BASE_WIDTH, BASE_HEIGHT)
