class_name Game
extends Node2D
## 游戏核心逻辑 —— 移植自 src/game.py
##
## 一局游戏的完整状态：波次、塔、怪物、双货币、卡牌与元素反应联动。
## 本节点同时是所有实体节点的父节点（怪物/塔/投射物都挂在它下面）。
##
## 时序约定：实体一律不用 _process/_physics_process，而是由本节点的 tick(dt)
## 逐个驱动。这样「固定步长 + 快进倍率」的模型才成立 —— 快进就是把 tick 多跑几次，
## 挂引擎自己的时钟会与快进倍率脱节。对应 Python 版 main.py 的主循环。

const MONSTER_SCENE := preload("res://src/entities/monster.tscn")
const TOWER_SCENE := preload("res://src/entities/tower.tscn")
const PROJECTILE_SCENE := preload("res://src/entities/projectile.tscn")

## 游戏状态
const STATE_BUILD := "build"
const STATE_COMBAT := "combat"
const STATE_WIN := "win"
const STATE_LOSE := "lose"


## 一个出怪事件：按固定间隔（interval）连续放出 count 只同种怪物。
class SpawnEvent extends RefCounted:
	var monster_id := ""
	var count := 0
	var interval := 1.0
	var delay := 0.0
	var remaining := 0
	var timer := 0.0

	func _init(p_id: String, p_count: int, p_interval: float, p_delay: float) -> void:
		monster_id = p_id
		count = p_count
		interval = p_interval
		delay = p_delay
		remaining = p_count
		timer = p_interval + p_delay   # 含首次延迟

	## 倒计时到 0 且还有剩余就生成一只，返回 true 表示本次生成了。
	func update(dt: float) -> bool:
		timer -= dt
		if timer <= 0.0 and remaining > 0:
			remaining -= 1
			timer = interval          # 首次 delay 只作用一次
			return true
		return false


# ---------- 地图与坐标 ----------
var map_data := {}
var tile_size := 64
var width := 0
var height := 0
var path_grid: Array = []
var waypoints: Array = []
var castle_pos := Vector2.ZERO
var castle_grid := Vector2i.ZERO
var blocked := {}                        ## 「不可建塔」的格子集合，键为 Vector2i

# ---------- 局内资源 ----------
var castle_hp_level := 1
var initial_points_level := 1
var castle_hp := 0
var points := 0
var gold := 0
## 本关的开局点数补贴（地图数据 bonus_initial_points）：关卡越难给得越多
var bonus_initial_points := 0

# ---------- 波次与奖励 ----------
var waves: Array = []
var points_per_wave := 50
## 无尽模式每波的局内金币；普通关卡不用这个字段（改由 clear_gold 一局发一次）
var gold_reward := Config.ENDLESS_GOLD_PER_WAVE
## 普通关卡通关时一次性发放的金币（一局一笔，不按波次发）
var clear_gold := Config.CLEAR_GOLD
## 本关怪物血量倍率（地图数据 monster_hp_multiplier）：关卡1 是 1 倍
var monster_hp_multiplier := 1.0
## 无尽模式已跨过的里程碑档数（1 档 = 扛过 10 波）与已获得的里程碑金币总额
var endless_milestone := 0
var endless_bonus_gold := 0
var cards_per_wave := 3
var endless := false
var endless_hp_growth := 0.15
var monster_pool: Array = []
var card_pool: Array = []
var tower_pool: Array = []
var tower_levels := {}

# ---------- 运行时状态 ----------
var towers: Array = []
var monsters: Array = []
var projectiles: Array = []
var damage_texts: Array = []
var particles: Array = []
var lightning: Array = []
var thunder_loops := {}                  ## {tower: [AudioStreamPlayer, ...]}

var wave_index := 0
var current_events: Array = []
var wave_total := 0
var wave_remaining := 0
var current_offers: Array = []
var state := STATE_BUILD
var time := 0.0
var between_waves := 2.0                 ## 波间建塔阶段时长（秒）
var first_cleared := false

var card_manager := CardManager.new()
var selected_build_tower = null          ## 待放置的塔类型 id
var recycle_target = null                ## 右键选中的待回收塔（非空时显示确认弹窗）

## 选中塔 / 显示全部范围。用 setter 同步到塔节点的显示开关，
## 这样 UI 层只管改这两个值，不用手动刷新每座塔。
var selected_tower = null:
	set(value):
		selected_tower = value
		_sync_tower_visuals()
var show_all_ranges := false:
	set(value):
		show_all_ranges = value
		_sync_tower_visuals()

var game_speed := 1
var paused := false
var card_timer := 0.0
var card_duration := 10.0
var card_refreshed: Array = []
var show_collection := false

## 本局存档引用（结算时写回）
var save_data := {}


