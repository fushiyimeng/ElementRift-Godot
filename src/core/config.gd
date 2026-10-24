class_name Config
extends RefCounted
## 全局常量与配置中心 —— 移植自 src/config.py
##
## 集中存放所有会被多个模块引用的常量、反应表和纯计算函数。
## 改一个数值只需要改这里一处，其它模块自动生效。
##
## 与 Python 版的差异：本文件用 class_name + static，不需要注册成 autoload，
## 调用点写法完全一致（Config.FIXED_DT），但测试脚本无需依赖 autoload 即可使用。

# ---------- 版本 ----------
const VERSION := "0.3.0"

# ---------- 固定步长与帧率 ----------
## 固定逻辑步长：游戏逻辑固定按 1/60 秒一帧推进，保证不同机器上表现一致
const FIXED_DT := 1.0 / 60.0
## 单帧真实耗时上限（秒）：防止窗口卡顿/切后台后一帧推进过多逻辑导致跳变
const MAX_FRAME_DT := 0.1
## 帧率下限
const FPS_MIN := 60
## 帧率上限（设置界面可调）
const FPS_MAX := 1000

# ---------- 元素 ----------
## 游戏中的四种元素（用中文做唯一标识，贯穿数据文件与代码）
const ELEMENTS := ["火", "水", "雷", "冰"]

## 元素附着持续时间（秒）：怪物被元素命中后，附着在身上、可参与反应的窗口时长
const ELEMENT_ATTACH_DURATION := 3.0
## 元素反应冷却（秒）：同一怪物连续两次触发反应之间的最短间隔
const REACTION_COOLDOWN := 0.5
## 攻击被免疫时，飘字显示的文字
const IMMUNE_DISPLAY := "MISS"

# ---------- 冰元素控制效果 ----------
## 冻结时长（秒）：冰塔命中水系怪物时完全无法移动
const FREEZE_DURATION := 0.2
## 减速时长（秒）：命中非水系怪物时移动速度降低
const SLOW_DURATION := 1.5
## 减速期间移动速度倍率（0.8 = 减速 20%）
const SLOW_FACTOR := 0.8

# ---------- 元素反应定义 ----------
## 键为「旧元素 + 新元素」拼接的字符串（GDScript 没有元组，用拼接字符串等价）。
## 顺序无关：火+水 和 水+火 都是「蒸发」，所以两种组合都列出。
## 值：name 名称 / mult 倍率 / chain 连锁数 / knockback 击退强度 / aoe AOE 半径
const REACTIONS := {
	"火水": {"name": "蒸发", "mult": 1.5, "chain": 0, "knockback": 0, "aoe": 0},
	"水火": {"name": "蒸发", "mult": 1.5, "chain": 0, "knockback": 0, "aoe": 0},
	"雷水": {"name": "感电", "mult": 1.5, "chain": 2, "knockback": 0, "aoe": 0},
	"水雷": {"name": "感电", "mult": 1.5, "chain": 2, "knockback": 0, "aoe": 0},
	"火雷": {"name": "超载", "mult": 2.0, "chain": 0, "knockback": 110, "aoe": 90},
	"雷火": {"name": "超载", "mult": 2.0, "chain": 0, "knockback": 110, "aoe": 90},
	# 冰元素反应（参考原神）：冰+火=融化（高倍率爆发），冰+水=冻结（简化为增伤）。
	# 冰+雷=超导 需要「降低防御」字段，当前战斗系统暂不支持，故未加入。
	"冰火": {"name": "融化", "mult": 2.0, "chain": 0, "knockback": 0, "aoe": 0},
	"火冰": {"name": "融化", "mult": 2.0, "chain": 0, "knockback": 0, "aoe": 0},
	"冰水": {"name": "冻结", "mult": 1.5, "chain": 0, "knockback": 0, "aoe": 0},
	"水冰": {"name": "冻结", "mult": 1.5, "chain": 0, "knockback": 0, "aoe": 0},
}

# ---------- 配色 ----------
## 元素 -> 默认色块颜色：当对应图片缺失时，用这个纯色块作为回退显示。
## Python 版的 (r,g,b) 元组在这里换成 Godot 的 Color（分量已除以 255）。
static var ELEMENT_COLORS := {
	"火": Color8(255, 92, 92),
	"水": Color8(80, 150, 240),
	"雷": Color8(190, 110, 250),
	"冰": Color8(150, 210, 255),
}

## 卡牌稀有度 -> 边框颜色（prismatic 为 null，渲染时做彩虹渐变特殊处理）
static var RARITY_COLORS := {
	"brass": Color8(184, 115, 51),      # 黄铜 #B87333
	"silver": Color8(192, 192, 192),    # 白银 #C0C0C0
	"gold": Color8(255, 215, 0),        # 黄金 #FFD700
	"prismatic": null,                  # 彩色渐变，见 ui 层
}

## 卡牌稀有度英文 key -> 中文显示名（用于卡牌顶部的类型文字）
const RARITY_LABELS := {
	"brass": "黄铜",
	"silver": "白银",
	"gold": "黄金",
	"prismatic": "棱彩",
}

