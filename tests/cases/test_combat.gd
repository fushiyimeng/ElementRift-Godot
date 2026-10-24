extends RefCounted
## 校验战斗结算 —— 对拍 src/combat.py
##
## 伤害表期望值来自 Python 版实际输出。
## 附着/反应/免疫部分用替身对象验证，不依赖 entities 层。


## 怪物替身：只提供 combat 读取的字段与方法
class StubMonster extends RefCounted:
	var alive := true
	var element := "火"
	var immune: Array = []
	var hp := 1000.0
	var max_hp := 1000.0
	var defense_element := 0.0
	var defense_physical := 0.0
	var attachment = null      # null 或 {"element": str, "remaining": float}
	var reaction_cooldown := 0.0
	var x := 0.0
	var y := 0.0
	var radius := 10
	var frozen := 0.0
	var slow_timer := 0.0

	func apply_freeze(duration: float) -> void:
		frozen = maxf(frozen, duration)

	func apply_slow(duration: float) -> void:
		slow_timer = maxf(slow_timer, duration)


## 游戏替身：记录 combat 触发的各种回调，供断言检查
class StubGame extends RefCounted:
	var texts: Array = []
	var chained: Array = []
	var aoes: Array = []
	var knockbacks: Array = []
	var killed: Array = []

	func add_damage_text(_x, _y, text, _color) -> void:
		texts.append(text)

	func chain_lightning(source, count, attack, element) -> void:
		chained.append([source, count, attack, element])

	func reaction_aoe(source, radius, attack, element) -> void:
		aoes.append([source, radius, attack, element])

	func apply_reaction_knockback(monster, source_pos, strength) -> void:
		knockbacks.append([monster, source_pos, strength])

	func on_monster_killed(monster) -> void:
		killed.append(monster)


func run(t) -> void:
	_test_damage_table(t)
	_test_defense_of(t)
	_test_immune(t)
	_test_attachment(t)
	_test_same_element_refresh(t)
	_test_reaction_vaporize(t)
	_test_reaction_cooldown(t)
	_test_reaction_overload(t)
	_test_reaction_electro_charge(t)
	_test_ice_cc(t)
	_test_death(t)
	_test_pure_damage(t)
	t.finish()


## 伤害公式逐点对拍 Python：正防减伤、负防增伤、防御下限 -100
func _test_damage_table(t) -> void:
	var cases := [
		[100.0, 0.0, 100.0],
		[100.0, 50.0, 66.66666666666667],
		[100.0, 100.0, 50.0],
		[100.0, -50.0, 150.0],
		[60.0, 50.0, 40.0],
		[3.0, 100.0, 1.5],
		[100.0, -100.0, 200.0],
		[100.0, -200.0, 200.0],   # 防御下限钳到 -100，故与 -100 同值
		[0.0, 100.0, 0.0],
		[100.0, 1000.0, 9.090909090909092],
	]
	for c in cases:
		t.check_almost("calculate_damage(%s, %s)" % [c[0], c[1]],
				Combat.calculate_damage(c[0], c[1]), c[2], 1e-9)
	# 固定减免
	t.check_almost("calculate_damage(100, 50, flat=10)",
			Combat.calculate_damage(100.0, 50.0, 10.0), 56.66666666666667, 1e-9)
	# 减免大于伤害时不出现负伤害
	t.check_almost("减免超额不返回负数",
			Combat.calculate_damage(10.0, 0.0, 999.0), 0.0)


func _test_defense_of(t) -> void:
	var m := StubMonster.new()
	m.defense_element = 50.0
	m.defense_physical = 100.0
	t.check_almost("元素攻击取元素防御",
			Combat.defense_of(m, "elemental"), 50.0)
	t.check_almost("物理攻击取物理防御",
			Combat.defense_of(m, "physical"), 100.0)


## 免疫优先：打免疫元素只飘 MISS，不附着、不扣血、不触发反应
func _test_immune(t) -> void:
	var g := StubGame.new()
	var m := StubMonster.new()
	m.immune = ["火"]
	var dmg := Combat.resolve_hit(g, m, 100.0, "火")
	t.check_almost("免疫伤害为 0", dmg, 0.0)
	t.check_almost("免疫不扣血", m.hp, 1000.0)
	t.check("免疫飘字为 MISS", g.texts, ["MISS"])
	t.check("免疫不产生附着", m.attachment, null)