## 用地图数据与存档创建一局新游戏。
func setup(p_map_data: Dictionary, p_save_data: Dictionary) -> void:
	map_data = p_map_data
	save_data = p_save_data

	# 网格与坐标
	var grid: Dictionary = map_data.get("grid", {"width": 15, "height": 10, "tile_size": 64})
	tile_size = int(grid.get("tile_size", 64))
	width = int(grid.get("width", 15)) * tile_size
	height = int(grid.get("height", 10)) * tile_size

	# 路径网格坐标列表
	path_grid = []
	for p in map_data.get("path", []):
		path_grid.append(Vector2i(int(p["x"]), int(p["y"])))
	# 路径折线的像素坐标：把网格坐标转成格子中心点的像素坐标
	waypoints = []
	for g in path_grid:
		waypoints.append(Vector2(g.x * tile_size + tile_size / 2,
				g.y * tile_size + tile_size / 2))
	# 城堡位置：路径最后一个点
	castle_pos = waypoints[-1] if waypoints.size() > 0 else Vector2.ZERO
	castle_grid = path_grid[-1] if path_grid.size() > 0 else Vector2i.ZERO

	# 局内资源（使用存档里升级后的属性，再叠加本关的开局点数补贴）
	castle_hp_level = int(save_data.get("castle_hp_level", 1))
	initial_points_level = int(save_data.get("initial_points_level", 1))
	castle_hp = Config.castle_hp_for_level(castle_hp_level)
	bonus_initial_points = int(map_data.get("bonus_initial_points", 0))
	points = Config.initial_points_for_level(initial_points_level) + bonus_initial_points
	gold = 0
	endless_milestone = 0
	endless_bonus_gold = 0

	# 波次与奖励
	waves = map_data.get("waves", []).duplicate()
	points_per_wave = int(map_data.get("points_per_wave", 50))
	gold_reward = int(map_data.get("gold_reward", Config.ENDLESS_GOLD_PER_WAVE))
	# clear_gold 是现名，first_clear_gold 是旧数据里的键名（兼容读一次）
	clear_gold = int(map_data.get("clear_gold",
			map_data.get("first_clear_gold", Config.CLEAR_GOLD)))
	monster_hp_multiplier = float(map_data.get("monster_hp_multiplier", 1.0))
	cards_per_wave = int(map_data.get("cards_per_wave", 3))

	# 无限模式
	endless = bool(map_data.get("endless", false))
	endless_hp_growth = float(map_data.get("endless_hp_growth", 0.15))
	monster_pool = map_data.get("monster_pool", []).duplicate()

	card_pool = map_data.get("card_pool", []).duplicate()
	tower_pool = map_data.get("tower_pool", []).duplicate()
	tower_levels = save_data.get("tower_levels", {})

	# 注意：JSON 里的数字都是 float，tower_levels 的值要转回 int 才好比较
	for k in tower_levels.keys():
		tower_levels[k] = int(tower_levels[k])

	# 计算「不可建塔」的格子集合
	blocked = _build_blocked()


## 计算「不可建塔」的网格格集合。
##
## 包含两类：
## 1. 障碍物格子（直接整格禁用）；
## 2. 路径占用格子 —— 按 PATH_WIDTH 加宽：凡格子中心到路径折线的距离小于
##    「半宽 + 半格」都算路径，禁止建塔。
func _build_blocked() -> Dictionary:
	var result := {}
	# 障碍物：直接整格禁止建塔
	for ob in map_data.get("obstacles", []):
		result[Vector2i(int(ob["x"]), int(ob["y"]))] = true

	# 判定半径 = 路径半宽 + 半格
	var half := Config.PATH_WIDTH / 2.0 + tile_size / 2.0
	var gw := width / tile_size                        # 网格列数
	var gh := (height - Config.UI_HEIGHT) / tile_size  # 可建区域行数（不含底部 UI）
	for gx in range(gw):
		for gy in range(gh):
			var key := Vector2i(gx, gy)
			if result.has(key):
				continue
			if _dist_to_path(gx, gy) < half:
				result[key] = true
	return result


## 返回网格格 (gx, gy) 中心到路径折线的最短距离（像素）。
##
## 逐段计算「点到线段」的距离，取最小值；用于精确判断格子是否被路径覆盖。
func _dist_to_path(gx: int, gy: int) -> float:
	var p := Vector2(gx * tile_size + tile_size / 2.0,
			gy * tile_size + tile_size / 2.0)
	var best := INF
	for i in range(waypoints.size() - 1):
		var a: Vector2 = waypoints[i]
		var b: Vector2 = waypoints[i + 1]
		var d := b - a
		if d.x == 0.0 and d.y == 0.0:
			# 线段退化成单个点
			best = minf(best, p.distance_to(a))
		else:
			# 点到线段距离：先把点投影到线段所在直线，参数 t 截断到 [0,1]
			var t := ((p.x - a.x) * d.x + (p.y - a.y) * d.y) / (d.x * d.x + d.y * d.y)
			t = clampf(t, 0.0, 1.0)
			best = minf(best, p.distance_to(a + d * t))
	return best


## 把像素坐标转成网格格，判断该格是否能建塔（不在路径/障碍/城堡上）。
func is_buildable(px: float, py: float) -> bool:
	var g := Vector2i(int(px / tile_size), int(py / tile_size))
	if blocked.has(g):
		return false
	if g == castle_grid:
		return false
	return true


