extends RefCounted
## 界面集成测试：把游戏画面真正跑起来
##
## 逻辑层测试（test_game）只覆盖 Game，碰不到任何 Control 控件。
## 这个用例实例化真实的 game_screen.tscn、连续推进 _process，
## 并走一遍 UI 交互路径，确保所有控件都能构建、刷新、响应而不报错。


func run(t) -> void:
	GameData.load_all()
	_test_screen_boots(t)
	_test_hud_and_bar(t)
	_test_endless_hud(t)
	_test_placement_flow(t)
	_test_card_panel(t)
	_test_collection_panel(t)
	_test_recycle_dialog(t)
	_test_speed_and_pause(t)
	_test_result_overlay(t)
	_test_menu_screens(t)
	_test_input_reaches_game(t)
	_test_layer_ordering(t)
	_test_entity_draw_order(t)
	t.finish()


func _make_screen(t) -> GameScreen:
	var screen: GameScreen = load("res://scenes/game_screen.tscn").instantiate()
	t.add_child(screen)
	screen.setup(GameData.preload_level("level_01"), GameData.default_save())
	return screen


func _drop(t, screen: Node) -> void:
	t.remove_child(screen)
	screen.free()


## 画面能构建并连续跑帧不报错（这一步能覆盖所有 UI 控件的 refresh）
func _test_screen_boots(t) -> void:
	var screen := _make_screen(t)
	# 刚创建时应处于建塔阶段（必须在跑帧之前断言：波间只有 2 秒）
	t.check("画面创建后处于建塔阶段", screen.game.state, "build")
	for _i in range(600):
		screen._process(1.0 / 60.0)
	# 波间 2 秒后应自动开波
	var entered_combat := false
	for _i in range(300):
		screen._process(1.0 / 60.0)
		if screen.game.state == "combat":
			entered_combat = true
			break
	t.check_true("波间结束后自动进入战斗", entered_combat)
	# 再跑一段，确认怪物出生、HUD 有内容
	for _i in range(300):
		screen._process(1.0 / 60.0)
	t.check_true("已有怪物出生", screen.game.monsters.size() > 0)
	t.check_false("HUD 点数文本非空", screen.hud._points_label.text.is_empty())
	t.check_false("HUD 波次文本非空", screen.hud._wave_label.text.is_empty())
	_drop(t, screen)


## 底部塔栏：卡片数量跟上塔池，点击卡片进入放置模式
func _test_hud_and_bar(t) -> void:
	var screen := _make_screen(t)
	screen._process(1.0 / 60.0)
	t.check("塔栏卡片数 = 塔池大小", screen.tower_bar._cards.size(), 4)
	t.check_true("四座塔的卡片都在",
			screen.tower_bar._cards.has("fire_mage_tower")
			and screen.tower_bar._cards.has("ice_mage_tower"))

	# 模拟点击火塔卡片
	screen._on_tower_selected("fire_mage_tower")
	screen._process(1.0 / 60.0)
	t.check("进入放置模式", screen.game.selected_build_tower, "fire_mage_tower")
	# 再刷新一帧，卡片高亮应生效且不报错
	screen.tower_bar.refresh()
	t.check_true("塔栏刷新不报错", true)

	# 普通关卡：金币与里程碑都不在局内显示
	# （一局只发一次，局内盯着它不动只会误导）
	t.check_false("普通关卡 HUD 不显示金币", screen.hud._gold_label.visible)
	t.check_false("普通关卡 HUD 不显示里程碑", screen.hud._milestone_label.visible)
	_drop(t, screen)


