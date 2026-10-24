class_name LevelSelect
extends Control
## 选关界面 —— 移植自 main.py 的 draw_level_select / click_level_select
##
## 关卡条目数量由 maps/index.json 决定，所以行是运行时生成的。

var main: Main = null
var _built := false
var _list: VBoxContainer = null


func setup(p_main: Main) -> void:
	main = p_main
	if _built:
		return
	_built = true
	_build()


func _build() -> void:
	add_child(UiKit.title("选择关卡"))

	_list = VBoxContainer.new()
	_list.name = "Levels"
	_list.anchor_left = 0.5
	_list.anchor_right = 0.5
	_list.offset_left = -440.0
	_list.offset_right = 440.0
	_list.offset_top = 160.0
	_list.add_theme_constant_override("separation", 20)
	add_child(_list)

	var back := UiKit.button("返回", Vector2(200, 50))
	back.position = Vector2(40, 640)
	back.pressed.connect(func():
		Audio.play_sound("button_click")
		main._show_state(Main.STATE_MAIN_MENU))
	add_child(back)


## 每次进入选关都重建列表（解锁状态与关卡数据可能已变）。
func refresh() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()

	var unlocked := {}
	for m in main.save_data.get("unlocked_maps", []):
		unlocked[m] = true

	for map_id in GameData.level_ids():
		var map_data = GameData.preload_level(map_id)
		if map_data == null:
			continue
		var is_unlocked: bool = unlocked.has(map_id)

		var row := UiKit.row_panel(Vector2(880, 90))
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		if not is_unlocked:
			var sb := row.get_theme_stylebox("panel") as StyleBoxFlat
			if sb != null:
				var dim_sb := sb.duplicate() as StyleBoxFlat
				dim_sb.bg_color = Config.COLOR_BUTTON_DISABLED
				row.add_theme_stylebox_override("panel", dim_sb)

		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 16)
		row.add_child(inner)

		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inner.add_child(left)
		left.add_child(UiKit.label(map_data.get("name", map_id), UiKit.FONT_NORMAL))
		# 无尽模式不是关卡序列里的一关，别让它顶着「章节 N」的编号
		var subtitle := ""
		if bool(map_data.get("endless", false)):
			subtitle = "无尽模式    %s" % map_data.get("description", "")
		else:
			subtitle = "章节 %d    %s" % [int(map_data.get("chapter", 1)),
					map_data.get("description", "")]
		left.add_child(UiKit.label(subtitle, UiKit.FONT_SMALL, Color8(170, 170, 180)))

		inner.add_child(UiKit.label("已解锁" if is_unlocked else "未解锁",
				UiKit.FONT_SMALL,
				Color8(150, 220, 150) if is_unlocked else Color8(150, 150, 150)))

		var btn := UiKit.button("进入" if is_unlocked else "未解锁", Vector2(120, 50))
		btn.disabled = not is_unlocked
		# level_ids() 返回无类型数组，循环变量是 Variant，需显式标 String
		var id: String = map_id
		btn.pressed.connect(func():
			Audio.play_sound("button_click")
			main.enter_level(id))
		inner.add_child(btn)
		_list.add_child(row)