## 建塔位置校验：按塔的「占地」矩形判定，而非只看中心点。
##
## 塔立绘是站立着的：只有图片下半部分（塔基）真正落在地面上，上半部分悬空不占地面。
## 因此占地边界取图片的下半部分（宽 55、高 50，顶边为塔中心）。
##
## 规则：
## 1. 占地矩形整体必须在地图边界内，且不侵入底部 UI 区；
## 2. 占地矩形覆盖到的任意网格格不能是阻挡格（路径/障碍/城堡）；
## 3. 占地矩形不能与任何已有塔的占地矩形重叠。
func can_place_tower(x: float, y: float) -> bool:
	var hw := Config.TOWER_FOOTPRINT.x / 2.0   # 占地半宽
	var hh := Config.TOWER_FOOTPRINT.y / 2.0   # 占地半高（= 图片高的一半）
	var y_top := y                             # 占地顶边 = 塔中心
	var y_bottom := y + hh                     # 占地底边 = 图片底边
	var grid_w := width / tile_size
	var grid_h := (height - Config.UI_HEIGHT) / tile_size

	# 1) 边界：占地矩形不能越界，也不能压进底部 UI 区
	if x - hw < 0.0 or x + hw > width:
		return false
	if y_top < 0.0 or y_bottom > height - Config.UI_HEIGHT:
		return false

	# 2) 阻挡格：占地矩形覆盖到的格子，任一为路径/障碍/城堡即拒绝
	var gx0 := int((x - hw) / tile_size)
	var gx1 := mini(int((x + hw) / tile_size), grid_w - 1)
	var gy0 := int(y_top / tile_size)
	var gy1 := mini(int(y_bottom / tile_size), grid_h - 1)
	for gx in range(gx0, gx1 + 1):
		for gy in range(gy0, gy1 + 1):
			var key := Vector2i(gx, gy)
			if blocked.has(key):
				return false
			if key == castle_grid:
				return false

	# 3) 塔塔重叠：占地矩形轴对齐重叠（纵向区间 [y, y+hh]，故纵向间距 < hh 即重叠）
	for t in towers:
		if absf(t.x - x) < hw * 2.0 and absf(t.y - y) < hh:
			return false
	return true


# ---------- 塔 ----------
## 在 (x, y) 放置一座塔：校验点数与位置，成功则扣点数并加入场景。
func spawn_tower(tower_id: String, px: float, py: float) -> bool:
	var data = GameData.get_tower(tower_id)
	if data == null:
		return false
	var cost := int(data.get("build_cost", 50))
	if points < cost or not can_place_tower(px, py):
		return false

	var level := int(tower_levels.get(tower_id, 1))
	var levels: Array = data.get("levels", [])
	# 取当前等级对应的数值，等级越界则回退到第一级
	var level_data: Dictionary = levels[level - 1] if (level - 1 >= 0 and level - 1 < levels.size()) else levels[0]
	# 射程换算成像素：格数 × 格子边长
	var range_px := float(level_data.get("attack_range", data.get("attack_range", 3))) * tile_size

	points -= cost
	var tower: Tower = TOWER_SCENE.instantiate()
	add_child(tower)
	tower.setup(tower_id, data, level, level_data, px, py, range_px)
	tower.show_range = show_all_ranges
	towers.append(tower)
	return true


## 回收塔：按 TOWER_RECYCLE_RATIO 返还建造点数的整数部分，并从场景移除。
func recycle_tower(tower) -> int:
	if not towers.has(tower):
		return 0
	_stop_thunder_sfx(tower)
	var refund := int(tower.build_cost * Config.TOWER_RECYCLE_RATIO)
	towers.erase(tower)
	tower.queue_free()
	points += refund
	if selected_tower == tower:
		selected_tower = null
	return refund


## 所有塔冷却计时；冷却结束就索敌并开火，然后按攻速重置冷却。
func update_towers(dt: float) -> void:
	for tower in towers:
		tower.tick(dt)
		if tower.attack_cooldown <= 0.0:
			var target = pick_target(tower)
			if target != null:
				fire_tower(tower, target)
				# 用卡牌加成后的攻速计算下次开火间隔（1/攻速 = 冷却秒数）
				var aspd: float = card_manager.final_value(
						tower.base_attack_speed, "attack_speed", tower)
				tower.attack_cooldown = 1.0 / maxf(0.05, aspd)   # 攻速下限防除零
			else:
				tower.chain_hits = 0      # 没有目标：雷塔停止攻击
		_update_thunder_sfx(tower)


## 按雷塔当前命中的单位数，调整循环电流音效的声道数（与攻速无关）。
##
## 雷塔攻速很快，若每次开火都播一次音效会非常吵，因此改为「持续电流声」：
## 命中的单位数 = 循环音效的声道数。攻击暂停（无目标）则声道归零、停止音效。
func _update_thunder_sfx(tower) -> void:
	if tower.attack_element != "雷":
		return
	var hits := maxi(0, int(tower.chain_hits))
	if not thunder_loops.has(tower):
		thunder_loops[tower] = []
	var channels: Array = thunder_loops[tower]
	# 命中单位数变多：追加循环声道
	while channels.size() < hits:
		var ch := Audio.play_loop("thunder_attack")
		if ch == null:
			break
		channels.append(ch)
	# 命中单位数变少：停止多余的声道
	while channels.size() > hits:
		var ch = channels.pop_back()
		if ch != null:
			ch.stop()


## 停止并清理某座雷塔的循环电流音效声道。
func _stop_thunder_sfx(tower) -> void:
	if not thunder_loops.has(tower):
		return
	for ch in thunder_loops[tower]:
		if ch != null:
			ch.stop()
	thunder_loops.erase(tower)