## 无尽模式：金币与里程碑进度在局内显示，里程碑文案跟着已过档位走
func _test_endless_hud(t) -> void:
	var screen: GameScreen = load("res://scenes/game_screen.tscn").instantiate()
	t.add_child(screen)
	screen.setup(GameData.preload_level("level_endless"), GameData.default_save())
	screen._process(1.0 / 60.0)

	t.check_true("无尽模式显示金币", screen.hud._gold_label.visible)
	t.check_true("无尽模式显示里程碑", screen.hud._milestone_label.visible)
	t.check("里程碑文案指向第 10 波", screen.hud._milestone_label.text,
			"里程碑: 第 10 波 +100（已获 0）")

	# 打到第 10 波：本局金币 = 每波 100 + 里程碑 100，文案指向下一档
	screen.game.wave_index = 9
	screen.game.finish_wave()
	screen._process(1.0 / 60.0)
	t.check("无尽 10 波后本局金币", screen.hud._gold_label.text, "本局金币: 200")
	t.check("里程碑文案指向第 20 波", screen.hud._milestone_label.text,
			"里程碑: 第 20 波 +200（已获 100）")

	# 打到第 20 波：再 +100 +200，累计里程碑 300
	screen.game.wave_index = 19
	screen.game.finish_wave()
	screen._process(1.0 / 60.0)
	t.check("无尽 20 波后本局金币", screen.hud._gold_label.text, "本局金币: 500")
	t.check("里程碑文案指向第 30 波", screen.hud._milestone_label.text,
			"里程碑: 第 30 波 +400（已获 300）")
	_drop(t, screen)


## 放置防塔的完整交互路径
func _test_placement_flow(t) -> void:
	var screen := _make_screen(t)
	var game := screen.game
	game.points = 1000

	# 找一个紧贴路径的可建位置
	var best := Vector2(-1, -1)
	var best_d := INF
	for gx in range(game.width / game.tile_size):
		for gy in range((game.height - Config.UI_HEIGHT) / game.tile_size):
			var px := gx * game.tile_size + game.tile_size / 2.0
			var py := gy * game.tile_size + game.tile_size / 2.0
			if not game.can_place_tower(px, py):
				continue
			var d: float = game._dist_to_path(gx, gy)
			if d < best_d:
				best_d = d
				best = Vector2(px, py)

	screen._on_tower_selected("fire_mage_tower")
	t.check("放置模式已进入", game.selected_build_tower, "fire_mage_tower")

	# 直接调 spawn_tower（等价于点击合法位置）
	var placed := game.spawn_tower("fire_mage_tower", best.x, best.y)
	t.check_true("放置成功", placed)
	t.check("场上 1 座塔", game.towers.size(), 1)
	game.selected_build_tower = null

	# 选中该塔 → 索敌按钮出现
	game.selected_tower = game.towers[0]
	screen._process(1.0 / 60.0)
	t.check_true("索敌按钮可见", screen._targeting._row.visible)
	t.check("选中态同步到塔节点", game.towers[0].selected, true)

	# 切换索敌策略
	screen._on_targeting_mode_selected(game.towers[0], "highest_hp")
	t.check("索敌策略已切换", game.towers[0].targeting, "highest_hp")

	# 取消选中
	game.selected_tower = null
	screen._process(1.0 / 60.0)
	t.check_false("取消选中后索敌按钮隐藏", screen._targeting._row.visible)
	_drop(t, screen)


## 找紧贴路径的可建位置（塔射程有限，必须靠近路径才打得到怪）
func _find_buildable_near(game: Game) -> Vector2:
	var best := Vector2(-1, -1)
	var best_d := INF
	for gx in range(game.width / game.tile_size):
		for gy in range((game.height - Config.UI_HEIGHT) / game.tile_size):
			var px := gx * game.tile_size + game.tile_size / 2.0
			var py := gy * game.tile_size + game.tile_size / 2.0
			if not game.can_place_tower(px, py):
				continue
			var d: float = game._dist_to_path(gx, gy)
			if d < best_d:
				best_d = d
				best = Vector2(px, py)
	return best


## 卡面上是否有「已购买」字样的 Label
func _card_has_sold_label(card: Control) -> bool:
	if card == null or not is_instance_valid(card):
		return false
	for c in card.get_children():
		if c is Label and (c as Label).text == "已购买":
			return true
	return false


## 直接往场上塞一座塔（不走过 spawn_tower 的位置校验，避免依赖地图几何）
func _force_tower(game: Game) -> Tower:
	var data: Dictionary = GameData.get_tower("fire_mage_tower")
	var tower: Tower = load("res://src/entities/tower.tscn").instantiate()
	game.add_child(tower)
	tower.setup("fire_mage_tower", data, 1, data["levels"][0], 200.0, 600.0, 150.0)
	game.towers.append(tower)
	return tower


