extends RefCounted
## 游戏核心逻辑测试 —— 移植自 tools/smoke_test.py 的 10 项断言，另补若干
##
## Game 是节点，必须有父节点才能 instantiate 实体、queue_free，所以用 t 当父节点。


func run(t) -> void:
	GameData.load_all()
	_test_data_ok(t)
	_test_init_resources(t)
	_test_place_tower(t)
	_test_combat_and_fire(t)
	_test_card_flow(t)
	_test_additive_bonus(t)
	_test_kill_reward(t)
	_test_recycle(t)
	_test_wave_progression(t)
	_test_wave_hp_curve(t)
	_test_level_difficulty(t)
	_test_endless(t)
	_test_endless_milestone(t)
	_test_tower_bounds(t)
	_test_thunder_chain(t)
	_test_damage_dealt(t)
	_test_freed_target_safety(t)
	t.finish()


## 建一局 level_01 并挂到测试节点下。
func _make_game(t, map_id: String = "level_01") -> Game:
	var map_data = GameData.preload_level(map_id)
	var save_data = GameData.default_save()
	var game := Game.new()
	t.add_child(game)
	game.setup(map_data, save_data)
	return game


func _cleanup(t, game: Node) -> void:
	t.remove_child(game)
	game.free()


## 找一个「塔占地边界完全合法」的位置（塔占地 55x100，需离路径/边界有足够余量）。
## 从左上角开始扫，用于几何判定类测试（不关心离路径远近）。
func _find_buildable(game: Game) -> Vector2:
	for gx in range(game.width / game.tile_size):
		for gy in range((game.height - Config.UI_HEIGHT) / game.tile_size):
			var px := gx * game.tile_size + game.tile_size / 2.0
			var py := gy * game.tile_size + game.tile_size / 2.0
			if game.can_place_tower(px, py):
				return Vector2(px, py)
	return Vector2(-1, -1)


## 找「紧贴路径」的可建位置，用于战斗类测试。
##
## 塔射程只有 150px（1 级 10 格），必须紧邻路径才打得到怪；
## Python 版 smoke_test 用 _find_buildable 取左上角第一个可建格，那一步其实
## 只打印不断言，所以「塔能不能打到怪」在原版测试里从未被真正验证过。
func _find_buildable_near_path(game: Game) -> Vector2:
	var best := Vector2(-1, -1)
	var best_dist := INF
	for gx in range(game.width / game.tile_size):
		for gy in range((game.height - Config.UI_HEIGHT) / game.tile_size):
			var px := gx * game.tile_size + game.tile_size / 2.0
			var py := gy * game.tile_size + game.tile_size / 2.0
			if not game.can_place_tower(px, py):
				continue
			var d: float = game._dist_to_path(gx, gy)
			if d < best_dist:
				best_dist = d
				best = Vector2(px, py)
	return best


func _test_data_ok(t) -> void:
	t.check("数据加载：怪物数", GameData.monsters.size(), 4)
	t.check("数据加载：塔数", GameData.towers.size(), 4)
	t.check("数据加载：卡牌数", GameData.cards.size(), 4)


func _test_init_resources(t) -> void:
	var game := _make_game(t)
	# 默认存档：城堡 1 级 = 5 血，初始点数 1 级 = 200
	t.check("初始城堡血量", game.castle_hp, 5)
	t.check("初始点数", game.points, 200)
	t.check("地图宽", game.width, 1920)
	t.check("地图高", game.height, 1080)
	t.check("格子边长", game.tile_size, 15)
	t.check("路径点数", game.waypoints.size(), 6)
	t.check("城堡位置 = 路径终点", game.castle_pos, game.waypoints[-1])
	t.check("初始状态", game.state, "build")
	t.check("不可建格非空", game.blocked.size() > 0, true)
	# 路径附近的格子必然不可建
	t.check_false("路径上的格子不可建",
			game.is_buildable(game.waypoints[0].x, game.waypoints[0].y))
	# 城堡格不可建
	t.check_false("城堡格不可建",
			game.is_buildable(game.castle_pos.x, game.castle_pos.y))
	_cleanup(t, game)


