extends RefCounted
## 校验数据加载器 —— 对拍 src/loader.py
##
## 额外重点：中文文件名资源能否在运行时正常加载（移植方案里的风险项）。


func run(t) -> void:
	GameData.load_all()
	_test_load_all(t)
	_test_monster_data(t)
	_test_tower_data(t)
	_test_card_data(t)
	_test_maps(t)
	_test_textures(t)          # 含中文文件名资源
	_test_sprite_masks(t)
	_test_save_default(t)
	_test_save_roundtrip(t)
	_test_sanitize(t)
	_test_audio_assets(t)
	t.finish()


func _test_load_all(t) -> void:
	t.check("怪物数量", GameData.monsters.size(), 4)
	t.check("塔数量", GameData.towers.size(), 4)
	t.check("卡牌数量", GameData.cards.size(), 4)
	# 5 个普通关卡 + 无尽模式
	t.check("关卡数量", GameData.level_ids().size(), 6)
	t.check("关卡 id", GameData.level_ids(),
			["level_01", "level_02", "level_03", "level_04", "level_05", "level_endless"])
	t.check_true("怪物 id 齐全", GameData.get_monster("fire_slime") != null)
	t.check_true("塔 id 齐全", GameData.get_tower("fire_mage_tower") != null)
	t.check_true("卡牌 id 齐全", GameData.get_card("brass_fire_damage") != null)
	t.check("get_monster 未知 id 返回 null", GameData.get_monster("nope"), null)
	t.check("get_tower 未知 id 返回 null", GameData.get_tower("nope"), null)
	t.check("get_card 未知 id 返回 null", GameData.get_card("nope"), null)


func _test_monster_data(t) -> void:
	var m: Dictionary = GameData.get_monster("fire_slime")
	t.check("火史莱姆 name", m.get("name"), "火史莱姆")
	t.check("火史莱姆 element", m.get("element"), "火")
	t.check("火史莱姆 hp", int(m.get("hp")), 100)
	t.check("火史莱姆 speed", int(m.get("speed")), 80)
	t.check("火史莱姆 defense_element", int(m.get("defense_element")), 50)
	t.check("火史莱姆 defense_physical", int(m.get("defense_physical")), 100)
	t.check("火史莱姆 immune", m.get("immune"), ["火"])
	t.check("火史莱姆 帧数", int(m.get("frame_count")), 13)
	t.check("火史莱姆 帧尺寸",
			Vector2i(int(m.get("frame_width")), int(m.get("frame_height"))),
			Vector2i(128, 64))
	# 四只史莱姆的免疫元素各不相同
	t.check("水史莱姆 immune", GameData.get_monster("water_slime").get("immune"), ["水"])
	t.check("雷史莱姆 immune", GameData.get_monster("thunder_slime").get("immune"), ["雷"])
	t.check("冰史莱姆 immune", GameData.get_monster("ice_slime").get("immune"), ["冰"])
	# 冰史莱姆是唯一带中文文件名的资源 —— 移植风险点
	t.check("冰史莱姆 image 路径（中文名）",
			GameData.get_monster("ice_slime").get("image"), "image/monsters/冰史莱姆.png")
	t.check("雷史莱姆帧高与其它不同（62）",
			int(GameData.get_monster("thunder_slime").get("frame_height")), 62)


func _test_tower_data(t) -> void:
	var fire: Dictionary = GameData.get_tower("fire_mage_tower")
	t.check("火法师塔 name", fire.get("name"), "火法师塔")
	t.check("火法师塔 element", fire.get("attack_element"), "火")
	t.check("火法师塔 attack_mode", fire.get("attack_mode"), "single")
	t.check("火法师塔 build_cost", int(fire.get("build_cost")), 100)
	t.check("火法师塔 等级数", fire.get("levels", []).size(), 5)
	t.check("火法师塔 Lv1 攻击力", int(fire["levels"][0]["attack_power"]), 60)
	t.check("火法师塔 Lv5 范围", int(fire["levels"][4]["attack_range"]), 30)

	var water: Dictionary = GameData.get_tower("water_mage_tower")
	t.check("水法师塔 attack_mode", water.get("attack_mode"), "aoe")
	t.check("水法师塔 aoe_radius", int(water.get("aoe_radius")), 150)

	var thunder: Dictionary = GameData.get_tower("thunder_mage_tower")
	t.check("雷法师塔 attack_mode", thunder.get("attack_mode"), "chain")
	t.check("雷法师塔 max_targets", int(thunder.get("max_targets")), 4)
	t.check("雷法师塔 Lv1 攻击力", int(thunder["levels"][0]["attack_power"]), 3)
	t.check("雷法师塔 Lv1 攻速", int(thunder["levels"][0]["attack_speed"]), 10)
	t.check("雷法师塔 build_cost", int(thunder.get("build_cost")), 80)

	t.check("冰法师塔 element", GameData.get_tower("ice_mage_tower").get("attack_element"), "冰")