## 卡牌面板：弹出、购买、刷新、跳过
func _test_card_panel(t) -> void:
	var screen := _make_screen(t)
	var game := screen.game
	game.start_card_phase()
	screen._process(1.0 / 60.0)
	t.check_true("卡牌面板已显示", screen.card_panel._root.visible)
	t.check("面板 3 张卡", screen.card_panel._cards.size(), 3)
	t.check("刷新按钮 3 个", screen.card_panel._refresh_btns.size(), 3)
	t.check_true("跳过按钮已创建", screen.card_panel._skip_btn != null)

	# 买第一张
	var sold_card_id = game.current_offers[0]
	var before: int = game.points
	screen._on_card_clicked(0)
	screen._process(1.0 / 60.0)
	t.check_true("购买后点数减少", game.points < before)
	t.check("第一张卡已置空", game.current_offers[0], null)
	# 已购的卡：卡面显示「已购买」，刷新按钮置灰
	t.check_true("买后卡面显示「已购买」", _card_has_sold_label(screen.card_panel._cards[0]))
	t.check("已购卡的刷新按钮被禁用", screen.card_panel._refresh_btns[0].disabled, true)
	t.check("已购卡的刷新按钮文案", screen.card_panel._refresh_btns[0].text, "已购买")

	# 回归：买过的那张卡再次出现在新一波面板里时，旧的「已购买」字样必须消失。
	# 之前清理卡面内容时靠「删名字以 Dyn 开头的节点」，而「已购买」Label 的名字
	# 是自动生成的，从来没被清掉，于是同一张卡再出现时带着旧字样（其实能买）。
	game._close_card_panel()
	screen._process(1.0 / 60.0)
	game.current_offers = [sold_card_id, "brass_water_damage", "brass_thunder_damage"]
	game.card_refreshed = [false, false, false]
	game.card_timer = game.card_duration
	screen._process(1.0 / 60.0)
	t.check("同一张卡再次出现", game.current_offers[0], sold_card_id)
	t.check_false("同卡再次出现时没有残留「已购买」字样",
			_card_has_sold_label(screen.card_panel._cards[0]))
	t.check_true("该卡可再次购买", screen.card_panel._cards[0] != null)
	# 重新出现后仍能买下（面板会把它置空）
	screen._on_card_clicked(0)
	screen._process(1.0 / 60.0)
	t.check("同一张卡可以再次买下", game.current_offers[0], null)

	# 刷新第二张
	if game.current_offers[1] != null:
		screen._on_refresh_clicked(1)
		screen._process(1.0 / 60.0)
		t.check("第二张卡已刷新", game.card_refreshed[1], true)

	# 跳过
	screen._on_skip_clicked()
	screen._process(1.0 / 60.0)
	t.check_almost("跳过后面板关闭", game.card_timer, 0.0)
	t.check_false("面板已隐藏", screen.card_panel._root.visible)
	_drop(t, screen)


## 已获取卡牌面板的开关与内容
func _test_collection_panel(t) -> void:
	var screen := _make_screen(t)
	var game := screen.game
	game.points = 1000
	game.start_card_phase()
	game.buy_card(0)
	screen._process(1.0 / 60.0)

	screen._on_collection_toggled()
	screen._process(1.0 / 60.0)
	t.check("面板已打开", game.show_collection, true)
	t.check_true("面板可见", screen.collection_panel._panel.visible)
	t.check_true("面板内有内容行", screen.collection_panel._vbox.get_child_count() > 0)

	# 再点一次关闭
	screen._on_collection_toggled()
	screen._process(1.0 / 60.0)
	t.check("面板已关闭", game.show_collection, false)
	t.check_false("面板不可见", screen.collection_panel._panel.visible)
	_drop(t, screen)


## 回收确认弹窗
func _test_recycle_dialog(t) -> void:
	var screen := _make_screen(t)
	var game := screen.game
	game.points = 1000
	_force_tower(game)

	game.recycle_target = game.towers[0]
	screen._process(1.0 / 60.0)
	t.check_true("回收弹窗可见", screen.recycle_dialog._panel.visible)
	t.check_true("遮罩可见", screen.recycle_dialog._dim.visible)

	# 确认回收
	var before: int = game.points
	screen._on_recycle_confirmed()
	screen._process(1.0 / 60.0)
	t.check("塔已移除", game.towers.size(), 0)
	t.check_true("点数已返还", game.points > before)
	t.check("回收目标已清空", game.recycle_target, null)
	t.check_false("弹窗已隐藏", screen.recycle_dialog._panel.visible)

	# 取消路径
	game.recycle_target = null
	screen._process(1.0 / 60.0)
	t.check_false("无目标时弹窗隐藏", screen.recycle_dialog._panel.visible)
	_drop(t, screen)