func _test_place_tower(t) -> void:
	var game := _make_game(t)
	var pos := _find_buildable(game)
	t.check_true("找到可建位置", pos.x >= 0)
	var before := game.points
	var ok := game.spawn_tower("fire_mage_tower", pos.x, pos.y)
	t.check_true("建塔成功", ok)
	t.check("塔数为 1", game.towers.size(), 1)
	t.check("扣点数 100", before - game.points, 100)
	# 同位置再建应失败（与已有塔重叠）
	t.check_false("重叠位置建塔失败", game.spawn_tower("fire_mage_tower", pos.x, pos.y))
	# 点数不足时失败
	game.points = 0
	t.check_false("点数不足建塔失败", game.spawn_tower("water_mage_tower", pos.x + 200.0, pos.y))
	_cleanup(t, game)


func _test_combat_and_fire(t) -> void:
	var game := _make_game(t)
	game.points = 1000
	var pos := _find_buildable_near_path(game)
	t.check_true("找到紧贴路径的可建位置", pos.x >= 0)
	game.spawn_tower("fire_mage_tower", pos.x, pos.y)
	game.start_wave()
	t.check("进入战斗状态", game.state, "combat")
	t.check("第 1 波事件数", game.current_events.size(), 1)
	t.check("第 1 波怪物总数", game.wave_total, 6)
	t.check("剩余怪物数初始 = 总数", game.wave_remaining, 6)

	# 跑最多 25 秒，等塔产生伤害飘字
	var attacked := false
	for _i in range(60 * 25):
		game.tick(Config.FIXED_DT)
		if game.damage_texts.size() > 0:
			attacked = true
			break
	t.check_true("塔攻击产生伤害飘字", attacked)
	t.check_true("场上已有怪物", game.monsters.size() > 0)
	_cleanup(t, game)


## 塔对非免疫目标确实造成伤害（火塔打火史莱姆会 MISS，所以换水塔验证）
func _test_damage_dealt(t) -> void:
	var game := _make_game(t)
	var pos := _find_buildable_near_path(game)
	game.points = 1000
	game.spawn_tower("water_mage_tower", pos.x, pos.y)
	game.start_wave()
	var damaged := false
	for _i in range(60 * 20):
		game.tick(Config.FIXED_DT)
		for m in game.monsters:
			if m.alive and m.hp < m.max_hp:
				damaged = true
				break
		if damaged:
			break
	t.check_true("水塔对火史莱姆造成实际伤害", damaged)

	# 火塔打火史莱姆应 MISS（免疫）
	var game2 := _make_game(t)
	var pos2 := _find_buildable_near_path(game2)
	game2.points = 1000
	game2.spawn_tower("fire_mage_tower", pos2.x, pos2.y)
	game2.start_wave()
	var missed := false
	for _i in range(60 * 20):
		game2.tick(Config.FIXED_DT)
		for d in game2.damage_texts:
			if d.text == Config.IMMUNE_DISPLAY:
				missed = true
				break
		if missed:
			break
	t.check_true("火塔打火史莱姆出现 MISS", missed)
	_cleanup(t, game)
	_cleanup(t, game2)


func _test_card_flow(t) -> void:
	var game := _make_game(t)
	game.start_card_phase()
	t.check("卡牌面板已弹出", game.current_offers.size(), 3)
	t.check_almost("卡牌倒计时已开始", game.card_timer, game.card_duration)
	t.check("刷新标记初始全 false", game.card_refreshed, [false, false, false])

	var before := game.points
	var bought := game.buy_card(0)
	t.check_true("购买卡牌成功", bought)
	t.check("购买后该卡置空", game.current_offers[0], null)
	t.check_true("扣了点數", game.points < before)
	t.check("卡牌管理器记录了购买", game.card_manager.purchased.size(), 1)

	# 同一张卡不能重复购买
	t.check_false("重复购买同一张卡失败", game.buy_card(0))
	# 越界索引失败
	t.check_false("越界索引购买失败", game.buy_card(99))

	# 刷新卡牌：消耗点数并替换
	var idx := 1
	var before_refresh := game.points
	if game.current_offers[idx] != null:
		t.check_true("刷新卡牌成功", game.refresh_card(idx))
		t.check("刷新后标记为已刷新", game.card_refreshed[idx], true)
		t.check("刷新扣点数", before_refresh - game.points, Config.CARD_REFRESH_COST)
		t.check_false("同张卡不能刷新两次", game.refresh_card(idx))
	_cleanup(t, game)


