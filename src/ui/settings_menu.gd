class_name SettingsMenu
extends Control
## 设置界面 —— 移植自 main.py 的 draw_settings / click_settings
##
## 音量、音效、帧率、分辨率、全屏。
## 所有修改先落在 main 持有的「草稿」上，点保存才写盘（对应 Python 版的 _settings_draft）。

var main: Main = null
var _built := false

## 各行左侧标签的统一宽度（"音乐音量" 这类四字标签在 26px 字号下约 104px）
const LABEL_W := 140.0

var _volume: HSlider
var _sfx: HSlider
var _ui: HSlider
var _fps: HSlider
var _fps_box: SpinBox
var _resolution_btns: Array = []     ## [[Vector2i 尺寸, Button], ...]
var _window_mode_btns: Array = []    ## [[String 模式, Button], ...]


func setup(p_main: Main) -> void:
	main = p_main
	if _built:
		return
	_built = true
	_build()


func _build() -> void:
	add_child(UiKit.title("设置"))

	var grid := VBoxContainer.new()
	grid.name = "Form"
	grid.anchor_left = 0.5
	grid.anchor_right = 0.5
	grid.offset_left = -400.0
	grid.offset_right = 400.0
	grid.offset_top = 170.0
	grid.add_theme_constant_override("separation", 24)
	add_child(grid)

	# 三档音量：背景音乐 / 战斗音效（塔攻击等）/ 界面音效（按钮、卡牌、升级）
	_volume = _add_slider_row(grid, "音乐音量", 0.0, 1.0, 0.01)
	_volume.value_changed.connect(func(v: float):
		main.get_settings_draft()["volume"] = v)

	_sfx = _add_slider_row(grid, "音效音量", 0.0, 1.0, 0.01)
	_sfx.value_changed.connect(func(v: float):
		main.get_settings_draft()["sfx"] = v)

	_ui = _add_slider_row(grid, "UI音量", 0.0, 1.0, 0.01)
	_ui.value_changed.connect(func(v: float):
		main.get_settings_draft()["ui"] = v)

	# 帧率：滑块 + 数字输入框，两边互相同步
	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 16)
	grid.add_child(fps_row)
	var fps_label := UiKit.label("帧率", UiKit.FONT_NORMAL)
	fps_label.custom_minimum_size = Vector2(80, 0)
	fps_row.add_child(fps_label)
	_fps = UiKit.slider(Config.FPS_MIN, Config.FPS_MAX, 1.0, Config.FPS_MIN)
	_fps.value_changed.connect(func(v: float):
		main.get_settings_draft()["fps"] = int(v)
		if _fps_box != null and int(_fps_box.value) != int(v):
			_fps_box.set_value_no_signal(int(v)))
	fps_row.add_child(_fps)
	_fps_box = SpinBox.new()
	_fps_box.min_value = Config.FPS_MIN
	_fps_box.max_value = Config.FPS_MAX
	_fps_box.step = 1
	_fps_box.custom_minimum_size = Vector2(110, 36)
	_fps_box.focus_mode = Control.FOCUS_NONE
	_fps_box.value_changed.connect(func(v: float):
		main.get_settings_draft()["fps"] = int(v)
		if _fps != null and int(_fps.value) != int(v):
			_fps.set_value_no_signal(v))
	fps_row.add_child(_fps_box)

	# 分辨率：只列出当前显示器支持得起的档位（屏小的机器不会看到 4K 这种选了也没用的选项）
	var screen_size := DisplayServer.screen_get_size()
	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 12)
	grid.add_child(res_row)
	var res_label := UiKit.label("分辨率", UiKit.FONT_NORMAL)
	res_label.custom_minimum_size = Vector2(LABEL_W, 0)
	res_row.add_child(res_label)
	for preset in Config.available_resolutions(screen_size):
		var size: Vector2i = preset["size"]
		var b := UiKit.button(str(preset["label"]), Vector2(110, 50))
		b.tooltip_text = "%d x %d" % [size.x, size.y]
		var target: Vector2i = size
		b.pressed.connect(func():
			main.get_settings_draft()["resolution"] = [target.x, target.y]
			main.preview_display()
			refresh())
		res_row.add_child(b)
		_resolution_btns.append([target, b])

	# 窗口模式：全屏 / 窗口 / 无边框窗口
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 12)
	grid.add_child(mode_row)
	var mode_label := UiKit.label("窗口模式", UiKit.FONT_NORMAL)
	mode_label.custom_minimum_size = Vector2(LABEL_W, 0)
	mode_row.add_child(mode_label)
	for mode in [Config.WINDOW_MODE_FULLSCREEN, Config.WINDOW_MODE_WINDOWED,
			Config.WINDOW_MODE_BORDERLESS]:
		var b := UiKit.button(str(Config.WINDOW_MODE_LABELS[mode]), Vector2(150, 50))
		var m: String = mode
		b.pressed.connect(func():
			main.get_settings_draft()["window_mode"] = m
			main.preview_display()
			refresh())
		mode_row.add_child(b)
		_window_mode_btns.append([m, b])

	# 保存 / 返回
	var save := UiKit.button("保存当前设置", Vector2(280, 56))
	save.anchor_left = 1.0
	save.anchor_right = 1.0
	save.offset_left = -320.0
	save.offset_right = -40.0
	save.offset_top = 1000.0
	save.offset_bottom = 1056.0
	save.pressed.connect(func():
		Audio.play_sound("button_click")
		main.apply_settings())
	add_child(save)

	var back := UiKit.button("返回", Vector2(200, 50))
	back.position = Vector2(40, 1000)
	back.pressed.connect(func():
		Audio.play_sound("button_click")
		main.cancel_settings())
	add_child(back)


func _add_slider_row(parent: Control, text: String, min_v: float, max_v: float,
		step: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var l := UiKit.label(text, UiKit.FONT_NORMAL)
	l.custom_minimum_size = Vector2(LABEL_W, 0)
	row.add_child(l)
	var s := UiKit.slider(min_v, max_v, step, 1.0)
	row.add_child(s)
	return s


## 每次进入设置都按草稿重置控件（草稿是进入时复制的存档快照）。
func refresh() -> void:
	if _volume == null:
		return
	var draft := main.get_settings_draft()
	_volume.set_value_no_signal(float(draft.get("volume", 1.0)))
	_sfx.set_value_no_signal(float(draft.get("sfx", 1.0)))
	_ui.set_value_no_signal(float(draft.get("ui", 1.0)))
	var fps := int(draft.get("fps", Config.FPS_MIN))
	_fps.set_value_no_signal(fps)
	_fps_box.set_value_no_signal(fps)
	# 当前分辨率高亮
	var res: Vector2i = main.resolution_from(draft)
	for entry in _resolution_btns:
		_highlight(entry[1], (entry[0] as Vector2i) == res)

	# 当前窗口模式高亮
	var mode := str(draft.get("window_mode", Config.WINDOW_MODE_WINDOWED))
	for entry in _window_mode_btns:
		_highlight(entry[1], str(entry[0]) == mode)


## 选中态样式：金底深色字；未选中：常规按钮样式。
func _highlight(b: Button, selected: bool) -> void:
	UiKit.recolor_button(b, Config.COLOR_CARD_SEL if selected else Config.COLOR_BUTTON)
	b.add_theme_color_override("font_color",
			Color8(30, 30, 30) if selected else Config.COLOR_BUTTON_TEXT)
