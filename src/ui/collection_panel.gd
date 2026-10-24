class_name CollectionPanel
extends Control
## 「已获取卡牌」面板 —— 移植自 renderer.py 的 _draw_collection_panel / collection_layout
##
## 按稀有度分组展示已购卡牌的加成明细（同类 buff 合并计数）。
## 面板高度随内容行数变化，所以整体是运行时构建的；只在内容变化时重建。

var game: Game = null
var _panel: PanelContainer = null
var _vbox: VBoxContainer = null
var _signature := ""          ## 内容指纹，用于避免每帧重建


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_top = 70.0
	_panel.custom_minimum_size = Vector2(460, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP   # 面板内点击不穿透到游戏
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(28, 28, 40, 238)
	sb.set_corner_radius_all(10)
	sb.border_color = Color8(120, 120, 140)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 4)
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_vbox)
	_panel.visible = false


func setup(p_game: Game) -> void:
	game = p_game


func refresh() -> void:
	if game == null or _panel == null:
		return
	var playable := game.state == Game.STATE_BUILD or game.state == Game.STATE_COMBAT
	var show := game.show_collection and playable
	_panel.visible = show
	if not show:
		return

	# 内容指纹：数量 + 明细行数。变了才重建，避免每帧重建。
	var groups: Array = game.card_manager.summary()
	var total: int = game.card_manager.purchased.size()
	var sig := "%d|" % total
	for g in groups:
		sig += "%s:%d;" % [g["rarity"], g["items"].size()]
	if sig == _signature:
		return
	_signature = sig

	_clear()
	_vbox.add_child(_title("已获取卡牌：%d 个" % total, Color8(255, 225, 130), 20))
	if total == 0:
		_vbox.add_child(_row("尚未获取任何卡牌", Color8(170, 170, 170)))
		return
	for group in groups:
		var rarity: String = group["rarity"]
		var label: String = Config.RARITY_LABELS.get(rarity, rarity)
		# 棱彩的值是 null，先用无类型变量接住再兜底（Color 装不下 null）
		var color = Config.RARITY_COLORS.get(rarity)
		if color == null:
			color = Color8(255, 255, 255)
		_vbox.add_child(_row("—— %s ——" % label, color))
		for item in group["items"]:
			_vbox.add_child(_item_row(item))


func _clear() -> void:
	for c in _vbox.get_children():
		_vbox.remove_child(c)
		c.queue_free()


func _title(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _row(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 一行明细：左侧描述，右侧 ×数量。
func _item_row(item: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var desc := _row("  %s" % item["desc"], Color8(235, 235, 235))
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(desc)

	var cnt := _row("×%d" % item["count"], Color8(150, 200, 255))
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(cnt)
	return row
