class_name CardPanel
extends Control
## 卡牌选择面板 —— 移植自 renderer.py 的 _card_layout / _card_ui_rects / _draw_card*
##
## 每波结束弹出，用局内点数购买卡牌加成；每张卡可刷新一次。
## 面板不阻塞游戏（对应 Python 版「卡牌面板不阻塞战斗」的设计）。

signal card_clicked(index: int)
signal refresh_clicked(index: int)
signal skip_clicked

const CARD_SIZE := Vector2(150, 267)
const CARD_GAP := 40.0
const REFRESH_H := 34.0
const SKIP_H := 46.0
const SKIP_W := 160.0
const GAP_AFTER_CARD := 12.0
const GAP_BEFORE_SKIP := 16.0

var game: Game = null
var _root: Control = null
var _cards: Array = []
var _refresh_btns: Array = []
var _skip_btn: Button = null
## 卡片内容状态的指纹，用来避免每帧重建卡面上的节点
var _state_signature := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root = Control.new()
	_root.name = "Root"
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)


func setup(p_game: Game) -> void:
	game = p_game


## 每帧刷新：面板显隐与内容（卡牌上下架是游戏逻辑决定的，UI 只跟随）。
func refresh() -> void:
	if game == null or _root == null:
		return
	var visible_now := game.card_timer > 0.0 and not game.current_offers.is_empty()
	_root.visible = visible_now
	if not visible_now:
		return
	# 卡牌数量变化（购买/刷新/换波）时重建
	if _cards.size() != game.current_offers.size():
		_rebuild()
		_state_signature = ""
	_update_card_states()


## 按当前卡牌数量重建整行卡片 + 刷新按钮 + 跳过按钮。
func _rebuild() -> void:
	# 先 remove_child 再 queue_free：queue_free 延迟到帧末，期间旧节点仍在树上，
	# 会让新加的背景压不住旧节点。
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	_cards.clear()
	_refresh_btns.clear()
	_skip_btn = null

	var n := maxi(1, game.current_offers.size())
	var total_w := n * CARD_SIZE.x + (n - 1) * CARD_GAP
	var start_x := (game.width - total_w) / 2.0
	var total_h := CARD_SIZE.y + GAP_AFTER_CARD + REFRESH_H + GAP_BEFORE_SKIP + SKIP_H
	var card_top := (game.height - total_h) / 2.0

	# 卡牌背后加一层压暗底。
	# 卡牌背景图有透明区域，战斗中的怪物血条会从卡面透出来，看着像 UI 出错。
	# Python 版也这样（它直接画在游戏画面上），但既然 UI 是重写的，这里补上可读性。
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0, 0, 0, 0.45)
	backdrop.position = Vector2(start_x - 24.0, card_top - 24.0)
	backdrop.size = Vector2(total_w + 48.0, total_h + 48.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)

	for i in game.current_offers.size():
		var x := start_x + i * (CARD_SIZE.x + CARD_GAP)
		var card := _make_card(i)
		card.position = Vector2(x, card_top)
		_root.add_child(card)
		_cards.append(card)

		var rb := _make_button("刷新", Vector2(CARD_SIZE.x, REFRESH_H))
		rb.position = Vector2(x, card_top + CARD_SIZE.y + GAP_AFTER_CARD)
		var idx := i
		rb.pressed.connect(func(): refresh_clicked.emit(idx))
		_root.add_child(rb)
		_refresh_btns.append(rb)

	_skip_btn = _make_button("跳过", Vector2(SKIP_W, SKIP_H), Color8(90, 90, 100))
	_skip_btn.position = Vector2((game.width - SKIP_W) / 2.0,
			card_top + CARD_SIZE.y + GAP_AFTER_CARD + REFRESH_H + GAP_BEFORE_SKIP)
	_skip_btn.pressed.connect(func(): skip_clicked.emit())
	_root.add_child(_skip_btn)


## 单张卡：背景图 + 稀有度边框 + 稀有度名 + 描述 + 价格。
func _make_card(index: int) -> Control:
	var card := Control.new()
	card.name = "Card%d" % index
	card.size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 背景图（缺失回退纯色框）。
	# 这两个节点是常驻的，刷新时不清 —— 见 _clear_dynamic_children 的白名单。
	var bg_tex := GameData.load_texture("image/卡牌背景图.png")
	if bg_tex != null:
		var bg := TextureRect.new()
		bg.name = "Bg"
		bg.texture = bg_tex
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.size = CARD_SIZE
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(bg)
	else:
		var bg2 := Panel.new()
		bg2.name = "Bg"
		bg2.size = CARD_SIZE
		bg2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color8(34, 38, 52)
		sb.set_corner_radius_all(10)
		sb.border_color = Color8(90, 90, 110)
		sb.set_border_width_all(1)
		bg2.add_theme_stylebox_override("panel", sb)
		card.add_child(bg2)

	# 整张卡是一个隐形按钮（点击购买）
	var hit := Button.new()
	hit.name = "Hit"
	hit.size = CARD_SIZE
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	hit.pressed.connect(func(): card_clicked.emit(index))
	card.add_child(hit)
	return card


