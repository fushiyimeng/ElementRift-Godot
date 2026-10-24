extends RefCounted
## 关卡数据与难度曲线 —— 5 张普通关 + 无尽模式的设计规格
##
## 这里断言的不是「某张图长什么样」（那种断言改地图就要跟着改，没什么价值），
## 而是**每张图都必须满足的设计约束**：
##   1. 几何：路径与障碍都落在可建区内，障碍不压在路径上；
##   2. 难度：怪物血量倍率逐关递增，关卡 2~5 是 5/10/15/20 倍；
##   3. 波次：编号连续、怪物 id 都在本图怪物池里、总血量逐关递增但不失控；
##   4. 金币：普通关一局固定 100、无尽每波 100 + 每 10 波里程碑。
##
## 数值可以调，但调完必须让这里的约束继续成立（或者一起改）。

## 每张图的设计规格：波数、血量倍率、无尽标记、章节
const SPEC := {
	"level_01": {"waves": 7, "hp_multiplier": 1.0, "endless": false, "chapter": 1},
	"level_02": {"waves": 8, "hp_multiplier": 5.0, "endless": false, "chapter": 2},
	"level_03": {"waves": 9, "hp_multiplier": 10.0, "endless": false, "chapter": 3},
	"level_04": {"waves": 10, "hp_multiplier": 15.0, "endless": false, "chapter": 4},
	"level_05": {"waves": 12, "hp_multiplier": 20.0, "endless": false, "chapter": 5},
	"level_endless": {"waves": 1, "hp_multiplier": 1.0, "endless": true, "chapter": 6},
}

## 障碍中心到路径折线的最近距离下限（格）。
## 路径本身占 30px 宽（±1 格），再加一点视觉留白，低于这个值就算「压在路上了」。
const OBSTACLE_CLEARANCE := 4.0

## 1 级火塔对「穿过一次射程」的单只怪造成的伤害：
## 攻击 60 × 100/(元素防御 50 + 100) = 40 伤害/秒；射程 10 格 = 150px 半径，
## 怪物 80px/s 穿过 300px 直径需要 3.75 秒 → 约 150 伤害。
const TOWER_DAMAGE_PER_PASS := 150.0
## 关卡第 1 波的容忍系数：开局能摆下的塔至少要能打掉第 1 波这么多比例的血量，
## 否则玩家一进门就被打穿（这正是 20 倍关卡最初的问题）。
const FIRST_WAVE_TOLERANCE := 0.6


func run(t) -> void:
	GameData.load_all()
	_test_index(t)
	_test_spec(t)
	_test_geometry(t)
	_test_waves(t)
	_test_difficulty_curve(t)
	_test_gold(t)
	_test_first_wave_affordable(t)
	t.finish()


## 关卡列表：5 普通关在前、无尽模式在最后
func _test_index(t) -> void:
	var ids: Array = GameData.level_ids()
	t.check("关卡数量", ids.size(), 6)
	t.check("普通关在前、无尽在后", ids[-1], "level_endless")
	for i in range(SPEC.size()):
		var id: String = ids[i]
		t.check_true("关卡 id 已登记: %s" % id, SPEC.has(id))


## 波数与难度倍率符合设计规格
func _test_spec(t) -> void:
	for id in SPEC:
		var data: Dictionary = GameData.preload_level(id)
		var spec: Dictionary = SPEC[id]
		t.check("%s 波数" % id, data.get("waves", []).size(), spec["waves"])
		t.check_almost("%s 血量倍率" % id,
				float(data.get("monster_hp_multiplier", 1.0)), spec["hp_multiplier"])
		t.check("%s 无尽标记" % id,
				bool(data.get("endless", false)), spec["endless"])
		t.check("%s 章节" % id, int(data.get("chapter", 0)), spec["chapter"])
		t.check_true("%s 有怪物池" % id, data.get("monster_pool", []).size() > 0)


