class_name TowerBar
extends Control
## 底部塔选择栏 —— 移植自 renderer.py 的 _draw_tower_bar / _tower_icon_rects / _tower_stats
##
## 每座塔一张卡片（缩略图 + 塔名 + 属性 + 价格），点击进入放置模式。
## 卡片数量由地图的 tower_pool 决定，所以卡片是运行时生成的，不写死在场景里。

signal tower_selected(tower_id: String)

const CARD_SIZE := Vector2(220, 170)
const CARD_GAP := 40.0
const THUMB_RECT := Rect2(150, 45, 43, 78)

var game: Game = null
var _row: HBoxContainer = null
var _cards := {}          ## {tower_id: Button}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = HBoxContainer.new()
	_row.name = "Cards"
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", int(CARD_GAP))
	# 卡片从 UI 区顶部开始（与原版一致：y = height - UI_HEIGHT）
	_row.anchor_right = 1.0
	_row.offset_top = 0.0
	_row.offset_bottom = CARD_SIZE.y
	add_child(_row)


func setup(p_game: Game) -> void:
	game = p_game
	_rebuild()


## 按当前 tower_pool 重建所有卡片。
func _rebuild() -> void:
	if _row == null:
		return
	for c in _row.get_children():
		c.queue_free()
	_cards.clear()
	if game == null:
		return

	for key in game.tower_pool:
		if GameData.get_tower(key) == null:
			continue
		var card := _make_card(key)
		_row.add_child(card)
		_cards[key] = card


## 单张塔卡片：用「防御塔UI框」贴图当按钮底，上面叠文字与缩略图。
func _make_card(key: String) -> Button:
	var stats := _tower_stats(key)
	var card := Button.new()
	card.name = key
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.focus_mode = Control.FOCUS_NONE
	card.tooltip_text = stats["name"]

	# 背景：防御塔UI框贴图（缺失时回退纯色框），用一个 StyleBoxTexture 当按钮样式
	var art := GameData.load_texture("image/防御塔UI框.png")
	var style := StyleBoxTexture.new()
	if art != null:
		style.texture = art
	else:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color8(34, 38, 52)
		flat.set_corner_radius_all(8)
		style = null
		card.add_theme_stylebox_override("normal", flat)
		card.add_theme_stylebox_override("hover", flat)
		card.add_theme_stylebox_override("pressed", flat)
	if style != null:
		card.add_theme_stylebox_override("normal", style)
		card.add_theme_stylebox_override("hover", style)
		card.add_theme_stylebox_override("pressed", style)
	card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	# 塔名（左上）
	card.add_child(_label("  %s Lv.%d" % [stats["name"], stats["level"]],
			Vector2(16, 25), Vector2(190, 20), Color8(255, 225, 130)))

	# 属性：左列标签 + 右列数值
	var rows := [
		["攻击力:", "%.0f" % stats["power"]],
		["攻速:", "%.1f" % stats["speed"]],
		["DPS:", "%.0f" % stats["dps"]],
		["范围:", "%s格" % _trim(stats["range"])],
		["价格:", "%d" % stats["cost"]],
	]
	var y := 45.0
	for row in rows:
		card.add_child(_label(row[0], Vector2(16, y), Vector2(60, 18), Config.COLOR_TEXT))
		card.add_child(_label(row[1], Vector2(80, y), Vector2(66, 18), Color8(255, 225, 130)))
		y += 18.0

	# 右侧缩略图（用塔立绘原图等比缩放，缺失回退色块圆）
	var thumb := TextureRect.new()
	thumb.name = "Thumb"
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.position = THUMB_RECT.position
	thumb.size = THUMB_RECT.size
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := GameData.load_texture(stats["image"])
	if tex != null:
		thumb.texture = tex
	else:
		var fallback := ColorRect.new()
		fallback.color = Color8(24, 26, 36)
		fallback.position = THUMB_RECT.position
		fallback.size = THUMB_RECT.size
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(fallback)
	card.add_child(thumb)

	card.pressed.connect(func(): tower_selected.emit(key))
	return card


func _label(text: String, pos: Vector2, size: Vector2, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 让点击穿透到卡片按钮
	return l


## 去掉浮点尾巴：30.0 -> "30"，3.5 -> "3.5"（对应 Python 的 "%g"）
func _trim(v: float) -> String:
	if absf(v - roundf(v)) < 1e-6:
		return str(int(roundf(v)))
	return str(v)


## 卡片需要展示的信息（含卡牌 buff 后的数值）—— 对应 renderer.py 的 _tower_stats。
func _tower_stats(key: String) -> Dictionary:
	var data: Dictionary = GameData.get_tower(key)
	var level := int(game.tower_levels.get(key, 1))
	var levels: Array = data.get("levels", [])
	var level_data: Dictionary = levels[level - 1] if (level - 1 >= 0 and level - 1 < levels.size()) else levels[0]
	var base_power := float(level_data.get("attack_power", data.get("attack_power", 50)))
	var base_speed := float(level_data.get("attack_speed", data.get("attack_speed", 1.0)))
	var grid_range := float(level_data.get("attack_range", data.get("attack_range", 3)))
	# 用一个只带三个字段的替身对象算卡牌加成（CardManager 只读这三个字段）
	var ref := _TowerRef.new(
			data.get("attack_element"),
			data.get("attack_type", "elemental"),
			key)
	var power: float = game.card_manager.final_value(base_power, "damage", ref)
	var speed: float = game.card_manager.final_value(base_speed, "attack_speed", ref)
	return {
		"name": data.get("name", key),
		"level": level,
		"power": power,
		"speed": speed,
		"dps": power * speed,
		"range": grid_range,
		"cost": int(data.get("build_cost", 50)),
		"color": Config.ELEMENT_COLORS.get(data.get("attack_element"), Config.COLOR_BUTTON),
		"image": data.get("image", ""),
	}


## CardManager 读取的最小替身（只提供它关心的三个字段）
class _TowerRef extends RefCounted:
	var attack_element
	var attack_type: String
	var tower_id: String

	func _init(element, type: String, id: String) -> void:
		attack_element = element
		attack_type = type
		tower_id = id


## 每帧刷新：高亮当前正在放置的塔类型。
func refresh() -> void:
	if game == null:
		return
	for key in _cards:
		var card: Button = _cards[key]
		if card == null or not is_instance_valid(card):
			continue
		# selected_build_tower 是鸭子类型字段，比较结果是 Variant，需显式标 bool
		var active: bool = (key == game.selected_build_tower)
		# 选中态：加一圈金色描边（用 StyleBoxFlat 叠在贴图样式外面做不到，
		# 这里改用 modulate 提亮 + 一个额外的描边节点）
		card.modulate = Color(1.25, 1.2, 1.0) if active else Color.WHITE
		var border: Panel = card.get_node_or_null("Border")
		if active and border == null:
			border = Panel.new()
			border.name = "Border"
			border.position = Vector2.ZERO
			border.size = CARD_SIZE
			border.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.border_color = Config.COLOR_CARD_SEL
			sb.set_border_width_all(3)
			sb.set_corner_radius_all(8)
			border.add_theme_stylebox_override("panel", sb)
			card.add_child(border)
		elif not active and border != null:
			border.queue_free()