## 停止所有雷塔的循环电流音效（波次结束/退出结算时调用）。
func stop_all_thunder_sfx() -> void:
	for chs in thunder_loops.values():
		for ch in chs:
			if ch != null:
				ch.stop()
	thunder_loops.clear()


## 按塔的 targeting 策略（血量多/血量少/随机）在射程内选目标。
func pick_target(tower):
	# 场上存活且还没漏怪的怪物
	var alive := []
	for m in monsters:
		if m.alive and not m.reached_castle:
			alive.append(m)
	if alive.is_empty():
		return null
	# 射程内的怪物
	var in_range := []
	for m in alive:
		if m.position.distance_to(tower.position) <= tower.range:
			in_range.append(m)
	if in_range.is_empty():
		return null

	match tower.targeting:
		"highest_hp":
			var best = in_range[0]
			for m in in_range:
				if m.hp > best.hp:
					best = m
			return best
		"lowest_hp":
			var best = in_range[0]
			for m in in_range:
				if m.hp < best.hp:
					best = m
			return best
	return in_range.pick_random()      # 默认：随机攻击


## 塔开火：计算卡牌加成后的伤害，按攻击模式发射投射物或释放连锁雷击。
func fire_tower(tower, target) -> void:
	# 用卡牌加成后的最终伤害
	var dmg: float = card_manager.final_value(tower.base_attack_power, "damage", tower)

	# 播放攻击音效：普通塔每次开火播一次；雷塔走循环电流音效（按命中单位数驱动）
	if tower.attack_element != "雷":
		Audio.play_sound("tower_attack")

	match tower.attack_mode:
		"chain":
			# 连锁雷击：不发射投射物，直接命中多个目标并播放雷击特效
			tower.chain_hits = fire_chain(tower, target, dmg)
		"pierce":
			# 穿透模式：发射直线飞行的投射物，可穿透多个怪物
			# 显式标注类型：target 是鸭子类型参数，不标注则推断不出 Vector2
			var direction: Vector2 = (target.position - tower.position).normalized()
			if direction == Vector2.ZERO:
				direction = Vector2.UP
			_add_projectile(tower.position, tower.attack_element, dmg, "linear", {
				"direction": direction, "pierce_radius": 16.0,
				"source_tower": tower, "max_distance": tower.range + 32.0,
				"pierce_count": tower.pierce_count,
			})
		_:
			# 普通模式：发射追踪目标的投射物，命中后可能触发 AOE
			_add_projectile(tower.position, tower.attack_element, dmg, "homing", {
				"target": target, "aoe_radius": tower.aoe_radius,
				"source_tower": tower,
			})


## 连锁雷击：无投射物，直接对主目标 + 射程内最近的若干目标结算伤害并打雷。
##
## 主目标走完整元素结算（附着/反应），额外目标走纯伤害（不附着、不触发新反应），
## 一次最多命中 max_targets 个目标。
func fire_chain(tower, target, dmg: float) -> int:
	# 主目标：完整元素结算
	Combat.resolve_hit(self, target, dmg, tower.attack_element,
			tower.position, tower.attack_type)
	_bolt(tower, target)
	# 额外目标：射程内按距离最近的存活怪物（排除主目标），最多 max_targets - 1 个
	var extra := []
	for m in monsters:
		if m.alive and not m.reached_castle and m != target \
				and m.position.distance_to(tower.position) <= tower.range:
			extra.append(m)
	extra.sort_custom(func(a, b):
		return a.position.distance_to(tower.position) < b.position.distance_to(tower.position))
	var hits := 1                        # 主目标已命中
	var limit := maxi(0, tower.max_targets - 1)
	for i in mini(limit, extra.size()):
		var m = extra[i]
		Combat.apply_pure_damage(self, m, dmg, tower.attack_element, tower.attack_type)
		_bolt(tower, m)
		hits += 1
	return hits


## 播放一次雷击特效：从塔到目标画一条闪电，并在目标处生成粒子。
func _bolt(tower, monster) -> void:
	var color: Color = Config.ELEMENT_COLORS.get(tower.attack_element,
			Color8(190, 110, 250))
	add_lightning(tower.x, tower.y, monster.x, monster.y, color)
	add_particle(monster.x, monster.y, color)


## 创建一个投射物节点并加入场景。
func _add_projectile(pos: Vector2, element: String, dmg: float,
		mode: String, opts: Dictionary) -> void:
	var p: Projectile = PROJECTILE_SCENE.instantiate()
	add_child(p)
	p.setup(pos.x, pos.y, element, dmg, Config.PROJECTILE_SPEED, mode, opts)
	projectiles.append(p)