## 几何：路径与障碍都在可建区内（不能让路径钻到底部塔栏 UI 里），
## 且障碍块不压在路径上。
func _test_geometry(t) -> void:
	for id in SPEC:
		var data: Dictionary = GameData.preload_level(id)
		var grid: Dictionary = data.get("grid", {})
		var gw := int(grid.get("width", 0))
		var gh := int(grid.get("height", 0))
		# 可建区行数：网格高度减去底部 UI 死区（与 Game._build_blocked 同一算法）
		var playable_rows := int((gh * int(grid.get("tile_size", 1))
				- Config.UI_HEIGHT) / int(grid.get("tile_size", 1)))

		var path := _polyline(data.get("path", []))
		t.check_true("%s 路径至少 2 个点" % id, path.size() >= 2)
		t.check("%s 路径从屏幕左缘进场" % id, int(path[0].x) if not path.is_empty() else -1, 0)

		var in_bounds := true
		for p in path:
			if p.x < 0.0 or p.x >= gw or p.y < 0.0 or p.y >= playable_rows:
				in_bounds = false
		t.check_true("%s 路径全在可建区内" % id, in_bounds)

		var min_clearance := 999.0
		var obstacles_ok := true
		for ob in data.get("obstacles", []):
			var p := Vector2(float(ob["x"]), float(ob["y"]))
			if p.x < 0.0 or p.x >= gw or p.y < 0.0 or p.y >= playable_rows:
				obstacles_ok = false
			min_clearance = minf(min_clearance, _distance_to_polyline(p, path))
		t.check_true("%s 障碍全在可建区内" % id, obstacles_ok)
		t.check_true("%s 障碍不压路径（最近 %.1f 格）" % [id, min_clearance],
				min_clearance >= OBSTACLE_CLEARANCE)


## 波次数据：编号连续、出怪组合法、怪物都在本图池子里
func _test_waves(t) -> void:
	for id in SPEC:
		var data: Dictionary = GameData.preload_level(id)
		var pool: Array = data.get("monster_pool", [])
		var waves: Array = data.get("waves", [])
		var numbering_ok := true
		var groups_ok := true
		var pool_ok := true
		var bonus_ok := true
		for i in range(waves.size()):
			var w: Dictionary = waves[i]
			if int(w.get("wave", 0)) != i + 1:
				numbering_ok = false
			if float(w.get("hp_bonus", 0.0)) < 0.0:
				bonus_ok = false
			if w.get("groups", []).is_empty():
				groups_ok = false
			for g in w.get("groups", []):
				if int(g.get("count", 0)) < 1 or float(g.get("interval", 0.0)) <= 0.0:
					groups_ok = false
				if not pool.has(g.get("monster_id")):
					pool_ok = false
		t.check_true("%s 波次编号连续" % id, numbering_ok)
		t.check_true("%s 每波都有出怪组且参数合法" % id, groups_ok)
		t.check_true("%s 出怪 id 都在本图怪物池里" % id, pool_ok)
		t.check_true("%s hp_bonus 非负" % id, bonus_ok)
		# 最后一波不该比第一波还小
		t.check_true("%s 最后一波数量 >= 第一波" % id,
				_wave_count(waves[-1]) >= _wave_count(waves[0]))


## 难度曲线：血量倍率逐关递增，最后一波的总血量也要涨但别失控
func _test_difficulty_curve(t) -> void:
	var ids := ["level_01", "level_02", "level_03", "level_04", "level_05"]
	var prev_hp := 0.0
	var prev_mult := 0.0
	for i in range(ids.size()):
		var id: String = ids[i]
		var data: Dictionary = GameData.preload_level(id)
		var mult := _cumulative_hp_multiplier(data)
		var hp := _wave_hp_total(data, data.get("waves", []).size() - 1)
		if i == 0:
			t.check_almost("%s 是基准难度（1 倍）" % id,
					float(data.get("monster_hp_multiplier", 1.0)), 1.0)
		else:
			# 每关最后一波的有效血量倍率至少比上一关高 30%
			t.check_true("%s 有效倍率高于上一关（%.1f vs %.1f）" % [id, mult, prev_mult],
					mult >= prev_mult * 1.3)
			# 最后一波总血量：递增但不失控（不超过上一关 5 倍）
			t.check_true("%s 末波总血量高于上一关（%.0f vs %.0f）" % [id, hp, prev_hp],
					hp > prev_hp)
			t.check_true("%s 末波总血量未失控（%.1f 倍）" % [id, hp / prev_hp],
					hp <= prev_hp * 5.0)
		prev_hp = hp
		prev_mult = mult