## 界面配色
static var COLOR_BG := Color8(24, 24, 34)               # 背景深色
static var COLOR_PATH := Color8(52, 52, 64)             # 路径颜色
static var COLOR_HOSTILE := Color8(220, 70, 70)         # 敌人/城堡血量等警示红色
static var COLOR_CASTLE := Color8(240, 210, 90)         # 城堡色块
static var COLOR_TEXT := Color8(235, 235, 235)          # 常规文字颜色
static var COLOR_MONEY_POINTS := Color8(110, 220, 160)  # 局内点数（绿色）
static var COLOR_MONEY_GOLD := Color8(255, 215, 100)    # 金币（金色）
static var COLOR_CARD_SEL := Color8(255, 225, 130)      # 卡牌/塔选中高亮边框
static var COLOR_BUTTON := Color8(52, 58, 84)           # 按钮常态背景
static var COLOR_BUTTON_HOVER := Color8(72, 80, 112)    # 按钮悬停背景
static var COLOR_BUTTON_DISABLED := Color8(44, 44, 52)  # 按钮禁用背景
static var COLOR_BUTTON_TEXT := Color8(235, 235, 235)   # 按钮文字颜色
static var COLOR_GRID := Color8(40, 40, 52)             # 网格线颜色
static var COLOR_OBSTACLE := Color8(70, 60, 50)         # 障碍物色块

# ---------- 尺寸与速度 ----------
## 投射物飞行速度（像素/秒）
const PROJECTILE_SPEED := 500.0
## 防御塔视觉半径（像素）：用于画塔的色块圆和选中提示圈
const TOWER_RADIUS := 28
## 防御塔立绘尺寸（宽 x 高）。
## 放置塔时按「图片下半部分」做占地碰撞判定：塔是立在地上的，只有塔基（下半截）
## 占地面，上半身悬空不占地，所以实际占地高度取这里高度的一半。
const TOWER_FOOTPRINT := Vector2i(55, 100)
## 底部死区（塔选择 UI 区域）高度：网格不绘制、路径不进入、塔不可放置于此
const UI_HEIGHT := 200
## 怪物路径的像素宽度（视觉宽度；同时作为「不可建塔」的路径占用宽度）
const PATH_WIDTH := 30

## 快进速度档位（循环切换：1x -> 2x -> 4x -> 1x）
const GAME_SPEEDS := [1, 2, 4]
## 塔击杀一只怪物奖励的局内点数
const KILL_POINTS := 5
## 卡牌刷新一次消耗的局内点数
const CARD_REFRESH_COST := 30
## 回收塔返还的建造点数比例（0.6 表示返还 60%）
const TOWER_RECYCLE_RATIO := 0.6

# ---------- 金币与奖励 ----------
## 普通关卡通关一次发放的金币：不按波次发，一局固定这一笔（数据里是 clear_gold）
const CLEAR_GOLD := 100
## 无尽模式每扛过一波发放的金币（数据里是 gold_reward）
const ENDLESS_GOLD_PER_WAVE := 100
## 无尽模式的里程碑间隔：每扛过这么多波，额外再发一笔
const ENDLESS_MILESTONE_STEP := 10
## 里程碑额外金币的基数：第 1 档 100，之后每档翻倍（100 / 200 / 400 / 800 / ...）
const ENDLESS_MILESTONE_BASE := 100
## 里程碑档位上限：防止跑上千波时 1 << n 把整数撑爆
const ENDLESS_MILESTONE_MAX := 20

# ---------- 城堡与点数成长 ----------
## 城堡初始生命等级：1 级 = 5 点血，每级 +1，最高 10 级
const CASTLE_HP_BASE := 5
const CASTLE_HP_MAX_LEVEL := 10
## 局内初始点数等级上限：1 级 = 200，每级 +100，最高 10 级 = 1100
const INITIAL_POINTS_MAX_LEVEL := 10

# ---------- 屏幕与窗口 ----------
## 分辨率档位（从小到大）。label 用于界面显示，size 是实际像素尺寸。
const RESOLUTION_PRESETS := [
	{"label": "720P", "size": Vector2i(1280, 720)},
	{"label": "1080P", "size": Vector2i(1920, 1080)},
	{"label": "2K", "size": Vector2i(2560, 1440)},
	{"label": "4K", "size": Vector2i(3840, 2160)},
]

## 游戏的设计分辨率。所有界面按这个尺寸排版，其它分辨率整体等比缩放
## （靠 project.godot 里的 stretch mode = canvas_items + aspect = keep）。
static var DEFAULT_RESOLUTION := Vector2i(1920, 1080)

## 窗口模式的取值（存档里存字符串，比布尔值好扩展）
const WINDOW_MODE_FULLSCREEN := "fullscreen"
const WINDOW_MODE_WINDOWED := "windowed"
const WINDOW_MODE_BORDERLESS := "borderless"