## 推进所有投射物并结算命中（追踪命中 / 直线穿透命中 / AOE）。
func update_projectiles(dt: float) -> void:
	for p in projectiles:
		p.tick(dt)
		# 攻击类型：有发射塔就用塔的攻击类型，否则默认元素攻击
		var atk_type: String = p.source_attack_type()

		if p.arrived:
			# 追踪投射物到达目标：结算主命中
			if p.has_live_target():
				Combat.resolve_hit(self, p.target, p.base_damage, p.element,
						p.source_position(), atk_type)
				# 有 AOE 半径则在目标周围造成范围伤害（50% 威力）
				# 只在目标仍存活时触发，避免目标已死后子弹落空却仍爆炸
				if p.aoe_radius > 0.0:
					reaction_aoe(p.target, p.aoe_radius, p.base_damage * 0.5, p.element)
		elif p.mode == "linear":
			# 直线穿透投射物：找出路径上最近的一个未命中怪物
			var hit = null
			var best := INF
			for m in monsters:
				# 跳过死亡/漏怪/已被本投射物命中的怪物
				if not m.alive or m.reached_castle or p.hit_ids.has(m.db_id):
					continue
				if _projectile_hits_monster(p, m):
					var d: float = m.position.distance_to(p.position)
					if d < best:
						best = d
						hit = m
			if hit != null:
				p.hit_ids[hit.db_id] = true       # 记录已命中，防止重复
				p.hit_count += 1
				Combat.resolve_hit(self, hit, p.base_damage, p.element,
						p.source_position(), atk_type)
				# 达到最大穿透数则销毁投射物
				if p.pierce_count > 0 and p.hit_count >= p.pierce_count:
					p.alive = false

	# 过滤掉已消失的投射物
	var keep := []
	for p in projectiles:
		if p.alive:
			keep.append(p)
		else:
			p.queue_free()
	projectiles = keep


## 投射物命中判定：优先用精灵遮罩（去除透明像素）做像素级重叠，回退圆形半径。
func _projectile_hits_monster(p, m) -> bool:
	if m.masks.size() > 0:
		# 先做一次圆形粗筛：遮罩是 frame_width×frame_height 的矩形，
		# 离中心最远的像素距离是半对角线 sqrt((fw/2)²+(fh/2)²)，恒 <= radius+10
		# （radius = max(fw,fh)/2）。超出这个范围必定不重叠，省掉 25 次位查询。
		if m.position.distance_to(p.position) > m.radius + 10.0:
			return false
		var mask: Dictionary = m.masks[m.frame_index() % m.masks.size()]
		var bm: BitMap = mask["bitmap"]
		var size: Vector2i = bm.get_size()
		# 投射物是 5x5 的方块，左上角在 (p.x-2, p.y-2)，换算到遮罩坐标系
		var origin := Vector2i(
				int(p.x - 2.0 - (m.x - m.frame_width / 2.0)),
				int(p.y - 2.0 - (m.y - m.frame_height / 2.0)))
		for dy in 5:
			for dx in 5:
				var pt := origin + Vector2i(dx, dy)
				if pt.x < 0 or pt.y < 0 or pt.x >= size.x or pt.y >= size.y:
					continue
				if bm.get_bitv(pt):
					return true
		return false
	# 无遮罩：退化为圆形距离判定
	var pierce_radius: float = p.pierce_radius if p.pierce_radius > 0.0 else 8.0
	return m.position.distance_to(p.position) <= m.radius + maxf(1.0, pierce_radius * 0.4)


# ---------- 反应追加 ----------
## 感电连锁：从源怪物向最近的若干只怪物跳电，造成纯伤害（不触发新反应）。
func chain_lightning(source, chain_count: int, attack: float, element: String) -> void:
	# 候选目标：存活、非源怪物、未漏怪
	var candidates := []
	for m in monsters:
		if m.alive and m != source and not m.reached_castle:
			candidates.append(m)
	# 按到源怪物的距离从小到大排序，取最近的 chain_count 只
	candidates.sort_custom(func(a, b):
		return a.position.distance_to(source.position) < b.position.distance_to(source.position))
	for i in mini(chain_count, candidates.size()):
		var m = candidates[i]
		Combat.apply_pure_damage(self, m, attack * 0.75, element)  # 连锁伤害为 75% 威力
		add_particle(m.x, m.y, Color8(130, 200, 255))              # 蓝色闪电粒子


## 超载 AOE：对源怪物周围半径内的其他怪物造成纯伤害。
func reaction_aoe(source, radius: float, attack: float, element: String) -> void:
	if attack <= 0.0 or source == null:
		return
	for m in monsters:
		# 跳过死亡/漏怪/源怪物自身
		if not m.alive or m.reached_castle or m == source:
			continue
		if m.position.distance_to(source.position) <= radius:
			Combat.apply_pure_damage(self, m, attack, element)     # 范围伤害
			add_particle(m.x, m.y, Color8(255, 180, 80))           # 橙色爆炸粒子


## 超载击退：给怪物一个远离伤害来源的冲量（速度）。
func apply_reaction_knockback(monster, source_pos, strength: float) -> void:
	if source_pos == null:
		# 没有来源坐标时，假设来源在怪物左方一格，制造一个大致方向
		source_pos = Vector2(monster.x - 1.0, monster.y)
	var d: Vector2 = monster.position - source_pos
	if d.length() < 1e-3:
		# 怪物几乎就在来源点上：给一个默认向上方向，避免除零
		d = Vector2(0.0, -1.0)
	# 归一化方向 × 击退强度，作为冲量叠加给怪物
	monster.apply_knockback(d.normalized().x * strength, d.normalized().y * strength)


