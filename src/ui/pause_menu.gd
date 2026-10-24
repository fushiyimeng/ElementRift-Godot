class_name PauseMenu
extends Control
## 暂停菜单（覆盖在游戏画面之上）—— 移植自 main.py 的 draw_pause_menu / click_pause

var main: Main = null
var _built := false


func setup(p_main: Main) -> void:
	main = p_main
	if _built:
		return
	_built = true
	_build()


func _build() -> void:
	add_child(UiKit.dim(0.6))

	var vbox := VBoxContainer.new()
	vbox.name = "Menu"
	vbox.anchor_left = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -130.0
	vbox.offset_right = 130.0
	vbox.offset_top = -70.0
	vbox.offset_bottom = 182.0
	vbox.add_theme_constant_override("separation", 14)
	add_child(vbox)

	var resume := UiKit.button("继续游戏")
	resume.pressed.connect(func():
		Audio.play_sound("button_click")
		main._show_state(Main.STATE_GAME))
	vbox.add_child(resume)

	var settings := UiKit.button("设置")
	settings.pressed.connect(func():
		Audio.play_sound("button_click")
		main.enter_settings(Main.STATE_PAUSE))
	vbox.add_child(settings)

	var quit := UiKit.button("退出本局")
	quit.pressed.connect(func():
		Audio.play_sound("button_click")
		main._on_game_exit(false))       # 中途退出不发金币
	vbox.add_child(quit)

	var title := UiKit.label("暂停", UiKit.FONT_TITLE)
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.offset_left = -150.0
	title.offset_right = 150.0
	title.offset_top = 110.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