## 快进档位循环与空格暂停
func _test_speed_and_pause(t) -> void:
	var screen := _make_screen(t)
	var game := screen.game
	t.check("初始速度 1x", game.game_speed, 1)
	screen._on_speed_pressed()
	t.check("快进到 2x", game.game_speed, 2)
	screen._on_speed_pressed()
	t.check("快进到 4x", game.game_speed, 4)
	screen._on_speed_pressed()
	t.check("循环回 1x", game.game_speed, 1)

	# 暂停按钮
	screen._on_pause_pressed()
	t.check("已暂停", game.paused, true)
	# 暂停时不应推进逻辑
	var t_before: float = game.time
	for _i in range(60):
		screen._process(1.0 / 60.0)
	t.check_almost("暂停时逻辑时间不推进", game.time, t_before)
	screen._on_pause_pressed()
	t.check("已继续", game.paused, false)

	# 显示所有范围：应同步到每座塔节点（Game 的 setter 负责下发）
	var tower := _force_tower(game)
	game.show_all_ranges = true
	t.check("所有塔显示范围已下发", tower.show_range, true)
	game.show_all_ranges = false
	t.check("关闭后范围圈隐藏", tower.show_range, false)
	screen._process(1.0 / 60.0)
	_drop(t, screen)


## 胜负覆盖层
func _test_result_overlay(t) -> void:
	var screen := _make_screen(t)
	var game := screen.game
	screen._process(1.0 / 60.0)
	t.check_false("初始不显示结算层", screen._result_catcher.visible)

	game.state = Game.STATE_WIN
	screen._process(1.0 / 60.0)
	t.check_true("胜利时显示结算层", screen._result_catcher.visible)
	t.check("胜利文案", screen._result_label.text, "胜利！")

	game.state = Game.STATE_LOSE
	screen._process(1.0 / 60.0)
	t.check("失败文案", screen._result_label.text, "失败")
	_drop(t, screen)


## 五个外围界面都能构建与刷新
func _test_menu_screens(t) -> void:
	var main := Main.new()
	t.add_child(main)                     # _ready 会加载存档并构建所有界面
	t.check_true("主菜单已构建", main.get_screen(Main.STATE_MAIN_MENU) != null)
	t.check("初始状态为主菜单", main.state, Main.STATE_MAIN_MENU)

	for key in [Main.STATE_LEVEL_SELECT, Main.STATE_UPGRADE,
			Main.STATE_SETTINGS, Main.STATE_PAUSE]:
		main._show_state(key)
		t.check_true("%s 界面可见" % key, (main.get_screen(key) as Control).visible)
	main._show_state(Main.STATE_MAIN_MENU)

	# 选关界面的关卡列表
	var ls: LevelSelect = main.get_screen(Main.STATE_LEVEL_SELECT)
	main._show_state(Main.STATE_LEVEL_SELECT)
	t.check("选关列表条目数 = 关卡数", ls._list.get_child_count(),
			GameData.level_ids().size())

	# 升级界面的行数 = 塔数 + 1 行（城堡/点数并排）
	var up: UpgradeMenu = main.get_screen(Main.STATE_UPGRADE)
	main._show_state(Main.STATE_UPGRADE)
	t.check("升级列表条目数（4 塔 + 1 行属性）", up._list.get_child_count(), 5)

	# 设置界面控件就绪
	var st: SettingsMenu = main.get_screen(Main.STATE_SETTINGS)
	main.enter_settings(Main.STATE_MAIN_MENU)
	t.check_true("三档音量滑块就绪",
			st._volume != null and st._sfx != null and st._ui != null)
	t.check_true("帧率控件就绪", st._fps != null and st._fps_box != null)

	# 分辨率按钮必须与「当前显示器支持得起的档位」完全一致。
	# 无头模式下 DisplayServer.screen_get_size() 返回的是假值（比 720P 还小），
	# 所以这里只验证「按钮确实来自 available_resolutions」；
	# 那个函数本身在 test_config 里用 1080p/2K/4K/800x600/带鱼屏 等各种尺寸测过了。
	var screen_size := DisplayServer.screen_get_size()
	var supported: Array = Config.available_resolutions(screen_size)
	t.check("分辨率按钮数 = 显示器支持的档位数",
			st._resolution_btns.size(), supported.size())
	t.check_true("至少有一个分辨率可选", st._resolution_btns.size() >= 1)
	for i in st._resolution_btns.size():
		var size: Vector2i = st._resolution_btns[i][0]
		t.check_true("%d x %d 是合法档位" % [size.x, size.y],
				Config.is_valid_resolution(size))
		t.check_true("%d x %d 与可用档位列表一致" % [size.x, size.y],
				size == (supported[i]["size"] as Vector2i))

	# 窗口模式三选一
	t.check("窗口模式有 3 个按钮", st._window_mode_btns.size(), 3)
	var modes := []
	for entry in st._window_mode_btns:
		modes.append(str(entry[0]))
	t.check_true("包含全屏", modes.has(Config.WINDOW_MODE_FULLSCREEN))
	t.check_true("包含窗口", modes.has(Config.WINDOW_MODE_WINDOWED))
	t.check_true("包含无边框窗口", modes.has(Config.WINDOW_MODE_BORDERLESS))

	t.remove_child(main)
	main.free()


