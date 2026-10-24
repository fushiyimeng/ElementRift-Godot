extends RefCounted
## 存档与金币结算流程 —— 移植自 tools/test_new_features.py
##
## 这些是「金币什么时候发」的精确行为规格，原版专门写了一个测试用例锁定它们。
## 测试会临时改写存档，结束后恢复原样。

var _backup := ""


func run(t) -> void:
	GameData.load_all()
	_backup = _read_save_text()
	# 从一份干净的存档开始，保证断言可预测
	_write_save(GameData.default_save())

	_test_resolution_migration(t)
	_test_settings_draft(t)
	_test_gold_rules(t)
	_test_escape_gold(t)
	_test_upgrade_spending(t)

	# 恢复原存档
	var f := FileAccess.open(GameData.SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(_backup)
		f.close()
	t.finish()


func _read_save_text() -> String:
	if not FileAccess.file_exists(GameData.SAVE_PATH):
		return ""
	return FileAccess.get_file_as_string(GameData.SAVE_PATH)


func _write_save(data: Dictionary) -> void:
	GameData.write_save(data)


func _read_save() -> Dictionary:
	var text := _read_save_text()
	var d = JSON.parse_string(text)
	return d if d is Dictionary else {}


func _new_main(t) -> Main:
	var main := Main.new()
	t.add_child(main)
	return main


func _drop(t, main: Main) -> void:
	t.remove_child(main)
	main.free()


## 旧存档里的非法分辨率应被纠正回默认值
func _test_resolution_migration(t) -> void:
	var bad := GameData.default_save()
	# 注意不能用 [1280,720]：「720P」现在是合法档位，测不出回退逻辑
	bad["settings"]["resolution"] = [1280, 1024]
	_write_save(bad)
	var loaded := GameData.load_save()
	t.check("非法分辨率回退默认", loaded["settings"]["resolution"],
			[Config.DEFAULT_RESOLUTION.x, Config.DEFAULT_RESOLUTION.y])
	# 合法档位应当被保留
	var good := GameData.default_save()
	good["settings"]["resolution"] = [1280, 720]
	_write_save(good)
	t.check("合法档位 720P 被保留",
			GameData.load_save()["settings"]["resolution"], [1280, 720])
	t.check("分辨率有 4 个档位", Config.RESOLUTION_PRESETS.size(), 4)
	t.check_true("默认分辨率是合法档位",
			Config.is_valid_resolution(Config.DEFAULT_RESOLUTION))


## 设置草稿：取消不生效，保存才生效
func _test_settings_draft(t) -> void:
	_write_save(GameData.default_save())
	var main := _new_main(t)
	var orig_fps := int(main.save_data["settings"]["fps"])

	# 取消：草稿被丢弃
	main.enter_settings(Main.STATE_MAIN_MENU)
	main.get_settings_draft()["fps"] = Config.FPS_MAX
	t.check("草稿已建立", int(main.get_settings_draft()["fps"]), Config.FPS_MAX)
	main.cancel_settings()
	t.check("取消后存档未变", int(main.save_data["settings"]["fps"]), orig_fps)
	t.check("取消后回到来源界面", main.state, Main.STATE_MAIN_MENU)
	t.check("取消后未落盘", int(_read_save()["settings"]["fps"]), orig_fps)

	# 保存：写盘并生效
	main.enter_settings(Main.STATE_MAIN_MENU)
	main.get_settings_draft()["fps"] = 300
	main.apply_settings()
	t.check("保存后内存生效", int(main.save_data["settings"]["fps"]), 300)
	t.check("保存后已落盘", int(_read_save()["settings"]["fps"]), 300)
	t.check("保存后回到来源界面", main.state, Main.STATE_MAIN_MENU)

	# 分辨率与窗口模式：草稿取消不生效、保存才生效
	var orig_res: Array = main.save_data["settings"]["resolution"].duplicate()
	main.enter_settings(Main.STATE_MAIN_MENU)
	main.get_settings_draft()["resolution"] = [1280, 720]
	main.get_settings_draft()["window_mode"] = Config.WINDOW_MODE_BORDERLESS
	main.cancel_settings()
	t.check("取消后分辨率未变", main.save_data["settings"]["resolution"], orig_res)
	t.check("取消后窗口模式未变",
			str(main.save_data["settings"]["window_mode"]), Config.WINDOW_MODE_WINDOWED)

	main.enter_settings(Main.STATE_MAIN_MENU)
	main.get_settings_draft()["window_mode"] = Config.WINDOW_MODE_BORDERLESS
	main.apply_settings()
	t.check("保存后窗口模式生效",
			str(main.save_data["settings"]["window_mode"]), Config.WINDOW_MODE_BORDERLESS)
	t.check("保存后窗口模式已落盘",
			str(_read_save()["settings"]["window_mode"]), Config.WINDOW_MODE_BORDERLESS)

	# 三档音量：草稿里都能改，保存后落到存档
	main.enter_settings(Main.STATE_MAIN_MENU)
	var draft := main.get_settings_draft()
	draft["volume"] = 0.2
	draft["sfx"] = 0.4
	draft["ui"] = 0.6
	main.apply_settings()
	var saved: Dictionary = _read_save()["settings"]
	t.check_almost("音乐音量已保存", float(saved["volume"]), 0.2)
	t.check_almost("音效音量已保存", float(saved["sfx"]), 0.4)
	t.check_almost("UI 音量已保存", float(saved["ui"]), 0.6)
	_drop(t, main)


## 金币发放规则：只有胜利才发
func _test_gold_rules(t) -> void:
	# 1) 中途退出不给金币
	_write_save(GameData.default_save())
	var main := _new_main(t)
	main.enter_level("level_01")
	main._game_screen.game.gold = 50
	var gold_before := int(_read_save()["gold"])
	main._on_game_exit(false)
	t.check("中途退出不给金币", int(_read_save()["gold"]), gold_before)
	t.check("退出后回到主菜单", main.state, Main.STATE_MAIN_MENU)
	t.check_true("游戏画面已释放", main._game_screen == null)

	# 2) 失败不给金币
	main.enter_level("level_01")
	main._game_screen.game.state = Game.STATE_LOSE
	main._game_screen.game.gold = 30
	gold_before = int(_read_save()["gold"])
	main._on_game_exit(false)
	t.check("失败不给金币", int(_read_save()["gold"]), gold_before)

	# 3) 胜利给金币
	main.enter_level("level_01")
	main._game_screen.game.state = Game.STATE_WIN
	main._game_screen.game.gold = 80
	gold_before = int(_read_save()["gold"])
	main._on_game_exit(true)
	t.check("胜利给金币", int(_read_save()["gold"]), gold_before + 80)

	# 4) 无尽模式失败也结算（无尽没有「通关」，破城即结算）
	main.enter_level("level_endless")
	main._game_screen.game.state = Game.STATE_LOSE
	main._game_screen.game.gold = 25
	gold_before = int(_read_save()["gold"])
	main._on_game_exit(false)
	t.check("无尽模式失败仍结算累计金币",
			int(_read_save()["gold"]), gold_before + 25)
	_drop(t, main)


## ESC 在胜负已定时直接结算
func _test_escape_gold(t) -> void:
	# 胜利态 ESC：发金币
	_write_save(GameData.default_save())
	var main := _new_main(t)
	main.enter_level("level_01")
	main._game_screen.game.state = Game.STATE_WIN
	main._game_screen.game.gold = 25
	var gold_before := int(_read_save()["gold"])
	main._game_screen._handle_key(_escape_event())
	t.check("胜利态 ESC 发金币", int(_read_save()["gold"]), gold_before + 25)
	t.check("胜利态 ESC 回主菜单", main.state, Main.STATE_MAIN_MENU)

	# 失败态 ESC：不发金币
	main.enter_level("level_01")
	main._game_screen.game.state = Game.STATE_LOSE
	main._game_screen.game.gold = 40
	gold_before = int(_read_save()["gold"])
	main._game_screen._handle_key(_escape_event())
	t.check("失败态 ESC 不发金币", int(_read_save()["gold"]), gold_before)
	t.check("失败态 ESC 回主菜单", main.state, Main.STATE_MAIN_MENU)

	# 进行中 ESC：打开暂停菜单，不结算
	main.enter_level("level_01")
	main._game_screen.game.gold = 15
	gold_before = int(_read_save()["gold"])
	main._game_screen._handle_key(_escape_event())
	t.check("进行中 ESC 打开暂停菜单", main.state, Main.STATE_PAUSE)
	t.check("进行中 ESC 不结算金币", int(_read_save()["gold"]), gold_before)
	t.check_true("游戏画面仍在", main._game_screen != null)
	_drop(t, main)


func _escape_event() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	return ev


## 升级消耗金币、等级提升、金币不足时拒绝
func _test_upgrade_spending(t) -> void:
	var save := GameData.default_save()
	save["gold"] = 1000
	_write_save(save)
	var main := _new_main(t)

	# 塔升级：1 级升 2 级花 100
	t.check_true("塔升级成功", main.try_upgrade_tower("fire_mage_tower"))
	t.check("塔等级 +1", int(main.save_data["tower_levels"]["fire_mage_tower"]), 2)
	t.check("金币扣 100", int(main.save_data["gold"]), 900)
	t.check("升级已落盘", int(_read_save()["tower_levels"]["fire_mage_tower"]), 2)

	# 城堡生命升级
	t.check_true("城堡生命升级成功", main.try_upgrade_stat("castle"))
	t.check("城堡等级 +1", int(main.save_data["castle_hp_level"]), 2)

	# 初始点数升级
	t.check_true("初始点数升级成功", main.try_upgrade_stat("points"))
	t.check("初始点数等级 +1", int(main.save_data["initial_points_level"]), 2)

	# 金币不足时拒绝
	main.save_data["gold"] = 0
	main.persist_save()
	t.check_false("金币不足时升级被拒", main.try_upgrade_tower("water_mage_tower"))
	t.check("被拒后等级不变", int(main.save_data["tower_levels"]["water_mage_tower"]), 1)

	# 满级后拒绝
	main.save_data["gold"] = 10_000_000
	main.save_data["tower_levels"]["fire_mage_tower"] = 5
	t.check_false("满级后升级被拒", main.try_upgrade_tower("fire_mage_tower"))

	# 城堡/点数满级后拒绝
	main.save_data["castle_hp_level"] = Config.CASTLE_HP_MAX_LEVEL
	t.check_false("城堡满级后拒绝", main.try_upgrade_stat("castle"))
	main.save_data["initial_points_level"] = Config.INITIAL_POINTS_MAX_LEVEL
	t.check_false("初始点数满级后拒绝", main.try_upgrade_stat("points"))
	_drop(t, main)