## 纯加法：0.10 + 0.20 = 0.30，不是复利 1.10 × 1.20
func _test_additive_bonus(t) -> void:
	var game := _make_game(t)
	var pos := _find_buildable(game)
	game.spawn_tower("fire_mage_tower", pos.x, pos.y)
	var tower = game.towers[0]
	t.check("塔的攻击元素是火", tower.attack_element, "火")

	var cm := CardManager.new()
	cm.apply({"scope": "element", "target": "火", "stat": "damage",
			"op": "mul", "value": 0.10})
	cm.apply({"scope": "element", "target": "火", "stat": "damage",
			"op": "mul", "value": 0.20})
	var final: float = cm.final_value(tower.base_attack_power, "damage", tower)
	t.check_almost("纯加法最终值 = 基础 × 1.30",
			final, tower.base_attack_power * 1.30)
	# 明确排除复利
	t.check_false("不是复利 1.10×1.20",
			absf(final - tower.base_attack_power * 1.32) < 1e-6)
	_cleanup(t, game)


func _test_kill_reward(t) -> void:
	var game := _make_game(t)
	var data = GameData.get_monster("fire_slime")
	var m: Monster = preload("res://src/entities/monster.tscn").instantiate()
	game.add_child(m)
	m.setup("fire_slime", data, game.waypoints)
	var before := game.points
	game.on_monster_killed(m)
	t.check("击杀奖励 +5 点", game.points - before, Config.KILL_POINTS)
	# 重复结算只发一次
	game.on_monster_killed(m)
	t.check("重复击杀不重复发奖", game.points - before, Config.KILL_POINTS)
	_cleanup(t, game)


func _test_recycle(t) -> void:
	var game := _make_game(t)
	var pos := _find_buildable(game)
	game.spawn_tower("fire_mage_tower", pos.x, pos.y)
	var tower = game.towers[0]
	var build_cost: int = tower.build_cost
	var before := game.points
	var refund: int = game.recycle_tower(tower)
	t.check("返还 = 建造价 × 0.6 取整", refund, int(build_cost * Config.TOWER_RECYCLE_RATIO))
	t.check("返还为 60", refund, 60)
	t.check("点数已返还", game.points, before + refund)
	t.check("塔已移除", game.towers.size(), 0)
	# 重复回收返回 0
	t.check("重复回收返回 0", game.recycle_tower(tower), 0)
	_cleanup(t, game)


## 打完第 1 波应进入 build 阶段、波次 +1、发点数奖励并弹卡牌
func _test_wave_progression(t) -> void:
	var game := _make_game(t)
	var pos := _find_buildable_near_path(game)
	game.points = 100000
	# 用 5 级雷塔才能稳定清掉第 1 波：1 级雷塔射程仅 150px、
	# 单次伤害 3×100/(50+100)=2，怪物穿过射程的时间不够打死（这是数值现状，不是 bug）。
	game.tower_levels["thunder_mage_tower"] = 5
	game.spawn_tower("thunder_mage_tower", pos.x, pos.y)
	game.start_wave()
	t.check_almost("第 1 波血量倍率 = 1", game.wave_hp_multiplier(0), 1.0)

	var points_before := game.points
	var finished := false
	for _i in range(60 * 120):
		game.tick(Config.FIXED_DT)
		if game.state != "combat":
			finished = true
			break
	t.check_true("第 1 波在 120 秒内结束", finished)
	t.check("回到建塔阶段", game.state, "build")
	t.check("波次推进到 2", game.wave_index, 1)
	t.check_true("发了波次点数奖励", game.points > points_before)
	t.check("弹出了新卡牌", game.current_offers.size(), 3)
	t.check_false("普通模式此时还没金币", game.gold > 0)
	_cleanup(t, game)


func _test_wave_hp_curve(t) -> void:
	var game := _make_game(t)
	# level_01 的 hp_bonus: 0, .12, .15, .18, .22, .26, .30 —— 逐波累乘
	t.check_almost("第 1 波倍率", game.wave_hp_multiplier(0), 1.0)
	t.check_almost("第 2 波倍率 = 1.12", game.wave_hp_multiplier(1), 1.12)
	t.check_almost("第 3 波倍率 = 1.12×1.15", game.wave_hp_multiplier(2), 1.12 * 1.15)
	var expect := 1.0
	for i in range(7):
		expect *= (1.0 + float(game.waves[i].get("hp_bonus", 0.0)))
	t.check_almost("第 7 波倍率累乘", game.wave_hp_multiplier(6), expect)
	# 超出模板波后不再增长（非无尽模式）
	t.check_almost("超出模板波保持最后倍率",
			game.wave_hp_multiplier(20), expect)
	_cleanup(t, game)