## 鼠标点击必须能穿过 Control 层到达游戏画面。
##
## 回归的 bug：Main 是铺满全屏的 Control，mouse_filter 默认 STOP，
## 把整个屏幕的鼠标事件都吞了，于是「点地面放不了塔」。
## 这里用真实的输入管线验证 —— 合成一个左键事件 push 进 viewport，
## 如果被某个 Control 拦截，_unhandled_input 就不会执行。
func _test_input_reaches_game(t) -> void:
	var main := Main.new()
	t.add_child(main)
	main.enter_level("level_01")
	var screen: GameScreen = main._game_screen
	t.check("Main 不拦截鼠标事件", main.mouse_filter,
			Control.MOUSE_FILTER_IGNORE)

	# 选中一座塔；点击空地面时处理器会把 selected_tower 清空，
	# 用它作为「事件确实到达了游戏」的观测点。
	var tower := _force_tower(screen.game)
	tower.position = Vector2(1800.0, 100.0)     # 远离鼠标默认位置，避免被判定为点中
	screen.game.selected_tower = tower
	screen.game.selected_build_tower = null

	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(900.0, 400.0)
	t.get_viewport().push_input(ev, true)
	t.check("左键事件到达游戏画面（选中被清空）", screen.game.selected_tower, null)

	# 右键同理：放置模式下右键应取消放置
	screen.game.selected_build_tower = "fire_mage_tower"
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_RIGHT
	ev2.pressed = true
	ev2.position = Vector2(900.0, 400.0)
	t.get_viewport().push_input(ev2, true)
	t.check("右键事件到达游戏画面（取消放置）",
			screen.game.selected_build_tower, null)

	# 端到端：选中塔类型 → 点击合法地面 → 塔真的建起来。
	# 直接调点击处理并传入显式坐标（Godot 无法在测试里设置鼠标位置）。
	main._show_state(Main.STATE_GAME)
	var game := screen.game
	game.points = 10000
	game.selected_build_tower = null
	var spot := _find_buildable_near(game)
	t.check_true("找到紧贴路径的可建位置", spot.x >= 0)
	screen._on_tower_selected("fire_mage_tower")
	t.check("已进入放置模式", game.selected_build_tower, "fire_mage_tower")
	var towers_before: int = game.towers.size()
	screen._handle_left_click(spot)
	t.check("点击地面建起了塔", game.towers.size(), towers_before + 1)
	t.check("放置成功后退出放置模式", game.selected_build_tower, null)

	# 点到不合法位置（路径上）不应建塔，且不退出放置模式
	game.selected_build_tower = "fire_mage_tower"
	var on_path: Vector2 = game.waypoints[0]
	var count_before: int = game.towers.size()
	screen._handle_left_click(on_path)
	t.check("点到路径上不建塔", game.towers.size(), count_before)
	t.check("失败后仍留在放置模式", game.selected_build_tower, "fire_mage_tower")

	t.remove_child(main)
	main.free()