## 首次命中：打上附着并开始倒计时
func _test_attachment(t) -> void:
	var g := StubGame.new()
	var m := StubMonster.new()
	var dmg := Combat.resolve_hit(g, m, 100.0, "火")
	t.check_almost("无防御时伤害等于攻击力", dmg, 100.0)
	t.check_almost("扣血正确", m.hp, 900.0)
	t.check_true("产生附着", m.attachment != null)
	if m.attachment != null:
		t.check("附着元素", m.attachment["element"], "火")
		t.check_almost("附着时长", m.attachment["remaining"],
				Config.ELEMENT_ATTACH_DURATION)


## 同元素再命中：只刷新持续时间，不触发反应
func _test_same_element_refresh(t) -> void:
	var g := StubGame.new()
	var m := StubMonster.new()
	Combat.resolve_hit(g, m, 100.0, "火")
	m.attachment["remaining"] = 1.0            # 手动消耗一部分时长
	Combat.resolve_hit(g, m, 100.0, "火")
	t.check_almost("同元素刷新附着时长", m.attachment["remaining"],
			Config.ELEMENT_ATTACH_DURATION)
	t.check_almost("同元素按原倍率结算（无反应）", m.hp, 800.0)
	t.check_almost("同元素不进入反应冷却", m.reaction_cooldown, 0.0)


## 火 -> 水 = 蒸发，倍率 1.5，反应后清空附着并进入冷却
func _test_reaction_vaporize(t) -> void:
	var g := StubGame.new()
	var m := StubMonster.new()
	Combat.resolve_hit(g, m, 100.0, "火")       # 先附着火
	var dmg := Combat.resolve_hit(g, m, 100.0, "水")  # 再打水 -> 蒸发
	t.check_almost("蒸发倍率 1.5", dmg, 150.0)
	t.check("蒸发后清空附着", m.attachment, null)
	t.check_almost("蒸发进入反应冷却", m.reaction_cooldown, Config.REACTION_COOLDOWN)
	t.check_almost("总扣血 100+150", m.hp, 750.0)
	t.check_false("蒸发无连锁", g.chained.size() > 0)
	t.check_false("蒸发无 AOE", g.aoes.size() > 0)
	t.check_false("蒸发无击退", g.knockbacks.size() > 0)


## 冷却期内不触发反应：新元素直接覆盖附着，按原倍率结算
func _test_reaction_cooldown(t) -> void:
	var g := StubGame.new()
	var m := StubMonster.new()
	m.attachment = {"element": "火", "remaining": 3.0}
	m.reaction_cooldown = Config.REACTION_COOLDOWN   # 处于冷却中
	var dmg := Combat.resolve_hit(g, m, 100.0, "水")
	t.check_almost("冷却期按原倍率结算", dmg, 100.0)
	t.check_true("冷却期新元素覆盖附着", m.attachment != null)
	if m.attachment != null:
		t.check("覆盖为新元素", m.attachment["element"], "水")


## 火 -> 雷 = 超载，倍率 2.0，带 AOE(90) 与击退(110)，无连锁
func _test_reaction_overload(t) -> void:
	var g := StubGame.new()
	var m := StubMonster.new()
	Combat.resolve_hit(g, m, 100.0, "火")
	var dmg := Combat.resolve_hit(g, m, 100.0, "雷")
	t.check_almost("超载倍率 2.0", dmg, 200.0)
	t.check("超载触发 AOE 一次", g.aoes.size(), 1)
	if g.aoes.size() == 1:
		t.check_almost("AOE 半径 90", g.aoes[0][1], 90.0)
		t.check_almost("AOE 伤害为攻击力×倍率", g.aoes[0][2], 200.0)
		t.check("AOE 元素", g.aoes[0][3], "雷")
	t.check("超载触发击退一次", g.knockbacks.size(), 1)
	if g.knockbacks.size() == 1:
		t.check_almost("击退强度 110", g.knockbacks[0][2], 110.0)
	t.check("超载无连锁", g.chained.size(), 0)