func _test_card_data(t) -> void:
	var c: Dictionary = GameData.get_card("brass_fire_damage")
	t.check("黄铜火伤害 name", c.get("name"), "黄铜·火元素伤害")
	t.check("黄铜火伤害 rarity", c.get("rarity"), "brass")
	t.check("黄铜火伤害 price", int(c.get("price")), 30)
	t.check("黄铜火伤害 scope", c.get("scope"), "element")
	t.check("黄铜火伤害 target", c.get("target"), "火")
	t.check("黄铜火伤害 stat", c.get("stat"), "damage")
	t.check("黄铜火伤害 op", c.get("op"), "mul")
	t.check_almost("黄铜火伤害 value", float(c.get("value")), 0.10)
	# 攻速卡是 global 范围
	var s: Dictionary = GameData.get_card("brass_attack_speed")
	t.check("黄铜攻速 scope", s.get("scope"), "global")
	t.check("黄铜攻速 target", s.get("target"), "all_towers")
	t.check("黄铜攻速 price", int(s.get("price")), 40)


func _test_maps(t) -> void:
	var lv: Dictionary = GameData.preload_level("level_01")
	t.check("level_01 name", lv.get("name"), "史莱姆平原")
	t.check("level_01 chapter", int(lv.get("chapter")), 1)
	# 注意：JSON 里的数字在 Godot 里一律解析成 float，逐字段转 int 再比，
	# 不能直接拿整个 Dictionary 和 int 字面量比（128.0 与 128 在字典深比较中不相等）
	var grid: Dictionary = lv.get("grid", {})
	t.check("level_01 grid.width", int(grid.get("width", 0)), 128)
	t.check("level_01 grid.height", int(grid.get("height", 0)), 72)
	t.check("level_01 grid.tile_size", int(grid.get("tile_size", 0)), 15)
	t.check("level_01 路径点数", lv.get("path", []).size(), 6)
	t.check("level_01 障碍数", lv.get("obstacles", []).size(), 6)
	t.check("level_01 波次数", lv.get("waves", []).size(), 7)
	t.check("level_01 怪物池", lv.get("monster_pool", []).size(), 4)
	t.check("level_01 塔池", lv.get("tower_pool", []).size(), 4)
	t.check("level_01 每波发卡数", int(lv.get("cards_per_wave")), 3)
	t.check("level_01 波次点数", int(lv.get("points_per_wave")), 50)
	t.check("level_01 非无尽", lv.get("endless", false), false)
	# 第 1 波 6 只火史莱姆、间隔 1.0
	var w1: Dictionary = lv["waves"][0]
	t.check("第 1 波 hp_bonus", float(w1.get("hp_bonus")), 0.0)
	t.check("第 1 波 group 数", w1.get("groups", []).size(), 1)
	t.check("第 1 波数量", int(w1["groups"][0]["count"]), 6)
	# 第 7 波四系混编
	t.check("第 7 波 group 数", lv["waves"][6].get("groups", []).size(), 4)

	var ed: Dictionary = GameData.preload_level("level_endless")
	t.check("无尽 name", ed.get("name"), "无尽裂隙")
	t.check("无尽 endless 标记", ed.get("endless"), true)
	t.check_almost("无尽 hp_growth", float(ed.get("endless_hp_growth")), 0.18)
	t.check("无尽 每波点数", int(ed.get("points_per_wave")), 40)
	# 缓存：二次读取应返回同一对象
	t.check_true("preload_level 命中缓存",
			GameData.preload_level("level_01") == lv)


## 贴图加载：英文名与中文名都要成功（中文名是移植风险点）
func _test_textures(t) -> void:
	var fire_tex := GameData.load_texture("image/monsters/fire_slime.png")
	t.check_true("加载 fire_slime.png 成功", fire_tex != null)
	if fire_tex != null:
		# 13 帧 × 128 宽 = 1664（Texture2D.get_size() 返回 Vector2）
		t.check("fire_slime sheet 尺寸", fire_tex.get_size(), Vector2(1664, 64))

	# 中文文件名资源 —— 若这里失败，说明必须把资源改名为 ASCII
	var ice_tex := GameData.load_texture("image/monsters/冰史莱姆.png")
	t.check_true("加载 冰史莱姆.png（中文名）成功", ice_tex != null)
	if ice_tex != null:
		t.check("冰史莱姆 sheet 尺寸", ice_tex.get_size(), Vector2(1664, 64))

	# 塔立绘与 UI 图
	t.check_true("加载火塔立绘成功",
			GameData.load_texture("image/towers/fire_mage_tower.png") != null)
	t.check_true("加载防御塔UI框成功",
			GameData.load_texture("image/防御塔UI框.png") != null)
	t.check_true("加载卡牌背景图成功",
			GameData.load_texture("image/卡牌背景图.png") != null)
	t.check_true("加载暂停图标成功", GameData.load_texture("image/暂停.png") != null)
	t.check_true("加载继续图标成功", GameData.load_texture("image/继续.png") != null)
	t.check_true("加载快进图标成功", GameData.load_texture("image/forward.png") != null)

	# 缺失资源返回 null 而不是崩溃
	t.check("缺失贴图返回 null", GameData.load_texture("image/不存在.png"), null)
	t.check("空路径返回 null", GameData.load_texture(""), null)


