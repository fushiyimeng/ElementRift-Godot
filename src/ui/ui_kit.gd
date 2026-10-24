class_name UiKit
extends RefCounted
## 界面通用控件工厂 —— 替代 renderer.py 里手画的 _button / _title / _gold_text
##
## 各菜单界面共用这些函数，保证按钮样式、字号、配色一致。
## 全部走 Godot 原生 Control + 主题覆盖，不再手算像素绘制。

const FONT_NORMAL := 26
const FONT_SMALL := 17
const FONT_TITLE := 52
const FONT_CARD := 20


## 通用按钮（含悬停/按下/禁用三态样式）。
static func button(text: String, size: Vector2 = Vector2(260, 56),
		font_size: int = FONT_NORMAL) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.size = size
	b.focus_mode = Control.FOCUS_NONE      # 避免空格/回车误触发聚焦按钮
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Config.COLOR_BUTTON_TEXT)
	_apply_button_styles(b, Config.COLOR_BUTTON, Config.COLOR_BUTTON_HOVER)
	return b


## 把按钮换成指定的底色（用于「确定」这类需要颜色区分的按钮）。
static func recolor_button(b: Button, bg: Color) -> void:
	_apply_button_styles(b, bg, bg.lightened(0.15))


static func _apply_button_styles(b: Button, bg: Color, hover: Color) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var color := bg
		if state == "hover" or state == "pressed":
			color = hover
		elif state == "disabled":
			color = Config.COLOR_BUTTON_DISABLED
		var sb := StyleBoxFlat.new()
		sb.bg_color = color
		sb.set_corner_radius_all(8)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## 纯文字标签。
static func label(text: String, font_size: int = FONT_NORMAL,
		color: Color = Config.COLOR_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## 水平居中的大标题。
static func title(text: String, font_size: int = FONT_TITLE) -> Label:
	var l := label(text, font_size, Config.COLOR_TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_right = 1.0
	l.offset_top = 60.0
	l.offset_bottom = 60.0 + font_size * 1.4
	return l


## 半透明遮罩（用于暂停/结算等覆盖层）。
static func dim(alpha: float = 0.6) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0, 0, 0, alpha)
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c


## 一个带底色的行容器（用于升级列表这类条目）。
static func row_panel(size: Vector2 = Vector2(1040, 90)) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Config.COLOR_BUTTON
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	return p


## 通用滑块（音量/音效/帧率）。
static func slider(min_value: float, max_value: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_value
	s.max_value = max_value
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(400, 24)
	s.focus_mode = Control.FOCUS_NONE
	return s