# ---------- 怪物与波次 ----------
## 把第 index 波的 groups 转成出怪事件列表，并统计本波怪物总数。
##
## 无尽模式：不读模板波，按「第 1 波 5 只、每波 +1、封顶 50 只、
## 每波随机 1~2 种怪混合」的规则生成出怪事件。
func setup_wave_events(index: int) -> void:
	if endless:
		_setup_endless_wave(index)
		return
	if index >= waves.size():
		return
	var wave: Dictionary = waves[index]
	current_events = []
	var total := 0
	for group in wave.get("groups", []):
		var count := maxi(1, int(round(int(group.get("count", 1)))))
		# 每个 group 转成一个 SpawnEvent（同种怪物、固定间隔、可有延迟）
		current_events.append(SpawnEvent.new(
				group.get("monster_id"), count,
				float(group.get("interval", 1.0)), float(group.get("delay", 0.0))))
		total += count
	wave_total = total
	wave_remaining = total


## 无尽模式出怪：第 1 波 5 只、之后每波 +1、封顶 50 只；每波随机 1~2 种怪混合。
func _setup_endless_wave(index: int) -> void:
	var pool := []
	for m in monster_pool:
		if GameData.get_monster(m) != null:
			pool.append(m)
	if pool.is_empty():
		pool = ["fire_slime"]                        # 兜底：怪物池为空时用默认怪
	var total := mini(5 + index, 50)                 # 第 1 波(index=0)=5，逐波 +1，封顶 50
	# 随机选 1~2 种怪（不超过池子大小）
	var kinds: Array = []
	if pool.size() >= 2 and randf() < 0.5:
		kinds = _random_sample(pool, 2)
	else:
		kinds = _random_sample(pool, 1)
	# 每种至少 1 只，其余随机分配到选中的种类上
	var counts := {}
	for m in kinds:
		counts[m] = 1
	for _i in range(maxi(0, total - kinds.size())):
		var pick = kinds.pick_random()
		counts[pick] += 1
	# 按种类生成出怪事件，依次错开时间（第一种出完再出第二种）
	var interval := 0.8
	var delay := 0.0
	current_events = []
	for monster_id in kinds:
		var count: int = counts[monster_id]
		current_events.append(SpawnEvent.new(monster_id, count, interval, delay))
		delay += count * interval
	wave_total = total
	wave_remaining = total


## 从数组里不重复地随机取 k 个（对应 Python 的 random.sample）。
func _random_sample(pool: Array, k: int) -> Array:
	var copy := pool.duplicate()
	copy.shuffle()
	return copy.slice(0, mini(k, copy.size()))


## 开始当前波：进入战斗状态并准备本波的出怪事件。
func start_wave() -> void:
	state = STATE_COMBAT
	setup_wave_events(wave_index)


## 推进所有出怪事件，事件到点就真正生成对应怪物。
func update_spawns(dt: float) -> void:
	for ev in current_events:
		if ev.update(dt):
			spawn_monster(ev.monster_id)


## 当前波怪物血量相对基础值的累乘倍率。
##
## 第 1 波为基础值；从第 2 波起，每波在上波基础上叠加 waves[i].hp_bonus。
## 无限模式下超出模板波后，按 endless_hp_growth 每波指数增长。
func wave_hp_multiplier(wave_index_: int) -> float:
	var mult := 1.0
	# 从第 0 波累乘到当前波（每波的 hp_bonus 逐波叠加）
	for i in range(mini(wave_index_ + 1, waves.size())):
		mult *= (1.0 + float(waves[i].get("hp_bonus", 0.0)))
	# 无限模式：超出模板波后，每多一波再乘 (1 + endless_hp_growth)
	if endless and wave_index_ >= waves.size():
		var extra := wave_index_ - waves.size() + 1
		mult *= pow(1.0 + endless_hp_growth, extra)
	return mult


## 本关当前波次的最终血量倍率 = 波次成长曲线 × 关卡难度倍率。
##
## 关卡难度倍率来自地图数据的 monster_hp_multiplier：关卡1 = 1 倍，
## 关卡2~5 依次 5/10/15/20 倍 —— 同一套史莱姆素材靠这个倍率拉出后期强度。
func total_hp_multiplier(wave_index_: int) -> float:
	return wave_hp_multiplier(wave_index_) * monster_hp_multiplier


## 生成一只怪物：按当前波血量倍率调整，并预加载碰撞遮罩。
func spawn_monster(monster_id: String) -> void:
	var data = GameData.get_monster(monster_id)
	if data == null:
		return
	var m: Monster = MONSTER_SCENE.instantiate()
	add_child(m)
	m.setup(monster_id, data, waypoints)
	var mult := total_hp_multiplier(wave_index)
	if mult != 1.0:
		m.max_hp *= mult
		m.hp = m.max_hp
	if not m.image_path.is_empty():
		# 有图片就预加载碰撞遮罩（切帧 + 去透明）
		m.masks = GameData.load_sprite_masks(
				m.image_path, m.frame_count, m.frame_width, m.frame_height,
				m.sprite_width, m.sprite_height)
	monsters.append(m)


## 推进所有怪物的更新（移动/动画/附着倒计时等）。
func update_monsters(dt: float) -> void:
	for m in monsters:
		m.tick(dt)