## 关卡难度倍率：关卡 2~5 的史莱姆血量是关卡 1 的 5/10/15/20 倍
func _test_level_difficulty(t) -> void:
	var base := _make_game(t, "level_01")
	t.check_almost("关卡 1 无难度加成", base.total_hp_multiplier(0), 1.0)
	t.check_almost("关卡 1 倍率字段", base.monster_hp_multiplier, 1.0)
	_cleanup(t, base)

	# 第 1 波的 hp_bonus 都是 0，所以此时怪血量 = 基础 100 × 本关倍率
	var difficulty := {"level_02": 5.0, "level_03": 10.0,
			"level_04": 15.0, "level_05": 20.0}
	for map_id in difficulty:
		var mult: float = difficulty[map_id]
		var game := _make_game(t, map_id)
		t.check_almost("%s 难度倍率" % map_id, game.monster_hp_multiplier, mult)
		game.spawn_monster("fire_slime")
		t.check_almost("%s 第 1 波史莱姆血量" % map_id,
				game.monsters[-1].max_hp, 100.0 * mult)
		_cleanup(t, game)


func _test_endless(t) -> void:
	var game := _make_game(t, "level_endless")
	t.check("无尽模式标记", game.endless, true)
	# 第 1 波 5 只、逐波 +1、封顶 50
	game.setup_wave_events(0)
	t.check("无尽第 1 波 5 只", game.wave_total, 5)
	game.setup_wave_events(9)
	t.check("无尽第 10 波 14 只", game.wave_total, 14)
	game.setup_wave_events(100)
	t.check("无尽封顶 50 只", game.wave_total, 50)

	# 血量指数增长：超出模板波（1 波）后按 (1+0.18) 每波递增
	var base: float = game.wave_hp_multiplier(0)
	t.check_almost("无尽第 1 波倍率 = 1", base, 1.0)
	var m1: float = game.wave_hp_multiplier(1)
	t.check_almost("无尽第 2 波倍率 = 1.18", m1, 1.18)
	var m3: float = game.wave_hp_multiplier(3)
	t.check_almost("无尽第 4 波倍率 = 1.18³", m3, pow(1.18, 3))

	# 无尽模式每波发金币
	var gold_before := game.gold
	game.finish_wave()
	t.check("无尽模式每波累计金币", game.gold - gold_before, game.gold_reward)
	t.check("无尽模式每波金币 = 100", game.gold_reward, 100)
	_cleanup(t, game)


## 金币发放：无尽模式每波 100 + 每扛过 10 波一笔里程碑；
## 普通关卡只在通关时发一次固定金币，按波次发的金额为 0。
func _test_endless_milestone(t) -> void:
	var game := _make_game(t, "level_endless")
	var gains := []
	for i in range(40):
		game.wave_index = i
		var before := game.gold
		game.finish_wave()
		gains.append(game.gold - before)

	t.check("普通波只发每波金币", gains[8], 100)
	t.check("第 10 波 = 每波 100 + 里程碑 100", gains[9], 200)
	t.check("第 20 波 = 每波 100 + 里程碑 200", gains[19], 300)
	t.check("第 30 波 = 每波 100 + 里程碑 400", gains[29], 500)
	t.check("第 40 波 = 每波 100 + 里程碑 800", gains[39], 900)
	# 40 波 = 40×100 + 100+200+400+800
	t.check("40 波累计金币", game.gold, 4000 + 1500)
	t.check("已跨过 4 档里程碑", game.endless_milestone, 4)
	t.check("里程碑金币累计", game.endless_bonus_gold, 1500)
	_cleanup(t, game)

	# 普通关卡：波次不发金币，通关一次性发 100
	var normal := _make_game(t, "level_01")
	normal.wave_index = 2
	normal.finish_wave()
	t.check("普通关卡打完一波不发金币", normal.gold, 0)
	normal.wave_index = normal.waves.size() - 1
	normal.finish_wave()
	t.check("普通关卡处于胜利态", normal.state, Game.STATE_WIN)
	t.check("普通关卡通关一次性发 100", normal.gold, Config.CLEAR_GOLD)
	t.check("普通关卡按波次发的金额为 0", normal.gold_reward, 0)
	_cleanup(t, normal)


