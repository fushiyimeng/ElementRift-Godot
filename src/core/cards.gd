class_name CardManager
extends RefCounted
## 卡牌（Card）系统 —— 移植自 src/cards.py
##
## 只负责「卡牌数值」这一层，回答三个问题：
## 1. STAT_LABELS   —— 把英文的统计项名（damage / attack_speed）翻译成中文显示名；
## 2. CardManager   —— 管理玩家已经购买的卡牌，把每一张卡的加成按规则累加起来；
## 3. describe_card —— 根据卡牌的数据字段，自动拼出一句人类可读的中文描述。
##
## 核心规则（务必记住）：
##   - 所有加成只做「加法累加」，不做「复合乘法」；
##   - 最终属性 = 基础属性 × (1 + 所有相关加成之和)。

## 统计项的英文名 -> 中文显示名（用于卡牌描述和 UI 展示）
const STAT_LABELS := {"damage": "伤害", "attack_speed": "攻击速度"}

## 稀有度显示顺序（有才显示，没有跳过）
const RARITY_ORDER := ["brass", "silver", "gold", "prismatic"]

## 存储所有已购卡牌的累加结果。
## key 形如 "global:all:damage"、"element:火:damage"，value 是累加的百分比（0.10 表示 +10%）
var card_stats := {}
## 按购买顺序记录每张已购卡牌的数据（用于「已获取卡牌」面板展示数量与稀有度）
var purchased: Array = []


## 把一张卡牌的百分比加成累加进 card_stats，返回是否成功应用。
func apply(card: Dictionary) -> bool:
	# 取卡牌的加成数值（百分比），字段缺失则默认 0
	var value := float(card.get("value", 0.0))
	# 只接受「乘法类」（op == "mul"）且数值不为 0 的卡牌，其它类型/空加成直接忽略
	if card.get("op", "mul") != "mul" or value == 0.0:
		return false
	# 用 scope:target:stat 三个字段拼成唯一 key，方便之后按维度查找
	var key := "%s:%s:%s" % [card.get("scope"), card.get("target"), card.get("stat")]
	# 累加：如果已经存在同 key 的加成就叠加上去，否则从 0 开始
	card_stats[key] = card_stats.get(key, 0.0) + value
	purchased.append(card)  # 记录这张卡（展示用）
	return true


## 返回某座塔在指定 stat（属性）上的总加成（纯加法之和，如 0.25 表示 +25%）。
## tower 需要有 attack_element / attack_type / tower_id 三个属性
## （Python 版用 duck typing，这里同样不限定类型）。
func get_bonus(stat: String, tower) -> float:
	var total := 0.0
	# 遍历所有已累加的卡牌加成
	for key in card_stats:
		# 把 key 拆成 scope、target、s（stat）三部分（最多拆 2 次，防止 target 里含冒号）
		var parts := (key as String).split(":", true, 2)
		if parts.size() < 3:
			continue
		var scope := parts[0]
		var target := parts[1]
		var s := parts[2]
		# 统计项不匹配当前查询的属性，直接跳过
		if s != stat:
			continue
		var value: float = card_stats[key]
		# 根据作用范围判断该加成是否适用于这座塔
		match scope:
			"global":
				total += value  # 全局：所有塔都生效
			"element":
				if target == tower.attack_element:
					total += value  # 按元素：只对同元素塔生效
			"attack_type":
				if target == tower.attack_type:
					total += value  # 按攻击类型：只对同类型塔生效
			"tower":
				if target == tower.tower_id:
					total += value  # 按塔 id：只对该塔生效
	return total


## 计算最终属性值 = 基础值 × (1 + 加成之和)。
func final_value(base: float, stat: String, tower) -> float:
	return base * (1.0 + get_bonus(stat, tower))


## 汇总已获取卡牌，按稀有度分组返回展示数据。
##
## 返回 [{ "rarity", "items": [ { "name", "desc", "count", "total" } ] }]，
## 相同 scope:target:stat 的 buff 叠加为一条：count 是张数，total 是累加百分比。
func summary() -> Array:
	var grouped := {}
	for card in purchased:
		var rarity: String = card.get("rarity", "brass")
		var scope = card.get("scope")
		var target = card.get("target")
		var stat = card.get("stat")
		var value := float(card.get("value", 0.0))
		# 用数组当复合 key（GDScript 的 Dictionary 支持数组作键，按值比较）
		var key := [scope, target, stat]
		if not grouped.has(rarity):
			grouped[rarity] = {}
		var bucket: Dictionary = grouped[rarity]
		if not bucket.has(key):
			bucket[key] = {
				"name": card.get("name"), "scope": scope,
				"target": target, "stat": stat, "count": 0, "total": 0.0,
			}
		bucket[key]["count"] += 1
		bucket[key]["total"] += value

	var result := []
	for rarity in RARITY_ORDER:
		if not grouped.has(rarity):
			continue
		var items := []
		for info in grouped[rarity].values():
			# 用叠加后的数值重新生成描述（如「攻击速度 +20%」）
			var fake := {
				"scope": info["scope"], "target": info["target"],
				"stat": info["stat"], "value": info["total"],
			}
			items.append({
				"name": info["name"], "desc": describe_card(fake),
				"count": info["count"], "total": info["total"],
			})
		items.sort_custom(func(a, b): return a["name"] < b["name"])
		result.append({"rarity": rarity, "items": items})
	return result


## 根据卡牌字段自动拼接一句人类可读的中文描述（用于卡牌面板显示）。
static func describe_card(card: Dictionary) -> String:
	var scope = card.get("scope")              # 作用范围
	var target = card.get("target")            # 作用目标
	var stat = card.get("stat")                # 影响的属性
	var value := float(card.get("value", 0.0)) # 加成数值
	var pct := "%d%%" % [int(round(value * 100.0))]  # 把数值转成百分比字符串，如 0.1 -> "10%"
	var stat_name: String = STAT_LABELS.get(stat, stat)  # 属性英文名转中文（没有映射就原样显示）

	# 根据作用范围返回不同的描述句式
	match scope:
		"global":
			return "%s +%s" % [stat_name, pct]
		"element":
			return "%s元素%s +%s" % [target, stat_name, pct]
		"attack_type":
			return "%s·%s +%s" % [target, stat_name, pct]
		"tower":
			return "%s %s +%s" % [target, stat_name, pct]
	# 兜底：未知 scope 时也给出一个默认句式，避免 UI 空白
	return "%s +%s" % [stat_name, pct]
