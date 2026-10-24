class_name TargetingSelector
extends Control
## 索敌策略切换按钮 —— 移植自 renderer.py 的 _draw_targeting_selector / targeting_selector_rects
##
## 选中某座塔时，在塔上方（顶部放不下则下方）显示 HP> / HP< / 随机 三个按钮，
## 当前策略高亮。

signal mode_selected(tower, mode: String)

## (策略, 显示文字)，顺序即显示顺序
const LABELS := [["highest_hp", "HP>"], ["lowest_hp", "HP<"], ["random", "随机"]]
const BTN_SIZE := Vector2(88, 40)
const BTN_GAP := 8.0

var game: Game = null
var _buttons := {}          ## {mode: Button}
var _row: HBoxContainer = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", int(BTN_GAP))
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)

	for entry in LABELS:
		var mode: String = entry[0]
		var b := Button.new()
		b.text = entry[1]
		b.custom_minimum_size = BTN_SIZE
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_stylebox_override("normal", _style(Config.COLOR_BUTTON))
		b.add_theme_stylebox_override("hover", _style(Config.COLOR_BUTTON_HOVER))
		b.add_theme_stylebox_override("pressed", _style(Config.COLOR_BUTTON_HOVER))
		b.pressed.connect(func(): _on_pressed(mode))
		_row.add_child(b)
		_buttons[mode] = b


func _style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	return s


func _on_pressed(mode: String) -> void:
	if game != null and game.selected_tower != null:
		mode_selected.emit(game.selected_tower, mode)


func setup(p_game: Game) -> void:
	game = p_game


## 每帧刷新：跟随选中的塔定位，并高亮当前策略。
func refresh() -> void:
	if game == null or _row == null:
		return
	var tower = game.selected_tower
	var show := tower != null and (game.state == Game.STATE_BUILD
			or game.state == Game.STATE_COMBAT)
	_row.visible = show
	if not show:
		return

	var total_w := LABELS.size() * BTN_SIZE.x + (LABELS.size() - 1) * BTN_GAP
	# tower 取自无类型的 selected_tower，属性是 Variant，需显式标 float
	var x: float = tower.x - total_w / 2.0
	var y: float = tower.y - 100.0
	if y < 4.0:
		y = tower.y + 60.0          # 太靠屏幕顶部则放到塔下方
	x = clampf(x, 4.0, game.width - total_w - 4.0)
	_row.position = Vector2(x, y)

	for entry in LABELS:
		var mode: String = entry[0]
		var b: Button = _buttons[mode]
		var active: bool = tower.targeting == mode
		b.add_theme_stylebox_override("normal",
				_style(Config.COLOR_CARD_SEL if active else Config.COLOR_BUTTON))
		# 亮黄底上用深色文字，对比度更清晰
		b.add_theme_color_override("font_color",
				Color8(30, 30, 30) if active else Config.COLOR_TEXT)