## 碰撞遮罩：13 帧、重心落在帧内
func _test_sprite_masks(t) -> void:
	var masks := GameData.load_sprite_masks(
			"image/monsters/fire_slime.png", 13, 128, 64, 128, 64)
	t.check("遮罩帧数", masks.size(), 13)
	if masks.size() > 0:
		var m0: Dictionary = masks[0]
		t.check("遮罩尺寸", m0["size"], Vector2i(128, 64))
		t.check_true("遮罩含不透明像素",
				(m0["bitmap"] as BitMap).get_true_bit_count() > 0)
		var c: Vector2 = m0["centroid"]
		t.check_true("重心在帧内", c.x >= 0.0 and c.x <= 128.0
				and c.y >= 0.0 and c.y <= 64.0)
		# 史莱姆是圆的，重心应接近帧中心（允许明显偏移，只排除跑飞）
		t.check_true("重心接近帧中心",
				absf(c.x - 64.0) < 30.0 and absf(c.y - 32.0) < 30.0)
	# 缓存：二次调用返回同一数组
	t.check_true("遮罩命中缓存",
			GameData.load_sprite_masks("image/monsters/fire_slime.png", 13, 128, 64, 128, 64)
			== masks)
	# 缺失图片返回空数组
	t.check("缺失图片遮罩为空数组",
			GameData.load_sprite_masks("image/nope.png", 4, 32, 32, 32, 32), [])


func _test_save_default(t) -> void:
	var s := GameData.default_save()
	t.check("默认金币", int(s["gold"]), 0)
	t.check("默认解锁全部关卡", s["unlocked_maps"].size(), 6)
	t.check("默认解锁全部塔", s["unlocked_towers"].size(), 4)
	t.check("默认解锁全部卡牌", s["unlocked_cards"].size(), 4)
	t.check("默认塔等级全 1", s["tower_levels"]["fire_mage_tower"], 1)
	t.check("默认城堡等级", int(s["castle_hp_level"]), 1)
	t.check("默认初始点数等级", int(s["initial_points_level"]), 1)
	t.check("默认设置帧率", int(s["settings"]["fps"]), Config.FPS_MIN)
	t.check("默认窗口模式", s["settings"]["window_mode"], Config.WINDOW_MODE_WINDOWED)
	t.check_almost("默认 UI 音量", float(s["settings"]["ui"]), 1.0)


func _test_save_roundtrip(t) -> void:
	var original := GameData.load_save()
	var probe := original.duplicate(true)
	probe["gold"] = 1234
	probe["castle_hp_level"] = 3
	GameData.write_save(probe)
	var back := GameData.load_save()
	t.check("存档往返：金币", int(back["gold"]), 1234)
	t.check("存档往返：城堡等级", int(back["castle_hp_level"]), 3)
	# 还原，避免污染后续用例
	GameData.write_save(original)


