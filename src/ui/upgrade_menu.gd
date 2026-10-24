class_name UpgradeMenu
extends Control
## 升级界面 —— 移植自 main.py 的 draw_upgrade / click_upgrade
##
## 用金币永久提升：各塔等级、城堡生命等级、初始点数等级。
## 塔的行数由存档里已解锁的塔决定，所以整体运行时重建。

var main: Main = null
var _built := false
var _list: VBoxContainer = null
var _gold_label: Label = null


func setup(p_main: Main) -> void:
	main = p_main
	if _built:
		return
	_built = true
	_build()


func _build() -> void:
	_gold_label = UiKit.label("金币: 0", UiKit.FONT_NORMAL, Config.COLOR_MONEY_GOLD)
	_gold_label.position = Vector2(12, 12)
	add_child(_gold_label)
	add_child(UiKit.title("升级"))

	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.anchor_left = 0.5
	_list.anchor_right = 0.5
	_list.offset_left = -520.0
	_list.offset_right = 520.0
	_list.offset_top = 150.0
	_list.add_theme_constant_override("separation", 10)
	add_child(_list)

	var back := UiKit.button("返回", Vector2(200, 50))
	back.position = Vector2(40, 640)
	back.pressed.connect(func():
		Audio.play_sound("button_click")
		main.persist_save()
		main._show_state(Main.STATE_MAIN_MENU))
	add_child(back)
	refresh()


func refresh() -> void:
	if _list == null:
		return
	_gold_label.text = "金币: %d" % int(main.save_data.get("gold", 0))
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()

	var gold := int(main.save_data.get("gold", 0))
	# 逐座塔一行
	for tower_id in main.save_data.get("unlocked_towers", []):
		var data = GameData.get_tower(tower_id)
		if data == null:
			continue
		_list.add_child(_tower_row(tower_id, data, gold))

	# 城堡生命 与 初始点数 并排两列
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 40)
	_list.add_child(stats)
	stats.add_child(_stat_row("castle", "城堡生命",
			"castle_hp_level", Config.CASTLE_HP_MAX_LEVEL,
			func(lv: int): return Config.castle_hp_for_level(lv), gold))
	stats.add_child(_stat_row("points", "初始点数",
			"initial_points_level", Config.INITIAL_POINTS_MAX_LEVEL,
			func(lv: int): return Config.initial_points_for_level(lv), gold))


func _tower_row(tower_id: String, data: Dictionary, gold: int) -> PanelContainer:
	var row := UiKit.row_panel(Vector2(1040, 90))
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 16)
	row.add_child(inner)

	var cur := int(main.save_data.get("tower_levels", {}).get(tower_id, 1))
	var levels: Array = data.get("levels", [])
	var cur_data: Dictionary = levels[cur - 1] if (cur - 1 >= 0 and cur - 1 < levels.size()) else levels[0]
	var can_up := cur < levels.size()

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(info)
	info.add_child(UiKit.label("%s  Lv.%d" % [data.get("name", tower_id), cur]))

	var detail: String
	if can_up:
		var nxt: Dictionary = levels[cur]
		detail = "攻击 %s → %s    攻速 %s → %s    范围 %s → %s" % [
			cur_data.get("attack_power"), nxt.get("attack_power"),
			cur_data.get("attack_speed"), nxt.get("attack_speed"),
			cur_data.get("attack_range"), nxt.get("attack_range")]
	else:
		detail = "攻击 %s    攻速 %s    范围 %s（满级）" % [
			cur_data.get("attack_power"), cur_data.get("attack_speed"),
			cur_data.get("attack_range")]
	info.add_child(UiKit.label(detail, UiKit.FONT_SMALL, Color8(200, 200, 210)))

	var cost := Config.upgrade_cost(cur)
	var btn := UiKit.button("升级 %d金" % cost, Vector2(150, 50))
	btn.disabled = not can_up or gold < cost
	var id: String = tower_id
	btn.pressed.connect(func():
		if main.try_upgrade_tower(id):
			refresh())
	inner.add_child(btn)
	return row


## 城堡生命 / 初始点数 的升级条目。
func _stat_row(kind: String, title: String, level_key: String,
		max_level: int, value_of: Callable, gold: int) -> PanelContainer:
	var row := UiKit.row_panel(Vector2(500, 70))
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 16)
	row.add_child(inner)

	var cur := int(main.save_data.get(level_key, 1))
	var can_up := cur < max_level
	var nxt_value: int = value_of.call(cur + 1) if can_up else value_of.call(cur)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(info)
	info.add_child(UiKit.label("%s Lv.%d" % [title, cur]))
	info.add_child(UiKit.label("%d → %d" % [value_of.call(cur), nxt_value],
			UiKit.FONT_SMALL, Color8(200, 200, 210)))

	var cost := Config.upgrade_cost(cur)
	var btn := UiKit.button("%d金" % cost, Vector2(130, 50))
	btn.disabled = not can_up or gold < cost
	btn.pressed.connect(func():
		if main.try_upgrade_stat(kind):
			refresh())
	inner.add_child(btn)
	return row
