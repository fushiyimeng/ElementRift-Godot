class_name Main
extends Control
## 主程序与状态机 —— 移植自 main.py 的 App
##
## 维护 主菜单/选关/游戏/暂停/设置/升级 六个界面之间的切换、存档读写与显示设置。
## 各界面本身是独立的 Control 子类（src/ui/ 下），只通过信号与本节点交互。

const STATE_MAIN_MENU := "MAIN_MENU"
const STATE_LEVEL_SELECT := "LEVEL_SELECT"
const STATE_GAME := "GAME"
const STATE_PAUSE := "PAUSE"
const STATE_SETTINGS := "SETTINGS"
const STATE_UPGRADE := "UPGRADE"

const GAME_SCREEN_SCENE := preload("res://scenes/game_screen.tscn")

## 菜单层：所有外围界面都挂在这一层，层号高于游戏画面自己的 UI 层（1）。
##
## 为什么需要它：游戏画面的 UI（HUD/卡牌面板/塔栏）挂在自己的 CanvasLayer（层 1）上，
## 而 CanvasLayer 的绘制顺序由层号决定，不是树顺序。菜单若直接挂在 Main 下（层 0），
## 就会被游戏 UI 盖住 —— 表现为「暂停菜单被卡牌面板压住」。
const MENU_LAYER := 10

var save_data := {}
var state := STATE_MAIN_MENU

var _screens := {}                 ## {state: Control}
var _menu_layer: CanvasLayer = null
var _game_screen: GameScreen = null
var _settings_return := STATE_MAIN_MENU
var _settings_draft = null         ## 设置草稿（进入设置时复制，保存才生效）


func _ready() -> void:
	# 关键：本节点是铺满全屏的 Control，而 Control 的 mouse_filter 默认是 STOP，
	# 会把整个屏幕的鼠标事件都吞掉，游戏画面的 _unhandled_input 永远收不到点击
	# （表现为「点地面放不了塔」）。设为 IGNORE 后自身不拦截，但各个菜单/按钮
	# 仍是独立的 Control，照常接收点击。
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	GameData.load_all()
	save_data = GameData.load_save()
	_apply_audio_settings()
	_apply_display_settings()

	# 所有外围界面挂在一个高层号的 CanvasLayer 上，保证画在游戏 UI 之上
	_menu_layer = CanvasLayer.new()
	_menu_layer.name = "MenuLayer"
	_menu_layer.layer = MENU_LAYER
	add_child(_menu_layer)

	# 各界面构建一次，之后靠显隐切换（对应 Python 版每个界面重画的做法）
	_add_screen(STATE_MAIN_MENU, MainMenu.new())
	_add_screen(STATE_LEVEL_SELECT, LevelSelect.new())
	_add_screen(STATE_UPGRADE, UpgradeMenu.new())
	_add_screen(STATE_SETTINGS, SettingsMenu.new())
	_add_screen(STATE_PAUSE, PauseMenu.new())

	for s in _screens.values():
		s.setup(self)

	_show_state(STATE_MAIN_MENU)
	Audio.play_music("main_menu")


func _add_screen(key: String, screen: Control) -> void:
	screen.name = key
	screen.anchor_right = 1.0
	screen.anchor_bottom = 1.0
	_menu_layer.add_child(screen)
	_screens[key] = screen


# ---------- 状态切换 ----------
func _show_state(new_state: String) -> void:
	state = new_state
	for key in _screens:
		var screen: Control = _screens[key]
		screen.visible = (key == new_state)
		# 界面显示时刷新一次内容（升级/选关/设置的数据可能已经变了）
		if screen.visible and screen.has_method("refresh"):
			screen.call("refresh")
	if _game_screen != null:
		# 暂停菜单是覆盖层：游戏画面仍然可见，只是被菜单盖住。
		# 用 set_content_visible 而不是直接设 visible —— 它会把 UI 那个 CanvasLayer 也一起同步。
		_game_screen.set_content_visible(
				new_state == STATE_GAME or new_state == STATE_PAUSE)
		_game_screen.menu_paused = new_state == STATE_PAUSE


func get_screen(key: String) -> Control:
	return _screens.get(key)


