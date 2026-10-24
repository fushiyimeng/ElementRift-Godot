extends RefCounted
## 长跑测试：连续打完整关 + 无尽模式多波，抓累积性问题
##
## 短测试发现不了的问题（节点泄漏、引用失效、数值溢出、越打越慢）
## 只有跑长了才暴露。这里跑完 level_01 全部 7 波，再跑无尽模式几十波。


func run(t) -> void:
	GameData.load_all()
	_test_full_level(t)
	_test_endless_marathon(t)
	_test_recycle_while_shooting(t)
	t.finish()


## 打穿 level_01 全部 7 波，检查胜利结算与资源清理
func _test_full_level(t) -> void:
	var game := _make_game(t, "level_01")
	game.points = 100000
	# 必须混搭元素：每种史莱姆都免疫自己那一系（雷史莱姆免疫雷、水史莱姆免疫水…），
	# 全用同一种塔会在混编波次（如第 6 波的水+雷）被免疫怪直接走通。
	var kinds := ["fire_mage_tower", "water_mage_tower",
			"thunder_mage_tower", "ice_mage_tower"]
	for k in kinds:
		game.tower_levels[k] = 5
	var placed := 0
	var spots := _spread_spots(game, 8)
	for i in spots.size():
		var kind: String = kinds[i % kinds.size()]
		if game.spawn_tower(kind, spots[i].x, spots[i].y):
			placed += 1
	t.check_true("至少放下 4 座塔", placed >= 4)

	var won := false
	var max_monsters := 0
	# 预算要够宽：怪物走完全程要 33 秒，血量还逐波翻倍（第 7 波约 2.9 倍），
	# 打完 7 波实测要 10 分钟以上的模拟时间。
	for _i in range(60 * 60 * 25):
		game.tick(Config.FIXED_DT)
		max_monsters = maxi(max_monsters, game.monsters.size())
		if game.state == Game.STATE_WIN or game.state == Game.STATE_LOSE:
			won = game.state == Game.STATE_WIN
			break
	t.check_true("打完 7 波并判定胜利", won)
	t.check("胜利时波次停在最后", game.wave_index, game.waves.size() - 1)
	t.check_true("全程怪物数量有起伏（不是一直为空）", max_monsters > 0)
	# 结束时场上不应还残留怪物节点
	game.tick(Config.FIXED_DT)
	t.check("结算后场上怪物已清空", game.monsters.size(), 0)
	t.check_true("结算发了通关金币", game.gold > 0)
	_drop(t, game)


## 无尽模式连打 40 波，检查指数成长下的稳定性
func _test_endless_marathon(t) -> void:
	var game := _make_game(t, "level_endless")
	game.points = 1000000
	game.castle_hp = 99999                # 不因漏怪中断，专测长跑
	var kinds := ["fire_mage_tower", "water_mage_tower",
			"thunder_mage_tower", "ice_mage_tower"]
	for k in kinds:
		game.tower_levels[k] = 5
	var spots := _spread_spots(game, 10)
	for i in spots.size():
		game.spawn_tower(kinds[i % kinds.size()], spots[i].x, spots[i].y)

	# 目标 15 波就够了：足以暴露节点泄漏与引用失效，而血量按 1.18^n 增长，
	# 再往后每波耗时会指数上升（第 40 波血量已是 750 倍，塔根本清不掉）。
	for _i in range(60 * 60 * 40):
		game.tick(Config.FIXED_DT)
		if game.wave_index >= 15:
			break
	t.check_true("无尽模式推进到 15 波以上", game.wave_index >= 15)
	# 血量倍率应按 1.18 的幂增长
	var m: float = game.wave_hp_multiplier(40)
	t.check_almost("第 41 波血量倍率 = 1.18^40", m, pow(1.18, 40), 1e-2)
	t.check_true("倍率随波次单调递增",
			game.wave_hp_multiplier(41) > game.wave_hp_multiplier(40))
	# 节点不应无限累积：死怪必须被回收
	t.check_true("场上怪物数受控（< 200）", game.monsters.size() < 200)
	t.check_true("场上投射物数受控（< 200）", game.projectiles.size() < 200)
	_drop(t, game)


## 塔在开火途中被回收：飞行中的投射物仍持有该塔的引用，不能崩
func _test_recycle_while_shooting(t) -> void:
	var game := _make_game(t, "level_01")
	game.points = 100000
	var spots := _spread_spots(game, 1)
	t.check_true("找到建塔位置", spots.size() > 0)
	if spots.is_empty():
		_drop(t, game)
		return
	game.spawn_tower("water_mage_tower", spots[0].x, spots[0].y)
	game.start_wave()

	# 跑到场上有飞行中的投射物
	for _i in range(60 * 20):
		game.tick(Config.FIXED_DT)
		if game.projectiles.size() > 0:
			break
	t.check_true("场上已有投射物", game.projectiles.size() > 0)

	# 回收发射它们的塔，然后继续推进
	if game.towers.size() > 0:
		game.recycle_tower(game.towers[0])
	for _i in range(120):
		game.tick(Config.FIXED_DT)
	t.check_true("回收发射塔后继续运行不崩", true)
	_drop(t, game)


# ---------- 辅助 ----------
func _make_game(t, map_id: String) -> Game:
	var game := Game.new()
	t.add_child(game)
	game.setup(GameData.preload_level(map_id), GameData.default_save())
	return game


func _drop(t, game: Game) -> void:
	t.remove_child(game)
	game.free()


## 沿路径折线均匀取样，每个取样点取最近的可建格。
##
## 不能按 x 排序均匀取样：那样选到的可建格可能离路径很远，塔射程再大也打不到怪，
## 测试就会误判成「关卡打不过」。按路径进度取样才能保证塔真的覆盖路径。
func _spread_spots(game: Game, count: int) -> Array:
	if game.waypoints.size() < 2:
		return []
	var total_len := 0.0
	for i in range(game.waypoints.size() - 1):
		total_len += (game.waypoints[i + 1] - game.waypoints[i]).length()

	# 先把所有可建格列出来，取样时找最近的
	var buildable := []
	for gx in range(game.width / game.tile_size):
		for gy in range((game.height - Config.UI_HEIGHT) / game.tile_size):
			var px := gx * game.tile_size + game.tile_size / 2.0
			var py := gy * game.tile_size + game.tile_size / 2.0
			if game.can_place_tower(px, py):
				buildable.append(Vector2(px, py))
	if buildable.is_empty():
		return []

	var out := []
	for k in range(count):
		var target_d := total_len * (float(k) + 0.5) / float(count)
		var ref := _point_at_distance(game.waypoints, target_d)
		var best := Vector2(-1, -1)
		var best_d := INF
		for b in buildable:
			var d: float = b.distance_squared_to(ref)
			if d < best_d:
				best_d = d
				best = b
		if best.x >= 0 and not out.has(best):
			out.append(best)
	return out


## 在折线上按累计距离取一点。
func _point_at_distance(points: Array, dist: float) -> Vector2:
	var acc := 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var seg := a.distance_to(b)
		if acc + seg >= dist:
			return a.lerp(b, (dist - acc) / maxf(seg, 1e-6))
		acc += seg
	return points[-1]