## 水 -> 雷 = 感电，倍率 1.5，连锁 2 只，无 AOE 无击退
func _test_reaction_electro_charge(t) -> void:
	var g := StubGame.new()
	var m := StubMonster.new()
	Combat.resolve_hit(g, m, 100.0, "水")
	var dmg := Combat.resolve_hit(g, m, 100.0, "雷")
	t.check_almost("感电倍率 1.5", dmg, 150.0)
	t.check("感电触发连锁一次", g.chained.size(), 1)
	if g.chained.size() == 1:
		t.check("连锁数量 2", g.chained[0][1], 2)
		t.check_almost("连锁伤害基数为攻击力×倍率", g.chained[0][2], 150.0)
		t.check("连锁元素", g.chained[0][3], "雷")
	t.check("感电无 AOE", g.aoes.size(), 0)
	t.check("感电无击退", g.knockbacks.size(), 0)


## 冰系控制：打水系怪冻结，打其它系减速
func _test_ice_cc(t) -> void:
	# 水系怪 -> 冻结
	var g1 := StubGame.new()
	var water := StubMonster.new()
	water.element = "水"
	Combat.resolve_hit(g1, water, 100.0, "冰")
	t.check_almost("冰打水系怪触发冻结", water.frozen, Config.FREEZE_DURATION)
	t.check_almost("冰打水系怪不减速", water.slow_timer, 0.0)

	# 非水系怪 -> 减速
	var g2 := StubGame.new()
	var fire := StubMonster.new()
	fire.element = "火"
	Combat.resolve_hit(g2, fire, 100.0, "冰")
	t.check_almost("冰打非水系怪触发减速", fire.slow_timer, Config.SLOW_DURATION)
	t.check_almost("冰打非水系怪不冻结", fire.frozen, 0.0)

	# 冻结取较大值（不缩短已有的更长冻结）
	var g3 := StubGame.new()
	var m3 := StubMonster.new()
	m3.element = "水"
	m3.frozen = 5.0
	Combat.resolve_hit(g3, m3, 100.0, "冰")
	t.check_almost("冻结取较大值", m3.frozen, 5.0)

	# 非冰元素不触发控制
	var g4 := StubGame.new()
	var m4 := StubMonster.new()
	Combat.resolve_hit(g4, m4, 100.0, "火")
	t.check_almost("火不触发冻结", m4.frozen, 0.0)
	t.check_almost("火不触发减速", m4.slow_timer, 0.0)


## 致死命中：血量归零、标记死亡、回调击杀结算
func _test_death(t) -> void:
	var g := StubGame.new()
	var m := StubMonster.new()
	m.hp = 50.0
	var dmg := Combat.resolve_hit(g, m, 100.0, "火")
	t.check_almost("伤害按溢出前计算", dmg, 100.0)
	t.check_almost("血量钳到 0", m.hp, 0.0)
	t.check_false("标记为死亡", m.alive)
	t.check("触发击杀回调一次", g.killed.size(), 1)

	# 已死亡的怪再被命中：直接返回 0
	var g2 := StubGame.new()
	var dead := StubMonster.new()
	dead.alive = false
	t.check_almost("已死亡目标不再结算", Combat.resolve_hit(g2, dead, 100.0, "火"), 0.0)
	t.check("已死亡目标无飘字", g2.texts.size(), 0)


## 纯伤害（感电连锁 / 超载 AOE 的副目标）：不附着、不触发反应，但吃免疫与防御
func _test_pure_damage(t) -> void:
	var g := StubGame.new()
	var m := StubMonster.new()
	Combat.apply_pure_damage(g, m, 100.0, "水")
	t.check_almost("纯伤害扣血", m.hp, 900.0)
	t.check("纯伤害不产生附着", m.attachment, null)
	t.check_almost("纯伤害不进入反应冷却", m.reaction_cooldown, 0.0)

	# 免疫仍然生效
	var g2 := StubGame.new()
	var immune := StubMonster.new()
	immune.immune = ["雷"]
	t.check_almost("纯伤害也遵循免疫", Combat.apply_pure_damage(g2, immune, 100.0, "雷"), 0.0)
	t.check("纯伤害免疫飘 MISS", g2.texts, ["MISS"])

	# 防御参与结算
	var g3 := StubGame.new()
	var tanky := StubMonster.new()
	tanky.defense_element = 100.0
	t.check_almost("纯伤害走防御公式",
			Combat.apply_pure_damage(g3, tanky, 100.0, "水"), 50.0)