## 击杀结算：每只怪物只结算一次，加击杀点数、减剩余数、播放粒子/飘字。
func on_monster_killed(monster) -> void:
	if monster._rewarded:
		return
	monster._rewarded = true
	var color: Color = Config.ELEMENT_COLORS.get(monster.element, Color8(200, 200, 200))
	add_particle(monster.x, monster.y, color)        # 死亡粒子
	points += Config.KILL_POINTS                     # 击杀奖励点数
	if wave_remaining > 0:
		wave_remaining -= 1
	add_damage_text(monster.x, monster.y - monster.radius - 16.0,
			"+%d点" % Config.KILL_POINTS, Color8(120, 255, 160), 12)


## 漏怪结算：城堡扣 1 血，扣到 0 则本局失败。
func monster_reached_castle(monster) -> void:
	if monster._leaked:
		return
	monster._leaked = true
	castle_hp -= 1
	monster.alive = false
	monster.reached_castle = true
	if wave_remaining > 0:
		wave_remaining -= 1
	if castle_hp <= 0:
		castle_hp = 0
		state = STATE_LOSE


## 判断当前波是否结束：出怪事件已全部出完，且场上没有存活的未漏怪怪物。
func wave_finished() -> bool:
	if current_events.is_empty():
		return false
	for ev in current_events:
		if ev.remaining > 0:
			return false
	for m in monsters:
		if m.alive and not m.reached_castle:
			return false
	return true


# ---------- 卡牌 ----------
## 发波次奖励并弹出卡牌（测试/调试也复用此入口）。
##
## 金币按模式发放：无尽模式每波累计，普通模式不在此发（通关时统一结算）。
func start_card_phase() -> void:
	points += points_per_wave
	if endless:
		gold += gold_reward
	_open_card_offers()


## 从卡牌池随机抽出几张卡作为本次卡牌面板的选项。
func _open_card_offers() -> void:
	var pool := []
	for c in card_pool:
		if GameData.get_card(c) != null:
			pool.append(c)
	current_offers = _random_sample(pool, mini(cards_per_wave, pool.size()))
	card_refreshed = []
	for _i in current_offers.size():
		card_refreshed.append(false)
	card_timer = card_duration


## 无尽模式里程碑结算：扛过第 10/20/30/40... 波时各额外发一笔金币。
##
## waves_cleared 是「刚打完的这一波是第几波」（从 1 开始数）。
## 第 N 档的金额是 100 翻倍 N-1 次（100/200/400/800/...），各档累加发放。
## 返回本次发放的金币（没跨档则为 0）。
func _grant_endless_milestone(waves_cleared: int) -> int:
	if waves_cleared <= 0 or waves_cleared % Config.ENDLESS_MILESTONE_STEP != 0:
		return 0
	endless_milestone = waves_cleared / Config.ENDLESS_MILESTONE_STEP
	var bonus := Config.endless_milestone_bonus(endless_milestone)
	gold += bonus
	endless_bonus_gold += bonus
	# 城堡上方飘字提示，玩家不用盯 HUD 也能看到这笔奖励
	add_damage_text(castle_pos.x, castle_pos.y - 60.0,
			"里程碑 +%d 金币" % bonus, Config.COLOR_MONEY_GOLD, 18)
	return bonus


## 一波清完后结算：发点数；金币按模式发放。
##
## 普通关卡：每波只发局内点数，金币在通关时一次性发固定奖励（clear_gold）。
## 无尽模式：每波发 gold_reward，跨 10 波再发里程碑奖励，破城时统一结算。
func finish_wave() -> void:
	stop_all_thunder_sfx()
	points += points_per_wave
	if endless:
		# 无限模式：每波累计金币 + 跨过 10 波时的里程碑奖励，波次 +1 继续，直到城堡被攻破
		gold += gold_reward
		_grant_endless_milestone(wave_index + 1)
		wave_index += 1
		_open_card_offers()
		state = STATE_BUILD
		time = 0.0
	elif wave_index >= waves.size() - 1:
		# 普通模式最后一波：通关，一次性发放本局固定金币
		state = STATE_WIN
		gold += clear_gold
		first_cleared = true
	else:
		# 普通模式还有下一波：波次 +1，弹卡牌，回到建塔阶段（不发金币）
		wave_index += 1
		_open_card_offers()
		state = STATE_BUILD
		time = 0.0


## 购买第 index 张卡牌：校验合法性与点数，成功则扣点数并应用加成。
func buy_card(index: int) -> bool:
	if card_timer <= 0.0:
		return false
	if index < 0 or index >= current_offers.size():
		return false
	var card_id = current_offers[index]
	if card_id == null:
		return false
	var data = GameData.get_card(card_id)
	if data == null or points < int(data.get("price", 0)):
		return false
	points -= int(data["price"])
	card_manager.apply(data)
	current_offers[index] = null
	# 全部卡牌都买完后，提前关闭面板，不必等待倒计时结束
	var all_bought := true
	for c in current_offers:
		if c != null:
			all_bought = false
			break
	if all_bought:
		_close_card_panel()
	return true


