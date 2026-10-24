class_name GameScreen
extends Node2D
## 游戏画面调度器 —— 移植自 main.py 的 App 中「游戏状态」那部分
##
## 职责：
## 1. 持有一个 Game 节点，驱动固定步长主循环（对应 main.py 的 accumulator 循环）；
## 2. 分发游戏内的键鼠输入（对应 handle_game_event / handle_game_click / handle_game_right_click）；
## 3. 每帧刷新各 UI 控件。
##
## 界面级的状态（主菜单/选关/暂停菜单/结算）不在这里，由 main.gd 的状态机负责，
## 本节点只通过信号上报。

## 请求退出本局；grant_gold 表示是否发放通关金币（只有胜利才发）
signal exit_requested(grant_gold: bool)
## 请求打开暂停菜单（ESC）
signal pause_requested

@onready var board: Board = $Board
@onready var game: Game = $Game
@onready var fx_layer: FxLayer = $FxLayer
@onready var hud: Hud = $UI/Hud
@onready var tower_bar: TowerBar = $UI/TowerBar
@onready var card_panel: CardPanel = $UI/CardPanel
@onready var collection_panel: CollectionPanel = $UI/CollectionPanel
@onready var recycle_dialog: RecycleDialog = $UI/RecycleDialog

## 由暂停菜单置位：为 true 时冻结游戏推进（ESC 菜单与空格暂停是两回事）
var menu_paused := false

var _targeting: TargetingSelector = null
var _result_label: Label = null
var _result_catcher: Control = null
var _accumulator := 0.0


func _ready() -> void:
	# 索敌切换按钮（位置依赖选中塔，独立成层便于覆盖在棋盘之上）
	_targeting = TargetingSelector.new()
	_targeting.name = "TargetingSelector"
	$UI.add_child(_targeting)

	# 胜负提示：中央文字 + 全屏点击捕获
	_result_catcher = Control.new()
	_result_catcher.name = "ResultCatcher"
	_result_catcher.anchor_right = 1.0
	_result_catcher.anchor_bottom = 1.0
	_result_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_catcher.visible = false
	$UI.add_child(_result_catcher)

	_result_label = Label.new()
	_result_label.name = "ResultText"
	_result_label.anchor_left = 0.5
	_result_label.anchor_top = 0.5
	_result_label.anchor_right = 0.5
	_result_label.anchor_bottom = 0.5
	_result_label.offset_left = -300.0
	_result_label.offset_top = -60.0
	_result_label.offset_right = 300.0
	_result_label.offset_bottom = 60.0
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 52)
	_result_label.add_theme_color_override("font_color", Color8(255, 220, 120))
	_result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_catcher.add_child(_result_label)


## 显示/隐藏整个游戏画面（棋盘、实体、特效、UI）。
##
## 必须同时设 UI 这个 CanvasLayer 的 visible：CanvasLayer 不是 CanvasItem，
## 父节点的 visible = false 不会传到它身上 —— 只设自身的话，UI 会残留并盖住菜单。
func set_content_visible(v: bool) -> void:
	visible = v
	var ui := get_node_or_null("UI")
	if ui != null:
		(ui as CanvasLayer).visible = v


## 用地图数据与存档开局。必须在节点入树后调用。
func setup(map_data: Dictionary, save_data: Dictionary) -> void:
	game.setup(map_data, save_data)
	board.setup(game)
	fx_layer.setup(game)
	hud.game = game
	tower_bar.setup(game)
	card_panel.setup(game)
	collection_panel.setup(game)
	recycle_dialog.setup(game)
	_targeting.setup(game)

	# UI 交互一律通过信号回流到本节点，UI 自己不碰游戏逻辑
	hud.collection_toggled.connect(_on_collection_toggled)
	hud.speed_pressed.connect(_on_speed_pressed)
	hud.pause_pressed.connect(_on_pause_pressed)
	tower_bar.tower_selected.connect(_on_tower_selected)
	card_panel.card_clicked.connect(_on_card_clicked)
	card_panel.refresh_clicked.connect(_on_refresh_clicked)
	card_panel.skip_clicked.connect(_on_skip_clicked)
	recycle_dialog.confirmed.connect(_on_recycle_confirmed)
	recycle_dialog.cancelled.connect(_on_recycle_cancelled)
	_targeting.mode_selected.connect(_on_targeting_mode_selected)
	_result_catcher.gui_input.connect(_on_result_input)

	_accumulator = 0.0


## 固定步长主循环 —— 与 Python 版 main.py 的 accumulator 逻辑一一对应。
##
## 卡牌面板倒计时用真实 delta（不受快进倍率影响）；
## 游戏逻辑按 FIXED_DT 推进，快进时一帧内连续推进 game_speed 次。
func _process(delta: float) -> void:
	if game == null or game.map_data.is_empty():
		return
	if not game.paused and not menu_paused:
		var dt := minf(delta, Config.MAX_FRAME_DT)
		game.update_card_timer(dt)
		_accumulator += dt
		while _accumulator >= Config.FIXED_DT:
			for _i in range(game.game_speed):
				game.tick(Config.FIXED_DT)
			_accumulator -= Config.FIXED_DT
	_refresh_ui()


## 每帧刷新所有 UI 控件与放置预览。
func _refresh_ui() -> void:
	hud.refresh()
	tower_bar.refresh()
	card_panel.refresh()
	collection_panel.refresh()
	recycle_dialog.refresh()
	_targeting.refresh()
	_update_preview()
	_update_result_overlay()


