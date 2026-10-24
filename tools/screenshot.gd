extends Node
## 开发用截图工具：把几个关键画面渲染成 PNG，方便确认真实观感。
##
## 无头测试只能验证逻辑，验证不了「长得对不对」。这个工具把游戏真的渲染出来存成图。
##
## 用法：
##   godot --path <项目> res://tools/screenshot.tscn -- <输出目录>
## 注意：--headless 下渲染器是 dummy，截出来是黑的，必须有显示环境。

const SHOTS := "user://screenshots"

var main: Main = null
var out_dir := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path(SHOTS)
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("[screenshot] 输出目录: ", out_dir)
	# 打印显示器信息，便于确认分辨率档位过滤是否符合预期
	var screen_size := DisplayServer.screen_get_size()
	print("[screenshot] 屏幕尺寸: %d x %d" % [screen_size.x, screen_size.y])
	var labels := []
	for preset in Config.available_resolutions(screen_size):
		labels.append(str(preset["label"]))
	print("[screenshot] 可选分辨率档位: ", ", ".join(labels))

	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _settle(5)
	await _shot("01_main_menu")

	# 选关
	main._show_state(Main.STATE_LEVEL_SELECT)
	await _settle(3)
	await _shot("02_level_select")

	# 升级
	main.save_data["gold"] = 5000
	main._show_state(Main.STATE_UPGRADE)
	await _settle(3)
	await _shot("03_upgrade")

	# 设置
	main.enter_settings(Main.STATE_MAIN_MENU)
	await _settle(3)
	await _shot("04_settings")

	# 进关卡，建几座塔，跑到有怪的时候
	main.enter_level("level_01")
	await _settle(3)
	var screen: GameScreen = main._game_screen
	screen.game.points = 5000
	var spots := _find_spots(screen.game, 3)
	for i in spots.size():
		screen.game.spawn_tower(["fire_mage_tower", "thunder_mage_tower",
				"ice_mage_tower"][i], spots[i].x, spots[i].y)
	await _settle(3)
	await _shot("05_game_build_phase")

	# 快进到战斗中期：有怪、有伤害飘字、有特效
	screen.game.game_speed = 4
	for _i in range(420):
		await get_tree().process_frame
	await _shot("06_game_combat")

	# 卡牌面板
	screen.game.start_card_phase()
	await _settle(5)
	await _shot("07_card_panel")

	# 已获取卡牌
	if not screen.game.current_offers.is_empty():
		screen.game.buy_card(0)
	screen.game.show_collection = true
	await _settle(5)
	await _shot("08_collection")

	# 暂停菜单（应当盖在棋盘与游戏 UI 之上）。走真实的 ESC 路径，
	# 这样会连带触发「收起游戏内浮层」的处理，跟玩家实际操作一致。
	screen.pause_requested.emit()
	await _settle(3)
	await _shot("09_pause")

	# 从暂停进设置：游戏画面与它的 UI 都必须隐藏，不能串到设置界面上
	main.enter_settings(Main.STATE_PAUSE)
	await _settle(3)
	await _shot("10_settings_from_pause")
	main.cancel_settings()
	await _settle(2)

	# 退出本局回主菜单：棋盘不能残留在菜单之上
	main._show_state(Main.STATE_GAME)
	await _settle(2)
	main._on_game_exit(false)
	await _settle(5)
	await _shot("11_after_exit_to_menu")

	print("[screenshot] 完成")
	get_tree().quit()


## 找几个紧贴路径的可建位置。
func _find_spots(game: Game, count: int) -> Array:
	var candidates := []
	for gx in range(game.width / game.tile_size):
		for gy in range((game.height - Config.UI_HEIGHT) / game.tile_size):
			var px := gx * game.tile_size + game.tile_size / 2.0
			var py := gy * game.tile_size + game.tile_size / 2.0
			if game.can_place_tower(px, py):
				candidates.append([game._dist_to_path(gx, gy), Vector2(px, py)])
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	# 跳过最靠前的几个（它们往往挤在一起），取分散一些的位置
	var step := maxi(1, candidates.size() / maxi(1, count))
	for i in range(count):
		var idx := mini(i * step, candidates.size() - 1)
		if idx >= 0:
			out.append(candidates[idx][1])
	return out


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _shot(name: String) -> void:
	# 等一帧渲染完成再抓，否则抓到的是上一帧
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	var err := img.save_png(path)
	print("[screenshot] %s -> %s" % ["OK" if err == OK else "FAIL(%d)" % err, path])