## 层级：三层的绘制顺序必须是
##   游戏世界（默认画布） < 游戏 UI（CanvasLayer 层 1） < 外围菜单（CanvasLayer 层 10）
##
## 这里踩过两个方向的坑：
## - 游戏画面曾是 Main 的最后一个子节点，靠后的兄弟画在上面 → 棋盘盖住暂停菜单；
## - 菜单直接挂在 Main 下（层 0），而游戏 UI 在自己的 CanvasLayer（层 1）上
##   → 卡牌面板反过来盖住暂停菜单。
func _test_layer_ordering(t) -> void:
	var main := Main.new()
	t.add_child(main)
	main.enter_level("level_01")
	var screen: GameScreen = main._game_screen

	var menu_layer := main.get_node_or_null("MenuLayer") as CanvasLayer
	var ui_layer := screen.get_node_or_null("UI") as CanvasLayer
	t.check_true("菜单层存在", menu_layer != null)
	t.check_true("游戏 UI 层存在", ui_layer != null)
	if menu_layer == null or ui_layer == null:
		t.remove_child(main)
		main.free()
		return
	t.check_true("菜单层号高于游戏 UI 层（暂停菜单不会被卡牌面板压住）",
			menu_layer.layer > ui_layer.layer)
	t.check_true("菜单层号高于世界层（棋盘不会盖住菜单）", menu_layer.layer > 0)
	t.check_true("各个界面都挂在菜单层上",
			main.get_screen(Main.STATE_PAUSE).get_parent() == menu_layer)
	t.check_true("游戏画面不挂在菜单层上（否则会跟着菜单一起被隐藏）",
			screen.get_parent() == main)

	# 非游戏状态下，游戏画面连同它的 UI 一起隐藏。
	# UI 挂在 CanvasLayer 上，而 CanvasLayer 不是 CanvasItem ——
	# 只设父节点的 visible 传不到它身上，必须显式同步（见 set_content_visible）。
	var ui: CanvasLayer = screen.get_node("UI")
	var hud: Control = screen.get_node("UI/Hud")
	t.check_true("游戏中 UI 可见", hud.is_visible_in_tree())
	main._show_state(Main.STATE_PAUSE)
	t.check_true("暂停时 UI 仍可见（被菜单盖住）", hud.is_visible_in_tree())
	main._show_state(Main.STATE_SETTINGS)
	t.check_false("设置界面下 UI 层已隐藏", ui.visible)
	t.check_false("设置界面下 HUD 不可见", hud.is_visible_in_tree())
	t.check_false("设置界面下游戏画面已隐藏", screen.visible)
	main._show_state(Main.STATE_MAIN_MENU)
	t.check_false("回主菜单后 UI 层已隐藏", ui.visible)

	t.remove_child(main)
	main.free()


## 实体不得有负 z_index 的子节点。
##
## 回归的 bug：z_index 在 Godot 里是整个画布内的全局排序键，不是相对父节点。
## 之前给怪物的 Sprite 子节点设了 z_index = -1，结果整只怪被排到棋盘之后，
## 沉到路径底下。现在实体一律自绘，z_index 全为 0。
func _test_entity_draw_order(t) -> void:
	var screen := _make_screen(t)
	var game := screen.game
	game.points = 100000
	game.start_wave()
	for _i in range(120):
		screen._process(1.0 / 60.0)
	t.check_true("已有怪物", game.monsters.size() > 0)

	var bad := 0
	for m in game.monsters:
		if m.z_index < 0:
			bad += 1
		for c in m.get_children():
			if c is CanvasItem and (c as CanvasItem).z_index < 0:
				bad += 1
	# 也覆盖塔与投射物
	_force_tower(game)
	for tower in game.towers:
		if tower.z_index < 0:
			bad += 1
		for c in tower.get_children():
			if c is CanvasItem and (c as CanvasItem).z_index < 0:
				bad += 1
	for p in game.projectiles:
		if p.z_index < 0:
			bad += 1
	t.check("没有负 z_index 的实体（不会被排到棋盘之后）", bad, 0)
	_drop(t, screen)