## 金币：普通关一局固定 100（不按波次发），无尽模式每波 100 且通关金币为 0
func _test_gold(t) -> void:
	for id in SPEC:
		var data: Dictionary = GameData.preload_level(id)
		if bool(data.get("endless", false)):
			t.check("%s 每波金币" % id, int(data.get("gold_reward", 0)),
					Config.ENDLESS_GOLD_PER_WAVE)
			t.check("%s 不发放通关金币" % id, int(data.get("clear_gold", 0)), 0)
		else:
			t.check("%s 一局固定金币" % id, int(data.get("clear_gold", 0)),
					Config.CLEAR_GOLD)
			t.check("%s 不按波次发金币" % id, int(data.get("gold_reward", 0)), 0)


## 第 1 波不能一进门就打穿玩家：开局点数（1 级初始点数档位 + 本关补贴）
## 能摆下的 1 级火塔，必须能对第 1 波打出足够伤害。
func _test_first_wave_affordable(t) -> void:
	var tower_cost := 100.0                       # 火塔造价
	var base_points := float(Config.initial_points_for_level(1))   # 未升级的开局点数
	for id in SPEC:
		var data: Dictionary = GameData.preload_level(id)
		if bool(data.get("endless", false)):
			continue                              # 无尽模式本来是持久战，不套这条
		var points := base_points + float(data.get("bonus_initial_points", 0))
		var wave1: Dictionary = data.get("waves", [])[0]
		var count := float(_wave_count(wave1))
		var hp_total := _wave_hp_total(data, 0)
		var capacity := (points / tower_cost) * TOWER_DAMAGE_PER_PASS * count
		t.check_true("%s 开局打得动第 1 波（%.0f vs %.0f）" % [id, capacity, hp_total],
				capacity >= hp_total * FIRST_WAVE_TOLERANCE)


# ---------- 纯计算辅助 ----------

## 路径点列表 → Vector2 折线
func _polyline(points: Array) -> Array:
	var out := []
	for p in points:
		out.append(Vector2(float(p["x"]), float(p["y"])))
	return out


## 点到折线的最短距离（格）
func _distance_to_polyline(p: Vector2, line: Array) -> float:
	var best := INF
	for i in range(line.size() - 1):
		best = minf(best, _distance_to_segment(p, line[i], line[i + 1]))
	return best


## 点到线段的最短距离
func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 1e-9:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## 一波的怪物总数
func _wave_count(wave: Dictionary) -> int:
	var total := 0
	for g in wave.get("groups", []):
		total += int(g.get("count", 0))
	return total


## 该图第 index 波的怪物总血量（含本图倍率与逐波 hp_bonus）
func _wave_hp_total(data: Dictionary, index: int) -> float:
	var waves: Array = data.get("waves", [])
	var mult := float(data.get("monster_hp_multiplier", 1.0))
	var hp := 100.0          # monsters.json 里 4 只史莱姆的血量都是 100
	for i in range(mini(index + 1, waves.size())):
		hp *= (1.0 + float(waves[i].get("hp_bonus", 0.0)))
	return hp * mult * _wave_count(waves[index])


## 该图最后一波的有效血量倍率（波次曲线累乘 × 本图倍率）
func _cumulative_hp_multiplier(data: Dictionary) -> float:
	var mult := float(data.get("monster_hp_multiplier", 1.0))
	for w in data.get("waves", []):
		mult *= (1.0 + float(w.get("hp_bonus", 0.0)))
	return mult