## 每帧刷新每张卡的内容与按钮可用状态（购买后置灰等）。
func _update_card_states() -> void:
	# 指纹变了才重建卡面节点。只关心「是否买得起刷新」这个布尔，
	# 不用点数原值，否则点数每次跳动都会重建。
	var sig := str(game.current_offers) + str(game.card_refreshed) \
			+ str(game.points >= Config.CARD_REFRESH_COST)
	if sig == _state_signature:
		return
	_state_signature = sig

	for i in _cards.size():
		var card: Control = _cards[i]
		if card == null or not is_instance_valid(card):
			continue
		var card_id = game.current_offers[i] if i < game.current_offers.size() else null
		_clear_dynamic_children(card)
		if card_id == null:
			card.add_child(_label("已购买", Vector2(0, CARD_SIZE.y / 2.0 - 10.0),
					CARD_SIZE, Color8(200, 200, 200), HORIZONTAL_ALIGNMENT_CENTER))
		else:
			var data: Dictionary = GameData.get_card(card_id)
			if data == null:
				continue
			_draw_card_content(card, data)

		# 刷新按钮状态
		if i < _refresh_btns.size():
			var rb: Button = _refresh_btns[i]
			var refreshed: bool = i < game.card_refreshed.size() and game.card_refreshed[i]
			var enabled: bool = card_id != null and not refreshed \
					and game.points >= Config.CARD_REFRESH_COST
			rb.disabled = not enabled
			rb.text = "已刷新" if refreshed else ("已购买" if card_id == null else "刷新")

	if _skip_btn != null:
		_skip_btn.text = "跳过"


## 清掉上一次刷新生成的动态内容，只保留卡面背景与点击层。
##
## 用白名单（保留 Bg / Hit）而不是「删名字以 Dyn 开头的」：
## 之前靠命名约定，结果「已购买」那个 Label 名字是自动生成的，从来没被清掉 ——
## 某张卡一旦显示过「已购买」，该字样就永久留在卡面上，
## 之后同一张卡再次出现在面板里会带着旧字样，看着像不能买（其实能买）。
##
## 另外必须先 remove_child 再 queue_free：queue_free 延迟到帧末，
## 期间旧节点仍在 get_children() 里，逐帧重建就会越积越多。
func _clear_dynamic_children(card: Control) -> void:
	for c in card.get_children():
		if c.name == "Bg" or c.name == "Hit":
			continue
		card.remove_child(c)
		c.queue_free()


## 画一张卡的内容：稀有度边框、稀有度名、加成描述、价格。
func _draw_card_content(card: Control, data: Dictionary) -> void:
	var rarity: String = data.get("rarity", "brass")
	# 稀有度边框
	var border := _RarityBorder.new()
	border.name = "DynBorder"
	border.rarity = rarity
	border.size = CARD_SIZE
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(border)

	# 稀有度名（顶部居中）
	var label: String = Config.RARITY_LABELS.get(rarity, rarity)
	# 棱彩在 RARITY_COLORS 里是 null，不能直接赋给值类型 Color（装不下 null），
	# 所以先用无类型变量接住再兜底。
	var color = Config.RARITY_COLORS.get(rarity)
	if color == null:
		color = Color8(255, 255, 255)     # 棱彩没有单色，用白色
	# y=36 而不是 Python 版的 16：卡牌背景图顶部正中有个花纹，
	# 压在上面会把「黄铜/白银/…」字盖住，下移一点避开。
	var rarity_label := _label(label, Vector2(0, 36), CARD_SIZE, color,
			HORIZONTAL_ALIGNMENT_CENTER)
	rarity_label.name = "DynRarity"
	card.add_child(rarity_label)

	# 加成描述（自动换行，中文用 ARBITRARY）
	var desc := Label.new()
	desc.name = "DynDesc"
	desc.text = CardManager.describe_card(data)
	desc.position = Vector2(16, 70)
	desc.size = Vector2(CARD_SIZE.x - 32.0, 80)
	# 用 WORD_SMART 而不是 ARBITRARY：ARBITRARY 会在任意字符处断行，
	# 把「火元素伤害 +10%」拆成「火元素伤害 +10」/「%」；
	# WORD_SMART 优先在空格处断，得到「火元素伤害」/「+10%」。
	# 中文没有空格时它仍会逐字回退断行，不会出现溢出。
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 17)
	desc.add_theme_color_override("font_color", Color8(255, 225, 130))
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(desc)

	# 价格
	var price := _label("%d 点" % int(data.get("price", 0)),
			Vector2(16, 160), Vector2(CARD_SIZE.x - 32.0, 20),
			Config.COLOR_MONEY_POINTS)
	price.name = "DynPrice"
	card.add_child(price)


func _label(text: String, pos: Vector2, size: Vector2, color: Color,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_button(text: String, size: Vector2,
		bg: Color = Color8(60, 90, 120)) -> Button:
	var b := Button.new()
	b.text = text
	b.size = size
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate() as StyleBoxFlat
	sb_hover.bg_color = bg.lightened(0.2)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_hover)
	var sb_disabled := sb.duplicate() as StyleBoxFlat
	sb_disabled.bg_color = Color8(58, 58, 62)
	b.add_theme_stylebox_override("disabled", sb_disabled)
	return b


## 稀有度边框：普通稀有度画单色；prismatic 四边不同色相，形成彩虹边。
class _RarityBorder extends Control:
	var rarity := "brass"

	func _draw() -> void:
		var color: Color = Config.RARITY_COLORS.get(rarity)
		if color != null:
			draw_rect(Rect2(Vector2.ZERO, size), color, false, 3.0)
			return
		# prismatic：四边各取一个色相
		var pts := [Vector2.ZERO, Vector2(size.x, 0),
				Vector2(size.x, size.y), Vector2(0, size.y)]
		for i in 4:
			var hue := float(i) / 4.0
			var c := Color.from_hsv(hue, 0.8, 1.0)
			draw_line(pts[i], pts[(i + 1) % 4], c, 3.0)