## 存档防篡改：越界等级钳制、负数金币归零
func _test_sanitize(t) -> void:
	var dirty := {
		"gold": -50,
		"tower_levels": {"fire_mage_tower": 999, "water_mage_tower": 0},
		"castle_hp_level": 99,
		"initial_points_level": -3,
		"settings": {"fps": 99999, "volume": 5.0, "sfx": -1.0,
				"resolution": [640, 480], "fullscreen": true},
	}
	var s := GameData.sanitize_save(dirty)
	t.check("负金币归零", int(s["gold"]), 0)
	t.check("塔等级上限钳制（5 级）", int(s["tower_levels"]["fire_mage_tower"]), 5)
	t.check("塔等级下限钳制（1 级）", int(s["tower_levels"]["water_mage_tower"]), 1)
	t.check("城堡等级钳制到 10", int(s["castle_hp_level"]), Config.CASTLE_HP_MAX_LEVEL)
	t.check("初始点数等级钳制到 1", int(s["initial_points_level"]), 1)
	t.check("帧率钳制到上限", int(s["settings"]["fps"]), Config.FPS_MAX)
	t.check_almost("音量钳制到 1.0", float(s["settings"]["volume"]), 1.0)
	t.check_almost("音效钳制到 0.0", float(s["settings"]["sfx"]), 0.0)
	# 「UI 音量」是后加的档位，旧存档没有这个键时要补 1.0
	t.check_almost("缺失的 UI 音量补默认值", float(s["settings"].get("ui", -1.0)), 1.0)
	t.check_almost("默认存档含 UI 音量", float(GameData.default_save()["settings"]["ui"]), 1.0)
	t.check("非法分辨率回退默认", s["settings"]["resolution"],
			[Config.DEFAULT_RESOLUTION.x, Config.DEFAULT_RESOLUTION.y])

	# 窗口模式：旧存档只有 fullscreen 布尔值，要迁移成 window_mode 并删掉旧键
	t.check("旧存档 fullscreen=true 迁移为全屏",
			s["settings"]["window_mode"], Config.WINDOW_MODE_FULLSCREEN)
	t.check_false("迁移后旧键已删除", s["settings"].has("fullscreen"))
	var old_windowed := GameData.sanitize_save({"settings": {"fullscreen": false}})
	t.check("旧存档 fullscreen=false 迁移为窗口",
			old_windowed["settings"]["window_mode"], Config.WINDOW_MODE_WINDOWED)
	var already_new := GameData.sanitize_save(
			{"settings": {"window_mode": Config.WINDOW_MODE_BORDERLESS}})
	t.check("已有的 window_mode 保留",
			already_new["settings"]["window_mode"], Config.WINDOW_MODE_BORDERLESS)
	var bad_mode := GameData.sanitize_save({"settings": {"window_mode": "乱写的"}})
	t.check("非法窗口模式回退为窗口",
			bad_mode["settings"]["window_mode"], Config.WINDOW_MODE_WINDOWED)

	# 缺失字段补全
	var empty := GameData.sanitize_save({})
	t.check("空存档补全塔等级", empty["tower_levels"].size(), 4)
	t.check("空存档补全设置", empty.has("settings"), true)

	# 解锁列表自愈：空数组 / 类型错误 / 缺失都要回填成「全部解锁」。
	# 这几项一旦为空，选关界面和升级界面会变成一片空白且不会自愈，属于必须拦住的坏档。
	var broken := GameData.sanitize_save({
		"unlocked_towers": [], "unlocked_maps": [], "unlocked_cards": "坏数据"})
	t.check("空 unlocked_towers 回填为全部", broken["unlocked_towers"].size(), 4)
	t.check("空 unlocked_maps 回填为全部", broken["unlocked_maps"].size(), 6)
	t.check("类型错误的 unlocked_cards 回填为全部", broken["unlocked_cards"].size(), 4)
	t.check("缺失 unlocked_towers 回填为全部", empty["unlocked_towers"].size(), 4)
	t.check("缺失 unlocked_maps 回填为全部", empty["unlocked_maps"].size(), 6)
	# 已有条目保留，但「已注册却没在列表里」的条目要补进来 ——
	# 否则老存档在新版本里会永远打不开新关卡（游戏里没有解锁玩法）
	var old_save := GameData.sanitize_save({
		"unlocked_maps": ["level_01", "level_endless"],
		"unlocked_towers": ["fire_mage_tower"],
	})
	t.check("老存档保留已有顺序，末尾补齐新关卡", old_save["unlocked_maps"],
			["level_01", "level_endless", "level_02", "level_03", "level_04", "level_05"])
	t.check("老存档补齐新塔", old_save["unlocked_towers"],
			["fire_mage_tower", "water_mage_tower", "thunder_mage_tower", "ice_mage_tower"])
	# 已经齐全的列表不应被改动
	var good := GameData.sanitize_save({
		"unlocked_towers": ["fire_mage_tower", "water_mage_tower",
				"thunder_mage_tower", "ice_mage_tower"]})
	t.check("已齐全的解锁列表不被改动", good["unlocked_towers"],
			["fire_mage_tower", "water_mage_tower", "thunder_mage_tower", "ice_mage_tower"])


## 音频资源存在性（含中文目录与文件名）
func _test_audio_assets(t) -> void:
	var paths := [
		"res://data/音乐/主界面背景音乐.mp3",
		"res://data/音乐/休闲音乐.mp3",
		"res://data/音乐/无限模式音乐_1.mp3",
		"res://data/音乐/无限模式音乐_2.mp3",
		"res://data/音效/升级音效.mp3",
		"res://data/音效/点击卡牌的音效.mp3",
		"res://data/音效/界面按钮点击音效.mp3",
		"res://data/音效/防御塔攻击音效.mp3",
		"res://data/音效/雷防御塔攻击音效.mp3",
	]
	for p in paths:
		t.check_true("存在 %s" % p.get_file(), ResourceLoader.exists(p))
	# 音频流能真正加载（中文路径的运行时加载验证）
	var stream = load("res://data/音乐/休闲音乐.mp3")
	t.check_true("加载 休闲音乐.mp3（中文名）成功", stream != null)
