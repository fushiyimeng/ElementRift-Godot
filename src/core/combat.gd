class_name Combat
extends RefCounted
## 战斗模块：伤害公式与元素反应解析 —— 移植自 src/combat.py
##
## 负责回答两件事：
## 1. 一次攻击能造成多少伤害 —— 由 defense_of / calculate_damage 负责；
## 2. 一次元素攻击命中怪物时，如何结算免疫、元素附着、元素反应及追加效果
##    —— 由 resolve_hit / apply_pure_damage 负责。
##
## 伤害结算顺序（重要）：
##     免疫优先 -> 防御减免（元素/物理）-> 固定减免（当前版本暂无）。
## 元素反应作为「攻击倍率」，在防御减免之前先乘入攻击力。
##
## 与 Python 版的差异：本文件所有函数都是 static，第一个参数 game 是调用方传入的
## 游戏对象（鸭子类型），用于回调 add_damage_text / chain_lightning /
## reaction_aoe / apply_reaction_knockback / on_monster_killed。


## 根据攻击类型选择怪物的防御值：物理攻击用物防，元素攻击用元素防御。
static func defense_of(monster, attack_type: String) -> float:
	if attack_type == "physical":
		return monster.defense_physical  # 物理攻击 -> 取物理防御
	return monster.defense_element       # 元素攻击 -> 取元素防御


## 核心伤害公式：把攻击力和防御值换算成最终伤害。
##
## 正防御时：伤害 = 攻击 × 100 / (防御 + 100)   （减伤，防御越高伤害越低）
## 负防御时：伤害 = 攻击 × (1 + |防御| / 100)   （增伤，负防御会放大伤害）
## 防御下限被限制在 -100，防止负防御过大导致伤害无限放大。
static func calculate_damage(attack: float, defense: float,
		flat_reduction: float = 0.0) -> float:
	# 防御值下限 -100，避免负防御过大导致伤害爆炸
	defense = maxf(-100.0, defense)
	var damage: float
	if defense >= 0.0:
		# 正防御：经典减伤公式（防御 100 时伤害减半）
		damage = attack * 100.0 / (defense + 100.0)
	else:
		# 负防御：线性增伤公式
		damage = attack * (1.0 + absf(defense) / 100.0)
	# 减去固定减免（当前版本传入 0，作为预留扩展）
	damage -= flat_reduction
	# 伤害不为负
	return maxf(0.0, damage)


## 对「额外目标」（感电连锁、超载 AOE）结算纯伤害。
##
## 这些额外目标：
## - 不施加元素附着；
## - 不触发新的元素反应；
## - 但仍遵循「免疫优先 + 防御公式」。
## 返回实际造成的伤害值。
static func apply_pure_damage(game, monster, attack: float, element: String,
		attack_type: String = "elemental") -> float:
	# 目标已死亡则直接跳过，不结算
	if not monster.alive:
		return 0.0
	# 免疫优先：目标免疫该元素则飘 MISS 并返回 0 伤害
	if element in monster.immune:
		game.add_damage_text(monster.x, monster.y - monster.radius - 8,
				Config.IMMUNE_DISPLAY, Color8(200, 200, 200))
		return 0.0

	# 按防御公式计算伤害并扣除怪物血量
	var damage := calculate_damage(attack, defense_of(monster, attack_type))
	monster.hp -= damage
	if damage > 0.0:
		game.add_damage_text(monster.x, monster.y - monster.radius - 8,
				str(int(round(damage))), Color8(255, 235, 150))
	# 血量扣到 0 或以下则判定死亡
	if monster.hp <= 0.0:
		monster.hp = 0.0
		monster.alive = false
		game.on_monster_killed(monster)  # 触发击杀结算（加点数、粒子、飘字等）

	return damage


## 对单个怪物施加一次元素攻击（塔/投射物的主命中）。
##
## 完整流程：免疫优先 -> 元素附着与反应判断 -> 伤害结算 -> 反应追加效果。
## 返回实际造成的伤害（反应倍率、免疫、防御均已计算在内）。
static func resolve_hit(game, monster, attack: float, element: String,
		source_pos = null, attack_type: String = "elemental") -> float:
	# 目标已死亡则直接跳过
	if not monster.alive:
		return 0.0

	# 1. 免疫优先：怪物免疫该元素时直接飘 MISS，不再做任何后续处理
	if element in monster.immune:
		game.add_damage_text(monster.x, monster.y - monster.radius - 8,
				Config.IMMUNE_DISPLAY, Color8(200, 200, 200))
		return 0.0

	# 2. 元素附着与反应判断
	var reaction = null  # 本次触发的反应定义（若无反应则为 null）
	var mult := 1.0      # 反应伤害倍率，默认 1（无反应时不变）

	if monster.attachment == null:
		# 怪物身上没有附着：直接打上本次元素的附着，并开始倒计时
		monster.attachment = {"element": element, "remaining": Config.ELEMENT_ATTACH_DURATION}
	elif monster.attachment["element"] == element:
		# 怪物身上已经是同种元素：只刷新附着持续时间（同元素不会触发反应）
		monster.attachment["remaining"] = Config.ELEMENT_ATTACH_DURATION
	else:
		# 怪物身上是不同元素：尝试触发元素反应
		# GDScript 没有元组，用「旧元素 + 新元素」拼接的字符串作反应表键
		var key: String = str(monster.attachment["element"]) + element
		# 需要反应冷却已结束，且该组合在反应表中才真正触发
		if monster.reaction_cooldown <= 0.0 and Config.REACTIONS.has(key):
			reaction = Config.REACTIONS[key]                    # 取反应定义
			mult = reaction["mult"]                             # 取反应伤害倍率
			monster.attachment = null                           # 反应后旧附着被消耗
			monster.reaction_cooldown = Config.REACTION_COOLDOWN  # 进入反应冷却
		else:
			# 冷却中或组合不在反应表：直接用新元素覆盖旧附着
			monster.attachment = {"element": element, "remaining": Config.ELEMENT_ATTACH_DURATION}

	# 3. 伤害结算（反应倍率已乘入攻击力，再走防御公式）
	var damage := calculate_damage(attack * mult, defense_of(monster, attack_type))
	monster.hp -= damage
	# 伤害飘字（数字往上飘、淡化消失）
	if damage > 0.0:
		game.add_damage_text(monster.x, monster.y - monster.radius - 8,
				str(int(round(damage))), Color8(255, 235, 150))
	# 血量扣到 0 或以下则判定死亡
	if monster.hp <= 0.0:
		monster.hp = 0.0
		monster.alive = false
		game.on_monster_killed(monster)

	# 3.5 冰元素控制效果：命中水系怪物冻结，其他怪物减速
	if element == "冰":
		if monster.element == "水":
			monster.apply_freeze(Config.FREEZE_DURATION)  # 冻结：完全无法移动
		else:
			monster.apply_slow(Config.SLOW_DURATION)      # 减速 20%

	# 4. 反应追加效果（只有在真正触发反应且造成了伤害时才执行）
	if reaction != null and damage > 0.0:
		if reaction.get("chain", 0) > 0:
			# 感电连锁：对附近怪物跳电造成纯伤害
			game.chain_lightning(monster, reaction["chain"], attack * mult, element)
		if reaction.get("aoe", 0) > 0:
			# 超载 AOE：对周围怪物造成范围伤害
			game.reaction_aoe(monster, reaction["aoe"], attack * mult, element)
		if reaction.get("knockback", 0) != 0:
			# 超载击退：把怪物推离伤害来源
			game.apply_reaction_knockback(monster, source_pos, reaction["knockback"])

	return damage