func _update_preview() -> void:
	if game.selected_build_tower == null:
		board.update_preview("", Vector2.ZERO, false)
		return
	var pos := get_global_mouse_position()
	var data = GameData.get_tower(game.selected_build_tower)
	var cost := int(data.get("build_cost", 50)) if data != null else 0
	var valid: bool = game.can_place_tower(pos.x, pos.y) and game.points >= cost
	board.update_preview(game.selected_build_tower, pos, valid)


func _update_result_overlay() -> void:
	var win := game.state == Game.STATE_WIN
	var lose := game.state == Game.STATE_LOSE
	_result_catcher.visible = win or lose
	if win:
		_result_label.text = "胜利！"
	elif lose:
		_result_label.text = "失败"


# ---------- 输入 ----------
## 只处理游戏世界里的输入；UI 控件的点击已被各自控件消费，不会走到这里。
func _unhandled_input(event: InputEvent) -> void:
	if game == null or game.map_data.is_empty():
		return
	if menu_paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click()


func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ESCAPE:
			# 胜负已定：ESC 直接结算退出；否则打开暂停菜单
			if game.state == Game.STATE_WIN:
				exit_requested.emit(true)
			elif game.state == Game.STATE_LOSE:
				exit_requested.emit(false)
			else:
				pause_requested.emit()
		KEY_SPACE:
			# 空格：暂停/继续（与右上角按钮一致）
			if game.state == Game.STATE_BUILD or game.state == Game.STATE_COMBAT:
				game.paused = not game.paused
		KEY_R:
			game.show_all_ranges = not game.show_all_ranges


## 用这个哨兵表示「没传坐标，用真实鼠标位置」。
## 之所以让点击处理接受显式坐标：测试无法在 Godot 里设置鼠标位置，
## 不这样的话「点地面放塔」这条路径永远测不到（只能测到事件有没有到达）。
const USE_MOUSE_POS := Vector2.INF


## 游戏内左键：依次处理已获取卡牌面板、选塔、放置。
func _handle_left_click(click_pos: Vector2 = USE_MOUSE_POS) -> void:
	var pos := get_global_mouse_position() if click_pos == USE_MOUSE_POS else click_pos

	if game.state == Game.STATE_WIN or game.state == Game.STATE_LOSE:
		return                                   # 交给结算覆盖层处理

	# 已获取卡牌面板打开时：点到面板外即关闭（面板自身会吞掉内部点击）
	if game.show_collection:
		game.show_collection = false
		return

	# 点击已放置塔：选中显示其攻击范围与属性
	for t in game.towers:
		if pos.distance_to(t.position) <= t.radius + 4.0:
			game.selected_tower = t
			game.selected_build_tower = null
			return
	game.selected_tower = null

	# 放置模式：左键放置，成功后退出放置（避免连续放置）
	if game.selected_build_tower != null:
		if game.spawn_tower(game.selected_build_tower, pos.x, pos.y):
			game.selected_build_tower = null


## 游戏内右键：取消放置模式，或对已放置塔弹出回收确认。
func _handle_right_click(click_pos: Vector2 = USE_MOUSE_POS) -> void:
	if game.state != Game.STATE_BUILD and game.state != Game.STATE_COMBAT:
		return
	var pos := get_global_mouse_position() if click_pos == USE_MOUSE_POS else click_pos

	if game.selected_build_tower != null:
		game.selected_build_tower = null        # 放置模式中：右键取消选择
		return

	for t in game.towers:
		if pos.distance_to(t.position) <= t.radius + 4.0:
			game.recycle_target = t             # 弹出回收确认
			game.selected_tower = null
			return
	game.selected_tower = null


func _on_result_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		exit_requested.emit(game.state == Game.STATE_WIN)


# ---------- 信号回调 ----------
func _on_collection_toggled() -> void:
	if game.state == Game.STATE_BUILD or game.state == Game.STATE_COMBAT:
		Audio.play_sound("button_click")
		game.show_collection = not game.show_collection


func _on_speed_pressed() -> void:
	Audio.play_sound("button_click")
	var speeds: Array = Config.GAME_SPEEDS
	var idx: int = speeds.find(game.game_speed)
	if idx < 0:
		idx = 0
	game.game_speed = speeds[(idx + 1) % speeds.size()]


func _on_pause_pressed() -> void:
	Audio.play_sound("button_click")
	game.paused = not game.paused


func _on_tower_selected(tower_id: String) -> void:
	game.selected_build_tower = tower_id
	game.selected_tower = null


func _on_card_clicked(index: int) -> void:
	Audio.play_sound("card_click")
	game.buy_card(index)


func _on_refresh_clicked(index: int) -> void:
	Audio.play_sound("card_click")
	game.refresh_card(index)


func _on_skip_clicked() -> void:
	Audio.play_sound("button_click")
	game.skip_card_phase()


func _on_recycle_confirmed() -> void:
	Audio.play_sound("button_click")
	if game.recycle_target != null:
		game.recycle_tower(game.recycle_target)
	game.recycle_target = null


func _on_recycle_cancelled() -> void:
	game.recycle_target = null


func _on_targeting_mode_selected(tower, mode: String) -> void:
	tower.targeting = mode