## 把第 index 张卡牌刷新为随机新卡（尽量不与其他卡重复），每张限一次，消耗点数。
func refresh_card(index: int) -> bool:
	if card_timer <= 0.0:
		return false
	if index < 0 or index >= current_offers.size():
		return false
	if card_refreshed[index] or current_offers[index] == null:
		return false
	if points < Config.CARD_REFRESH_COST:
		return false
	var pool := []
	for c in card_pool:
		if GameData.get_card(c) != null:
			pool.append(c)
	var used := {}
	for c in current_offers:
		if c != null:
			used[c] = true
	# 优先选没出现的卡，若全部出现则回退到整个池
	var candidates := []
	for c in pool:
		if not used.has(c):
			candidates.append(c)
	if candidates.is_empty():
		candidates = pool
	current_offers[index] = candidates.pick_random()
	card_refreshed[index] = true
	points -= Config.CARD_REFRESH_COST
	return true


## 关闭卡牌面板：倒计时归零并清空选项。
func _close_card_panel() -> void:
	card_timer = 0.0
	current_offers = []


## 手动跳过卡牌选择（关闭面板，不等待倒计时结束）。
func skip_card_phase() -> void:
	_close_card_panel()


## 卡牌面板倒计时：按真实时间递减，不受快进（game_speed）影响。
##
## 与游戏逻辑固定步长（tick）解耦：快进只是把 tick 多调几次，
## 而卡牌选择时间应始终按真实秒数流逝，保证 2x/4x 快进时玩家
## 仍有完整的选择窗口，不会来不及选就被跳过。
func update_card_timer(real_dt: float) -> void:
	if card_timer > 0.0:
		card_timer -= real_dt
		if card_timer <= 0.0:
			card_timer = 0.0
			current_offers = []


## 结算存档：把本局累计金币写回存档。
##
## 普通关卡：仅胜利（grant_gold=true）发放通关金币。
## 无尽模式：没有「通关」，城堡被攻破（lose）即结束，按累计波次结算金币。
func finalize_save(grant_gold: bool = true) -> Dictionary:
	stop_all_thunder_sfx()
	if (endless and state == STATE_LOSE) or grant_gold:
		save_data["gold"] = int(save_data.get("gold", 0)) + gold
	return save_data


# ---------- 主更新 ----------
## 每帧主更新：按状态推进战斗或等待建塔。
##
## 卡牌面板倒计时不在这里推进，而是由 update_card_timer（真实时间）单独处理，
## 避免被快进倍率加速。
func tick(dt: float) -> void:
	time += dt

	if state == STATE_COMBAT:
		# 战斗状态：依次推进出怪、怪物、塔、投射物
		update_spawns(dt)
		update_monsters(dt)
		update_towers(dt)
		update_projectiles(dt)

		# 处理所有已到达城堡（漏怪）的怪物
		for m in monsters:
			if m.alive and m.reached_castle:
				monster_reached_castle(m)

		# 还没失败且本波结束，则结算本波
		if state != STATE_LOSE and wave_finished():
			finish_wave()
		_cleanup_monsters()

	elif state == STATE_BUILD:
		# 波间间隔：只延迟下一波出怪，已射出的子弹继续飞完（不冻结战斗）
		update_projectiles(dt)
		_cleanup_monsters()
		if time >= between_waves:
			start_wave()

	update_effects(dt)


## 移除已经彻底消失的怪物（死亡或漏怪），并回收其节点。
##
## Python 版把死怪永远留在列表里、只靠渲染器跳过绘制；节点化的版本必须真的回收，
## 否则无尽模式跑久了节点会无限累积。
##
## 安全性：本函数在 update_projectiles 之后调用，此时已没有任何投射物会在
## 本帧再访问这些怪物；跨帧仍持有引用的投射物一律通过
## Projectile.has_live_target() / source_position() 做 is_instance_valid 检查。
func _cleanup_monsters() -> void:
	if monsters.is_empty():
		return
	var keep := []
	for m in monsters:
		if m.alive and not m.reached_castle:
			keep.append(m)
		else:
			m.queue_free()
	monsters = keep


## 更新并清理飘字和粒子（生命周期结束就移除）。
## 注意 update() 返回的是 bool（是否还存活），不要再拿它和 0 比较。
func update_effects(dt: float) -> void:
	var texts := []
	for d in damage_texts:
		if d.update(dt):
			texts.append(d)
	damage_texts = texts

	var parts := []
	for p in particles:
		if p.update(dt):
			parts.append(p)
	particles = parts

	var bolts := []
	for l in lightning:
		if l.update(dt):
			bolts.append(l)
	lightning = bolts


## 在 (x, y) 添加一个伤害飘字。
func add_damage_text(px: float, py: float, text: String, color: Color, size: int = 14) -> void:
	damage_texts.append(Fx.DamageText.new(px, py, text, color, size))


## 在 (x, y) 添加一个粒子特效。
func add_particle(px: float, py: float, color: Color) -> void:
	particles.append(Fx.Particle.new(px, py, color))


## 在 (x1, y1) 到 (x2, y2) 之间添加一条雷击闪电特效。
func add_lightning(x1: float, y1: float, x2: float, y2: float,
		color: Color = Color8(190, 110, 250)) -> void:
	lightning.append(Fx.Lightning.new(x1, y1, x2, y2, color))


## 把选中态与显示范围同步到每座塔的显示开关上。
func _sync_tower_visuals() -> void:
	for t in towers:
		if t == null or not is_instance_valid(t):
			continue
		t.selected = (t == selected_tower)
		t.show_range = show_all_ranges
		t.queue_redraw()