## 保存并落盘。
func persist_save() -> void:
	GameData.write_save(save_data)


## 进入某关卡：创建游戏画面。
func enter_level(map_id: String) -> void:
	var map_data = GameData.preload_level(map_id)
	if map_data == null:
		return
	if _game_screen != null:
		_game_screen.queue_free()
		_game_screen = null
	_game_screen = GAME_SCREEN_SCENE.instantiate()
	add_child(_game_screen)
	# 关键：Godot 里靠后的兄弟节点画在上面。菜单界面是先建好的，
	# 游戏画面后加会成为最后一个子节点，于是棋盘会盖住暂停菜单/设置界面。
	# 把游戏画面挪到最前（索引 0），它就一直画在所有菜单之下。
	move_child(_game_screen, 0)
	_game_screen.exit_requested.connect(_on_game_exit)
	_game_screen.pause_requested.connect(func():
		# 进暂停前收掉游戏内的浮层（已获取卡牌面板、回收确认），
		# 否则它们会和暂停菜单叠在一起，看起来像画错了
		_game_screen.game.show_collection = false
		_game_screen.game.recycle_target = null
		_show_state(STATE_PAUSE))
	_game_screen.setup(map_data, save_data)
	_show_state(STATE_GAME)
	Audio.play_music(map_id)


## 退出本局：结算存档、释放游戏画面、回主菜单。
func _on_game_exit(grant_gold: bool) -> void:
	if _game_screen != null:
		save_data = _game_screen.game.finalize_save(grant_gold)
		# 先立刻隐藏再 queue_free：queue_free 延迟到帧末才生效，
		# 这一帧里游戏画面仍在树上且可见，而菜单界面是透明的（只有按钮和标题），
		# 棋盘会从菜单底下透出来闪一下。
		_game_screen.set_content_visible(false)
		_game_screen.queue_free()
		_game_screen = null
	persist_save()
	_apply_display_settings()
	_show_state(STATE_MAIN_MENU)
	Audio.play_music("main_menu")


func quit_game() -> void:
	# 与 Python 版一致：只有胜利才发放本局金币
	var grant := _game_screen != null and _game_screen.game.state == Game.STATE_WIN
	if _game_screen != null:
		save_data = _game_screen.game.finalize_save(grant)
	persist_save()
	get_tree().quit()


# ---------- 显示与音频设置 ----------
func _apply_audio_settings() -> void:
	var settings: Dictionary = save_data.get("settings", {})
	Audio.set_volumes(
			float(settings.get("volume", 1.0)),    # 音乐
			float(settings.get("sfx", 1.0)),       # 战斗音效
			float(settings.get("ui", 1.0)))        # 界面音效


func _apply_display_settings() -> void:
	var settings: Dictionary = save_data.get("settings", {})
	Engine.max_fps = int(settings.get("fps", Config.FPS_MIN))

	# 分辨率：存档里的档位可能来自更大屏幕的机器（换显示器、存档被拷过来），
	# 直接按它开窗会超出屏幕范围，所以按当前显示器支持的范围夹一下，夹过就写回存档。
	var screen_size := DisplayServer.screen_get_size()
	var res := resolution_from(settings)
	var clamped: Vector2i = Config.clamp_resolution(res, screen_size)
	if clamped != res:
		settings["resolution"] = [clamped.x, clamped.y]
		persist_save()

	_apply_window_mode(str(settings.get("window_mode", Config.WINDOW_MODE_WINDOWED)), clamped)


## 设置界面的即时预览：按草稿应用显示设置，但尚未保存。
##
## 显示设置必须即时可见才有意义（选了个分辨率却看不到效果没法判断），
## 所以改动即刻生效；点「返回」时 cancel_settings 会按存档重新应用一次还原回去。
func preview_display() -> void:
	var draft := get_settings_draft()
	var screen_size := DisplayServer.screen_get_size()
	_apply_window_mode(str(draft.get("window_mode", Config.WINDOW_MODE_WINDOWED)),
			Config.clamp_resolution(resolution_from(draft), screen_size))


