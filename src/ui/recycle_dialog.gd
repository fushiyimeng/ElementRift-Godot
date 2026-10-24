class_name RecycleDialog
extends Control
## 回收确认弹窗（模态）—— 移植自 renderer.py 的 _draw_recycle_prompt
##
## 右键点已放置的塔弹出，确认后按比例返还点数。

signal confirmed
signal cancelled

const PANEL_SIZE := Vector2(380, 180)

var game: Game = null
var _dim: ColorRect = null
var _panel: PanelContainer = null
var _name_label: Label = null
var _info_label: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 全屏半透明遮罩：吞掉点击，避免误操作底下的棋盘
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0, 0, 0, 0.63)
	_dim.anchor_right = 1.0
	_dim.anchor_bottom = 1.0
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -PANEL_SIZE.x / 2.0
	_panel.offset_top = -PANEL_SIZE.y / 2.0
	_panel.offset_right = PANEL_SIZE.x / 2.0
	_panel.offset_bottom = PANEL_SIZE.y / 2.0
	_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(40, 44, 60)
	sb.set_corner_radius_all(10)
	sb.border_color = Color8(120, 120, 140)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "回收防御塔"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color8(255, 225, 130))
	vbox.add_child(title)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 17)
	vbox.add_child(_name_label)

	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 17)
	_info_label.add_theme_color_override("font_color", Config.COLOR_MONEY_POINTS)
	vbox.add_child(_info_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	vbox.add_child(buttons)
	buttons.add_child(_make_button("回收", Color8(60, 140, 90),
			func(): confirmed.emit()))
	buttons.add_child(_make_button("取消", Color8(90, 90, 100),
			func(): cancelled.emit()))


func _make_button(text: String, bg: Color, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(140, 42)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.2)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(on_press)
	return b


## 点遮罩空白处 = 取消
func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		cancelled.emit()


func setup(p_game: Game) -> void:
	game = p_game


func refresh() -> void:
	if game == null or _panel == null:
		return
	var tower = game.recycle_target
	var show := tower != null and (game.state == Game.STATE_BUILD
			or game.state == Game.STATE_COMBAT)
	_panel.visible = show
	_dim.visible = show
	if not show:
		return
	_name_label.text = "%s  Lv.%d" % [tower.display_name, tower.level]
	var refund := int(tower.build_cost * Config.TOWER_RECYCLE_RATIO)
	_info_label.text = "返还 %d 点数" % refund
