class_name Hud
extends Control
## 游戏内 HUD —— 移植自 renderer.py 的 _draw_hud / _draw_game_controls / _draw_collection_button
##
## 左上角信息栏、右上角快进/暂停按钮、顶部正中「已获取卡牌」入口。
## 只读地展示 game 的状态，自身不修改任何游戏逻辑，交互一律发信号给 GameScreen。

signal collection_toggled
signal speed_pressed
signal pause_pressed
signal skip_card_pressed

const MARGIN := Vector2(12, 8)
const ROW_H := 20.0
const BTN_SIZE := 48.0

var game: Game = null

var _points_label: Label
var _gold_label: Label
var _milestone_label: Label
var _castle_label: Label
var _wave_label: Label
var _monsters_label: Label
var _speed_label: Label
var _forward_btn: Button
var _pause_btn: Button
var _collection_btn: Button
var _pause_icon: Texture2D
var _resume_icon: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_left()
	_build_top_right()
	_build_collection_button()


## 左上角：局内点数、本局金币（仅无尽模式）、里程碑进度（仅无尽模式）、
## 城堡血量、波次、剩余怪物数。
func _build_top_left() -> void:
	var box := VBoxContainer.new()
	box.name = "TopLeft"
	box.position = MARGIN
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_points_label = _make_label(Config.COLOR_MONEY_POINTS)
	_gold_label = _make_label(Config.COLOR_MONEY_GOLD)
	_milestone_label = _make_label(Config.COLOR_MONEY_GOLD)
	_castle_label = _make_label(Config.COLOR_HOSTILE)
	_wave_label = _make_label(Config.COLOR_TEXT)
	_monsters_label = _make_label(Config.COLOR_TEXT)
	for l in [_points_label, _gold_label, _milestone_label,
			_castle_label, _wave_label, _monsters_label]:
		box.add_child(l)


func _make_label(color: Color) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 17)
	l.custom_minimum_size = Vector2(180, ROW_H)
	return l


## 右上角：快进按钮 + 速度倍率 + 暂停/继续按钮。
func _build_top_right() -> void:
	var box := HBoxContainer.new()
	box.name = "TopRight"
	# 容器默认 mouse_filter 也是 STOP，不设 IGNORE 会挡住这块区域的棋盘点击
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -220.0
	box.offset_top = MARGIN.y
	box.offset_right = -MARGIN.x
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	_forward_btn = _make_icon_button("res://data/image/forward.png", "快进")
	_forward_btn.pressed.connect(func(): speed_pressed.emit())
	box.add_child(_forward_btn)

	_speed_label = _make_label(Config.COLOR_TEXT)
	_speed_label.custom_minimum_size = Vector2(48, BTN_SIZE)
	_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_speed_label)

	# 暂停/继续共用同一个按钮，图标随状态切换
	_pause_icon = GameData.load_texture("image/暂停.png")
	_resume_icon = GameData.load_texture("image/继续.png")
	_pause_btn = _make_icon_button("res://data/image/暂停.png", "暂停/继续")
	_pause_btn.pressed.connect(func(): pause_pressed.emit())
	box.add_child(_pause_btn)


func _make_icon_button(icon_path: String, tip: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE          # 避免空格键误触发按钮
	b.icon = load(icon_path) if ResourceLoader.exists(icon_path) else null
	b.expand_icon = true
	b.add_theme_stylebox_override("normal", _flat_style(Config.COLOR_BUTTON))
	b.add_theme_stylebox_override("hover", _flat_style(Config.COLOR_BUTTON_HOVER))
	b.add_theme_stylebox_override("pressed", _flat_style(Config.COLOR_BUTTON_HOVER))
	return b


func _flat_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(8)
	return s


## 顶部正中：「已获取卡牌」入口。
func _build_collection_button() -> void:
	_collection_btn = Button.new()
	_collection_btn.name = "CollectionButton"
	_collection_btn.custom_minimum_size = Vector2(200, 36)
	_collection_btn.anchor_left = 0.5
	_collection_btn.anchor_right = 0.5
	_collection_btn.offset_left = -100.0
	_collection_btn.offset_right = 100.0
	_collection_btn.offset_top = 8.0
	_collection_btn.offset_bottom = 44.0
	_collection_btn.focus_mode = Control.FOCUS_NONE
	_collection_btn.add_theme_font_size_override("font_size", 17)
	_collection_btn.pressed.connect(func(): collection_toggled.emit())
	add_child(_collection_btn)


## 每帧由 GameScreen 调用，把 game 的最新状态刷到界面上。
func refresh() -> void:
	if game == null:
		return
	_points_label.text = "局内点数: %d" % int(game.points)

	# 金币只在无尽模式显示：普通关卡一局固定发一笔（通关才结算），
	# 局内看着一个不会动的数字只会误导；里程碑同理只有无尽模式才有。
	_gold_label.visible = game.endless
	_milestone_label.visible = game.endless
	if game.endless:
		_gold_label.text = "本局金币: %d" % int(game.gold)
		var next_milestone: int = game.endless_milestone + 1
		_milestone_label.text = "里程碑: 第 %d 波 +%d（已获 %d）" % [
			next_milestone * Config.ENDLESS_MILESTONE_STEP,
			Config.endless_milestone_bonus(next_milestone),
			game.endless_bonus_gold]

	_castle_label.text = "城堡: %d" % game.castle_hp
	if game.endless:
		_wave_label.text = "波次: %d (∞)" % (game.wave_index + 1)
	else:
		_wave_label.text = "波次: %d/%d" % [
			mini(game.wave_index + 1, game.waves.size()), game.waves.size()]
	_monsters_label.text = "怪物: %d/%d" % [game.wave_remaining, game.wave_total]
	_speed_label.text = "%dx" % game.game_speed

	# 暂停图标随状态切换
	if _pause_btn != null:
		var icon := _resume_icon if game.paused else _pause_icon
		if icon != null:
			_pause_btn.icon = icon

	# 「已获取卡牌」入口只在可操作阶段显示
	var playable := game.state == Game.STATE_BUILD or game.state == Game.STATE_COMBAT
	_collection_btn.visible = playable
	if playable:
		var total: int = game.card_manager.purchased.size()
		_collection_btn.text = "已获取卡牌 (%d)" % total
		var active: bool = game.show_collection
		_collection_btn.add_theme_color_override("font_color",
				Color8(30, 30, 30) if active else Config.COLOR_TEXT)
		_collection_btn.add_theme_stylebox_override("normal",
				_flat_style(Config.COLOR_CARD_SEL if active else Config.COLOR_BUTTON))
		_collection_btn.add_theme_stylebox_override("hover", _flat_style(
				Config.COLOR_CARD_SEL if active else Config.COLOR_BUTTON_HOVER))