## 窗口模式 -> 界面显示名
const WINDOW_MODE_LABELS := {
	"fullscreen": "全屏",
	"windowed": "窗口",
	"borderless": "无边框窗口",
}


## 返回显示器实际支持的分辨率档位：只保留宽高都不超过屏幕的档位。
##
## 屏幕尺寸由调用方传入（而不是在这里读 DisplayServer），
## 这样这个函数是纯函数，可以用各种屏幕尺寸直接测，不依赖真实显示器。
static func available_resolutions(screen_size: Vector2i) -> Array:
	var out := []
	for preset in RESOLUTION_PRESETS:
		var size: Vector2i = preset["size"]
		if size.x <= screen_size.x and size.y <= screen_size.y:
			out.append(preset)
	# 兜底：屏幕比最小档还小时也得给一个选项，否则界面上一个分辨率都选不了
	if out.is_empty():
		out.append(RESOLUTION_PRESETS[0])
	return out


## 把分辨率收敛到「当前屏幕支持得起的最大档位」。
##
## 存档里的档位可能来自更大屏幕的机器（比如换显示器、或存档被拷过来），
## 直接按它开窗会超出屏幕范围，所以这里夹一下。
static func clamp_resolution(res: Vector2i, screen_size: Vector2i) -> Vector2i:
	var available := available_resolutions(screen_size)
	for preset in available:
		if preset["size"] == res:
			return res
	# 不在可用列表里：退到最大的一档
	var best: Vector2i = available[0]["size"]
	for preset in available:
		if (preset["size"] as Vector2i).x > best.x:
			best = preset["size"]
	return best


## 分辨率是否为合法档位
static func is_valid_resolution(res: Vector2i) -> bool:
	for preset in RESOLUTION_PRESETS:
		if preset["size"] == res:
			return true
	return false


## 档位标签（如 "1080P"）；不是已知档位时返回 "宽 x 高"
static func resolution_label(res: Vector2i) -> String:
	for preset in RESOLUTION_PRESETS:
		if preset["size"] == res:
			return preset["label"]
	return "%d x %d" % [res.x, res.y]


## 计算「从当前窗口状态切到目标模式」需要执行哪些操作，返回操作名列表。
##
## 抽成纯函数有两个好处：
## 1. 能直接测「目标状态与当前一致时不产生任何操作」—— 这正是闪屏的根因；
## 2. 不依赖 DisplayServer，无头环境也能测（无头下窗口状态是假的）。
##
## 返回的操作名（按执行顺序）：
##   "borderless_off" / "borderless_on" —— 设/清无边框标志
##   "fullscreen_on"  / "fullscreen_off" —— 切全屏 / 切回窗口
##
## 注意顺序：从「无边框窗口」切「全屏」时必须先在窗口态下清掉无边框标志，
## 否则全屏会带着无边框状态。
static func window_ops(is_fullscreen: bool, is_borderless: bool,
		target_mode: String) -> PackedStringArray:
	var ops := PackedStringArray()
	var want_fullscreen := target_mode == WINDOW_MODE_FULLSCREEN
	var want_borderless := target_mode == WINDOW_MODE_BORDERLESS
	var bl := is_borderless
	var fs := is_fullscreen

	# 从无边框窗口切全屏：先清无边框标志
	if want_fullscreen and not fs and bl:
		ops.append("borderless_off")
		bl = false

	# 全屏状态需要变才切
	if fs != want_fullscreen:
		ops.append("fullscreen_on" if want_fullscreen else "fullscreen_off")
		fs = want_fullscreen

	# 无边框标志只在窗口态有意义
	if not fs and bl != want_borderless:
		ops.append("borderless_on" if want_borderless else "borderless_off")

	return ops


## 根据城堡生命等级计算城堡血量：1 级 = 5，之后每级 +1。
static func castle_hp_for_level(level: int) -> int:
	return CASTLE_HP_BASE + (level - 1)


## 根据初始点数等级计算开局点数：1 级 200，之后每级 +100。
static func initial_points_for_level(level: int) -> int:
	return 100 * (level + 1)


## 无尽模式第 milestone 档里程碑的额外金币：100 / 200 / 400 / 800 / ...
##
## 即扛过 10 波额外 +100、20 波 +200、30 波 +400、40 波 +800 —— 每档在上一档
## 基础上翻倍。每档是「各发各的」（累加），不是把总额替换掉。
static func endless_milestone_bonus(milestone: int) -> int:
	if milestone <= 0:
		return 0
	# 用位移而非 pow()，保证整数精确
	return ENDLESS_MILESTONE_BASE << (mini(milestone, ENDLESS_MILESTONE_MAX) - 1)


## 计算把某个项目从 current_level 升到下一级所需的金币。
## 1 升 2 需 100，2 升 3 需 200，3 升 4 需 400，依此类推（2 倍递增）。
## 用位移而非 pow()，保证整数精确（pow 返回浮点）。
static func upgrade_cost(current_level: int) -> int:
	return 100 * (1 << (current_level - 1))
