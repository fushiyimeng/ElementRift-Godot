extends RefCounted
## 校验 Config 常量与公式 —— 对拍 src/config.py
##
## 期望值全部来自 Python 版实际跑出来的结果（见 tools 对拍脚本），不是手算。

func run(t) -> void:
	# ---------- 版本与步长 ----------
	t.check("VERSION", Config.VERSION, "0.3.0")
	t.check_almost("FIXED_DT", Config.FIXED_DT, 1.0 / 60.0)
	t.check_almost("MAX_FRAME_DT", Config.MAX_FRAME_DT, 0.1)
	t.check("FPS_MIN", Config.FPS_MIN, 60)
	t.check("FPS_MAX", Config.FPS_MAX, 1000)

	# ---------- 元素与附着 ----------
	t.check("ELEMENTS", Config.ELEMENTS, ["火", "水", "雷", "冰"])
	t.check_almost("ELEMENT_ATTACH_DURATION", Config.ELEMENT_ATTACH_DURATION, 3.0)
	t.check_almost("REACTION_COOLDOWN", Config.REACTION_COOLDOWN, 0.5)
	t.check("IMMUNE_DISPLAY", Config.IMMUNE_DISPLAY, "MISS")

	# ---------- 冰系控制 ----------
	t.check_almost("FREEZE_DURATION", Config.FREEZE_DURATION, 0.2)
	t.check_almost("SLOW_DURATION", Config.SLOW_DURATION, 1.5)
	t.check_almost("SLOW_FACTOR", Config.SLOW_FACTOR, 0.8)

	# ---------- 反应表：条数与逐条内容 ----------
	t.check("REACTIONS count", Config.REACTIONS.size(), 10)
	_check_reaction(t, "火水", "蒸发", 1.5, 0, 0, 0)
	_check_reaction(t, "水火", "蒸发", 1.5, 0, 0, 0)
	_check_reaction(t, "雷水", "感电", 1.5, 2, 0, 0)
	_check_reaction(t, "水雷", "感电", 1.5, 2, 0, 0)
	_check_reaction(t, "火雷", "超载", 2.0, 0, 110, 90)
	_check_reaction(t, "雷火", "超载", 2.0, 0, 110, 90)
	_check_reaction(t, "冰火", "融化", 2.0, 0, 0, 0)
	_check_reaction(t, "火冰", "融化", 2.0, 0, 0, 0)
	_check_reaction(t, "冰水", "冻结", 1.5, 0, 0, 0)
	_check_reaction(t, "水冰", "冻结", 1.5, 0, 0, 0)
	# 顺序无关性：火+水 与 水+火 倍率一致
	t.check_almost("reaction 顺序无关 (火水==水火)",
			Config.REACTIONS["火水"]["mult"], Config.REACTIONS["水火"]["mult"])
	# 未定义的组合不应命中（冰+雷=超导 当前版本不支持）
	t.check_false("未定义组合 冰雷 不在表中", Config.REACTIONS.has("冰雷"))
	t.check_false("未定义组合 雷冰 不在表中", Config.REACTIONS.has("雷冰"))

	# ---------- 元素颜色 ----------
	t.check("ELEMENT_COLORS count", Config.ELEMENT_COLORS.size(), 4)
	t.check("ELEMENT_COLORS 火", Config.ELEMENT_COLORS["火"], Color8(255, 92, 92))
	t.check("ELEMENT_COLORS 水", Config.ELEMENT_COLORS["水"], Color8(80, 150, 240))
	t.check("ELEMENT_COLORS 雷", Config.ELEMENT_COLORS["雷"], Color8(190, 110, 250))
	t.check("ELEMENT_COLORS 冰", Config.ELEMENT_COLORS["冰"], Color8(150, 210, 255))

	# ---------- 稀有度 ----------
	t.check("RARITY_LABELS", Config.RARITY_LABELS,
			{"brass": "黄铜", "silver": "白银", "gold": "黄金", "prismatic": "棱彩"})
	t.check("RARITY_COLORS.prismatic 为 null", Config.RARITY_COLORS["prismatic"], null)

	# ---------- 尺寸与速度 ----------
	t.check("PROJECTILE_SPEED", Config.PROJECTILE_SPEED, 500.0)
	t.check("TOWER_RADIUS", Config.TOWER_RADIUS, 28)
	t.check("TOWER_FOOTPRINT", Config.TOWER_FOOTPRINT, Vector2i(55, 100))
	t.check("UI_HEIGHT", Config.UI_HEIGHT, 200)
	t.check("PATH_WIDTH", Config.PATH_WIDTH, 30)
	t.check("GAME_SPEEDS", Config.GAME_SPEEDS, [1, 2, 4])

	# ---------- 经济数值 ----------
	t.check("KILL_POINTS", Config.KILL_POINTS, 5)
	t.check("CARD_REFRESH_COST", Config.CARD_REFRESH_COST, 30)
	t.check_almost("TOWER_RECYCLE_RATIO", Config.TOWER_RECYCLE_RATIO, 0.6)
	t.check("CASTLE_HP_BASE", Config.CASTLE_HP_BASE, 5)
	t.check("CASTLE_HP_MAX_LEVEL", Config.CASTLE_HP_MAX_LEVEL, 10)
	t.check("INITIAL_POINTS_MAX_LEVEL", Config.INITIAL_POINTS_MAX_LEVEL, 10)

	# ---------- 成长公式（对拍 Python） ----------
	# upgrade_cost(1..8) == [100, 200, 400, 800, 1600, 3200, 6400, 12800]
	var costs := []
	for i in range(1, 9):
		costs.append(Config.upgrade_cost(i))
	t.check("upgrade_cost(1..8)", costs,
			[100, 200, 400, 800, 1600, 3200, 6400, 12800])
	# initial_points_for_level(1..4) == [200, 300, 400, 500]
	var pts := []
	for i in range(1, 5):
		pts.append(Config.initial_points_for_level(i))
	t.check("initial_points_for_level(1..4)", pts, [200, 300, 400, 500])
	# castle_hp_for_level(1..4) == [5, 6, 7, 8]
	var hps := []
	for i in range(1, 5):
		hps.append(Config.castle_hp_for_level(i))
	t.check("castle_hp_for_level(1..4)", hps, [5, 6, 7, 8])

	# ---------- 金币与无尽里程碑 ----------
	t.check("CLEAR_GOLD", Config.CLEAR_GOLD, 100)
	t.check("ENDLESS_GOLD_PER_WAVE", Config.ENDLESS_GOLD_PER_WAVE, 100)
	t.check("ENDLESS_MILESTONE_STEP", Config.ENDLESS_MILESTONE_STEP, 10)
	# 扛过 10 波 +100、20 波 +200、30 波 +400、40 波 +800（每档翻倍）
	var bonuses := []
	for i in range(1, 5):
		bonuses.append(Config.endless_milestone_bonus(i))
	t.check("endless_milestone_bonus(1..4)", bonuses, [100, 200, 400, 800])
	t.check("endless_milestone_bonus(0) = 0（不到 10 波没有奖励）",
			Config.endless_milestone_bonus(0), 0)
	# 档位上限：防止跑上千波时位移把整数撑爆
	t.check("里程碑档位有上限",
			Config.endless_milestone_bonus(Config.ENDLESS_MILESTONE_MAX + 50),
			Config.endless_milestone_bonus(Config.ENDLESS_MILESTONE_MAX))

	# ---------- 分辨率档位 ----------
	t.check("DEFAULT_RESOLUTION", Config.DEFAULT_RESOLUTION, Vector2i(1920, 1080))
	t.check("分辨率档位数", Config.RESOLUTION_PRESETS.size(), 4)
	t.check("第 1 档标签", Config.RESOLUTION_PRESETS[0]["label"], "720P")
	t.check("第 1 档尺寸", Config.RESOLUTION_PRESETS[0]["size"], Vector2i(1280, 720))
	t.check("第 2 档尺寸", Config.RESOLUTION_PRESETS[1]["size"], Vector2i(1920, 1080))
	t.check("第 3 档尺寸", Config.RESOLUTION_PRESETS[2]["size"], Vector2i(2560, 1440))
	t.check("第 4 档尺寸", Config.RESOLUTION_PRESETS[3]["size"], Vector2i(3840, 2160))

	# 显示器支持检测：只保留宽高都不超过屏幕的档位
	t.check("1080p 屏幕可见 2 档（720P/1080P）",
			Config.available_resolutions(Vector2i(1920, 1080)).size(), 2)
	t.check("2K 屏幕可见 3 档", Config.available_resolutions(Vector2i(2560, 1440)).size(), 3)
	t.check("4K 屏幕可见 4 档", Config.available_resolutions(Vector2i(3840, 2160)).size(), 4)
	t.check("比最小档还小的屏幕也保留 1 档（否则一个都选不了）",
			Config.available_resolutions(Vector2i(800, 600)).size(), 1)
	# 超宽带鱼屏：宽够但矮，4K 的 2160 高放不下
	t.check("带鱼屏 5120x1440 只给 3 档（不含 4K）",
			Config.available_resolutions(Vector2i(5120, 1440)).size(), 3)

	# 分辨率收敛：存档里的档位超出当前屏幕时退到最大可用档
	t.check("支持的档位原样保留",
			Config.clamp_resolution(Vector2i(1920, 1080), Vector2i(1920, 1080)),
			Vector2i(1920, 1080))
	t.check("4K 存档在 1080p 屏幕上收敛到 1080P",
			Config.clamp_resolution(Vector2i(3840, 2160), Vector2i(1920, 1080)),
			Vector2i(1920, 1080))
	t.check("非档位分辨率收敛到最大可用档",
			Config.clamp_resolution(Vector2i(1600, 900), Vector2i(1920, 1080)),
			Vector2i(1920, 1080))
	t.check("1366x768 笔记本上收敛到 720P",
			Config.clamp_resolution(Vector2i(1920, 1080), Vector2i(1366, 768)),
			Vector2i(1280, 720))

	# 合法性判定与标签
	t.check_true("1080P 是合法档位", Config.is_valid_resolution(Vector2i(1920, 1080)))
	t.check_false("1600x900 不是合法档位", Config.is_valid_resolution(Vector2i(1600, 900)))
	t.check("档位标签 2K", Config.resolution_label(Vector2i(2560, 1440)), "2K")
	t.check("非档位分辨率回退为尺寸文字",
			Config.resolution_label(Vector2i(1600, 900)), "1600 x 900")

	# ---------- 窗口模式 ----------
	t.check("窗口模式有 3 档", Config.WINDOW_MODE_LABELS.size(), 3)
	t.check("全屏标签", Config.WINDOW_MODE_LABELS[Config.WINDOW_MODE_FULLSCREEN], "全屏")
	t.check("窗口标签", Config.WINDOW_MODE_LABELS[Config.WINDOW_MODE_WINDOWED], "窗口")
	t.check("无边框标签",
			Config.WINDOW_MODE_LABELS[Config.WINDOW_MODE_BORDERLESS], "无边框窗口")

	# ---------- 窗口切换操作 ----------
	# 核心不变量：**目标状态与当前一致时不产生任何操作**。
	# 这里是闪屏 bug 的所在：之前为了清无边框标志，无条件「先切窗口态再切全屏」，
	# 于是一旦已经是全屏，切换列表里也会出现一次无谓的往返，画面闪一下。
	t.check("已全屏 + 目标全屏 = 无操作（闪屏根因）",
			Config.window_ops(true, false, Config.WINDOW_MODE_FULLSCREEN),
			PackedStringArray())
	t.check("窗口 + 目标窗口 = 无操作",
			Config.window_ops(false, false, Config.WINDOW_MODE_WINDOWED),
			PackedStringArray())
	t.check("无边框 + 目标无边框 = 无操作",
			Config.window_ops(false, true, Config.WINDOW_MODE_BORDERLESS),
			PackedStringArray())

	# 状态真的不同才产生操作
	t.check("全屏 -> 窗口",
			Config.window_ops(true, false, Config.WINDOW_MODE_WINDOWED),
			PackedStringArray(["fullscreen_off"]))
	t.check("窗口 -> 全屏",
			Config.window_ops(false, false, Config.WINDOW_MODE_FULLSCREEN),
			PackedStringArray(["fullscreen_on"]))
	t.check("窗口 -> 无边框",
			Config.window_ops(false, false, Config.WINDOW_MODE_BORDERLESS),
			PackedStringArray(["borderless_on"]))
	t.check("无边框 -> 窗口",
			Config.window_ops(false, true, Config.WINDOW_MODE_WINDOWED),
			PackedStringArray(["borderless_off"]))
	# 顺序不能反：必须先在窗口态清掉无边框标志，再切全屏
	t.check("无边框 -> 全屏（先清标志再切全屏）",
			Config.window_ops(false, true, Config.WINDOW_MODE_FULLSCREEN),
			PackedStringArray(["borderless_off", "fullscreen_on"]))
	t.check("全屏 -> 无边框窗口（先退全屏再开无边框）",
			Config.window_ops(true, false, Config.WINDOW_MODE_BORDERLESS),
			PackedStringArray(["fullscreen_off", "borderless_on"]))

	t.finish()


## 逐字段校验一条反应定义（不依赖 Dictionary 的相等语义，失败信息也更清楚）。
func _check_reaction(t, key: String, name: String, mult: float,
		chain: int, knockback: int, aoe: float) -> void:
	t.check_true("REACTIONS[%s] 存在" % key, Config.REACTIONS.has(key))
	if not Config.REACTIONS.has(key):
		return
	var r: Dictionary = Config.REACTIONS[key]
	t.check("REACTIONS[%s].name" % key, r["name"], name)
	t.check_almost("REACTIONS[%s].mult" % key, r["mult"], mult)
	t.check("REACTIONS[%s].chain" % key, r["chain"], chain)
	t.check("REACTIONS[%s].knockback" % key, r["knockback"], knockback)
	t.check("REACTIONS[%s].aoe" % key, r["aoe"], aoe)