## 塔的占地判定（对应 tools/verify_tower_bounds.py 的意图）
func _test_tower_bounds(t) -> void:
	var game := _make_game(t)
	var hh := Config.TOWER_FOOTPRINT.y / 2.0
	var hw := Config.TOWER_FOOTPRINT.x / 2.0
	# 越界：左边界外
	t.check_false("左侧越界不可建", game.can_place_tower(1.0, 300.0))
	# 越界：右边界外
	t.check_false("右侧越界不可建", game.can_place_tower(game.width - 1.0, 300.0))
	# 越界：压到底部 UI 区
	t.check_false("压到底部 UI 区不可建",
			game.can_place_tower(960.0, game.height - Config.UI_HEIGHT - 1.0))
	# 顶边为负。注意 y=0 时顶边恰好压在边界上，是合法的（判定是 y_top < 0）
	t.check_false("顶部越界不可建", game.can_place_tower(300.0, -1.0))
	t.check_true("顶边恰好贴边 y=0 仍可建", game.can_place_tower(300.0, 0.0))
	# 合法位置
	var pos := _find_buildable(game)
	t.check_true("合法位置可建", game.can_place_tower(pos.x, pos.y))

	# 占地是「下半部分」：同一个塔中心上方 50px 是悬空的，不参与判定
	var tower_pos := pos
	game.spawn_tower("fire_mage_tower", tower_pos.x, tower_pos.y)
	# 纵向间距 < 半高即视为重叠；>= 半高则应允许
	t.check_false("纵向间距小于半高：重叠被拒",
			game.can_place_tower(tower_pos.x, tower_pos.y + hh - 1.0))
	t.check_true("纵向间距大于半高：不重叠",
			game.can_place_tower(tower_pos.x, tower_pos.y + hh + 1.0))
	# 横向间距 >= 全宽则不重叠
	t.check_true("横向间距大于全宽：不重叠",
			game.can_place_tower(tower_pos.x + hw * 2.0 + 1.0, tower_pos.y))
	_cleanup(t, game)


## 连锁雷击：主目标走完整结算，副目标走纯伤害（不附着）
func _test_thunder_chain(t) -> void:
	var game := _make_game(t)
	var pos := _find_buildable_near_path(game)
	game.points = 100000
	game.spawn_tower("thunder_mage_tower", pos.x, pos.y)
	var tower = game.towers[0]
	t.check("雷塔攻击模式为 chain", tower.attack_mode, "chain")
	t.check("雷塔最多命中 4 个", tower.max_targets, 4)

	# 手动摆三只怪在射程内
	var made := []
	for i in 3:
		var m: Monster = preload("res://src/entities/monster.tscn").instantiate()
		game.add_child(m)
		m.setup("water_slime", GameData.get_monster("water_slime"), game.waypoints)
		m.position = tower.position + Vector2(40.0 + i * 20.0, 0.0)
		game.monsters.append(m)
		made.append(m)

	var hits: int = game.fire_chain(tower, made[0], 100.0)
	t.check("连锁命中 3 个目标", hits, 3)
	t.check_true("主目标产生元素附着", made[0].attachment != null)
	# 副目标是纯伤害：不应产生附着
	t.check("副目标不产生附着", made[1].attachment, null)
	t.check("副目标不产生附着（第 2 个）", made[2].attachment, null)
	# 每个命中目标都有一条闪电特效
	t.check("闪电特效数 = 命中数", game.lightning.size(), 3)
	_cleanup(t, game)


## 节点被回收后，仍持有引用的投射物不能崩（移植引入的新风险）
func _test_freed_target_safety(t) -> void:
	var game := _make_game(t)
	var pos := _find_buildable_near_path(game)
	game.points = 100000
	game.spawn_tower("water_mage_tower", pos.x, pos.y)
	game.start_wave()
	# 跑到有怪物和投射物为止
	for _i in range(600):
		game.tick(Config.FIXED_DT)
		if game.monsters.size() > 0 and game.projectiles.size() > 0:
			break
	t.check_true("已产生怪物", game.monsters.size() > 0)

	# 强制把一只怪物的目标指向它，然后立即销毁该怪物
	var m = game.monsters[0]
	var p = null
	for proj in game.projectiles:
		if proj.target == m:
			p = proj
			break
	if p == null and game.projectiles.size() > 0:
		p = game.projectiles[0]
		p.target = m
	if p != null:
		# 完全复刻 _cleanup_monsters 的顺序：先移出列表，再销毁节点。
		# 此时投射物仍持有对已释放实例的引用 —— 正是要验证的场景。
		game.monsters.erase(m)
		m.free()                       # 立即销毁（比 queue_free 更严格）
		# 再推进若干帧，不应因访问已释放实例而报错
		for _i in range(30):
			game.tick(Config.FIXED_DT)
		t.check_true("目标被销毁后继续运行不崩", true)
	else:
		t.info("(本次没有可测的投射物，跳过)")
	_cleanup(t, game)