## 从设置字典里取出分辨率（数组形式存储，便于 JSON 序列化）。
## 设置界面也用它，所以是公开的。
func resolution_from(settings: Dictionary) -> Vector2i:
	var res = settings.get("resolution", [])
	if res is Array and res.size() == 2:
		return Vector2i(int(res[0]), int(res[1]))
	return Config.DEFAULT_RESOLUTION


## 应用窗口模式：全屏 / 窗口 / 无边框窗口。
##
## 只执行「与当前状态不同」的操作（具体该做哪些由 Config.window_ops 决定）。
## 之前是无条件先切窗口态再切全屏 —— 已经全屏时也走一次往返，画面会闪一下。
## 这个函数在「设置里点返回」和「游戏内退出本局」时都会调到，所以闪屏在那两处都出现。
func _apply_window_mode(mode: String, size: Vector2i = Vector2i.ZERO) -> void:
	var is_fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	var is_borderless := DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)

	for op in Config.window_ops(is_fullscreen, is_borderless, mode):
		match op:
			"borderless_off":
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			"borderless_on":
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			"fullscreen_on":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			"fullscreen_off":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	# 窗口态下按目标分辨率调整窗口尺寸。尺寸已经对就不动 ——
	# 重复设同尺寸也会触发一次 resize，同样会闪。
	if mode != Config.WINDOW_MODE_FULLSCREEN and size != Vector2i.ZERO \
			and DisplayServer.window_get_size() != size:
		DisplayServer.window_set_size(size)


# ---------- 设置草稿 ----------
## 进入设置：复制一份草稿，所有修改先落在草稿上，保存才生效。
func enter_settings(return_state: String) -> void:
	_settings_draft = save_data.get("settings", {}).duplicate(true)
	_settings_return = return_state
	_show_state(STATE_SETTINGS)


func get_settings_draft() -> Dictionary:
	if _settings_draft == null:
		_settings_draft = save_data.get("settings", {}).duplicate(true)
	return _settings_draft


## 保存草稿：写回存档、写盘、应用显示与音频。
func apply_settings() -> void:
	# GDScript 没有 setdefault，手动补键
	if not save_data.has("settings"):
		save_data["settings"] = {}
	var settings: Dictionary = save_data["settings"]
	settings.merge(get_settings_draft(), true)
	_settings_draft = null
	persist_save()
	_apply_display_settings()
	_apply_audio_settings()
	_show_state(_settings_return)


## 放弃草稿：不落盘，并把预览改过的显示设置还原回存档里的值。
func cancel_settings() -> void:
	_settings_draft = null
	_apply_display_settings()
	_show_state(_settings_return)


# ---------- 升级 ----------
func upgrade_cost_text(level: int) -> String:
	return "%d金" % Config.upgrade_cost(level)


func try_upgrade_tower(tower_id: String) -> bool:
	var data = GameData.get_tower(tower_id)
	if data == null:
		return false
	var levels: Array = data.get("levels", [])
	if not save_data.has("tower_levels"):
		save_data["tower_levels"] = {}
	var levels_map: Dictionary = save_data["tower_levels"]
	var cur := int(levels_map.get(tower_id, 1))
	if cur >= levels.size():
		return false                              # 已满级
	var cost := Config.upgrade_cost(cur)
	if int(save_data.get("gold", 0)) < cost:
		return false                              # 金币不够
	save_data["gold"] = int(save_data["gold"]) - cost
	levels_map[tower_id] = cur + 1
	persist_save()
	Audio.play_sound("upgrade")
	return true


## 升级城堡生命 / 初始点数。kind 为 "castle" 或 "points"。
func try_upgrade_stat(kind: String) -> bool:
	var level_key := "castle_hp_level" if kind == "castle" else "initial_points_level"
	var max_level := Config.CASTLE_HP_MAX_LEVEL if kind == "castle" \
			else Config.INITIAL_POINTS_MAX_LEVEL
	var cur := int(save_data.get(level_key, 1))
	if cur >= max_level:
		return false
	var cost := Config.upgrade_cost(cur)
	if int(save_data.get("gold", 0)) < cost:
		return false
	save_data["gold"] = int(save_data["gold"]) - cost
	save_data[level_key] = cur + 1
	persist_save()
	Audio.play_sound("upgrade")
	return true
