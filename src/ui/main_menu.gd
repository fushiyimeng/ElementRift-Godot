class_name MainMenu
extends Control
## 主菜单 —— 移植自 main.py 的 draw_main_menu / click_main_menu

var main: Main = null
var _built := false


func setup(p_main: Main) -> void:
	main = p_main
	if _built:
		return
	_built = true
	_build()


func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "Menu"
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.offset_left = -130.0
	vbox.offset_right = 130.0
	vbox.offset_top = 400.0
	vbox.add_theme_constant_override("separation", 14)
	add_child(vbox)

	var start := UiKit.button("开始游戏")
	start.pressed.connect(func():
		Audio.play_sound("button_click")
		main._show_state(Main.STATE_LEVEL_SELECT))
	vbox.add_child(start)

	var upgrade := UiKit.button("升级")
	upgrade.pressed.connect(func():
		Audio.play_sound("button_click")
		main._show_state(Main.STATE_UPGRADE))
	vbox.add_child(upgrade)

	var settings := UiKit.button("设置")
	settings.pressed.connect(func():
		Audio.play_sound("button_click")
		main.enter_settings(Main.STATE_MAIN_MENU))
	vbox.add_child(settings)

	var quit := UiKit.button("退出")
	quit.pressed.connect(func():
		Audio.play_sound("button_click")
		main.quit_game())
	vbox.add_child(quit)

	# 标题 logo：色块 + 标题 + 版本号
	var logo := ColorRect.new()
	logo.name = "Logo"
	logo.color = Color8(70, 100, 160)
	logo.anchor_left = 0.5
	logo.anchor_right = 0.5
	logo.offset_left = -170.0
	logo.offset_right = 170.0
	logo.offset_top = 150.0
	logo.offset_bottom = 260.0
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)

	var title := UiKit.label("元素裂隙", UiKit.FONT_TITLE)
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.offset_left = -170.0
	title.offset_right = 170.0
	title.offset_top = 188.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	var version := UiKit.label("v%s" % Config.VERSION, UiKit.FONT_SMALL, Color8(170, 180, 200))
	version.anchor_left = 0.5
	version.anchor_right = 0.5
	version.offset_left = -100.0
	version.offset_right = 100.0
	version.offset_top = 272.0
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(version)
