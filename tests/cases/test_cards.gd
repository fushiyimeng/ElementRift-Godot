extends RefCounted
## 校验卡牌系统 —— 对拍 src/cards.py
##
## 重点验证「纯加法」语义：多张同类卡的加成直接相加，不做复合乘法。
## 期望文案与数值来自 Python 版实际输出。


## 供 get_bonus 做作用范围判断的最小替身（只提供它读取的三个字段）
class StubTower extends RefCounted:
	var attack_element: String
	var attack_type: String
	var tower_id: String

	func _init(element: String, type: String, id: String) -> void:
		attack_element = element
		attack_type = type
		tower_id = id


func run(t) -> void:
	_test_describe(t)
	_test_additive(t)
	_test_scope_filtering(t)
	_test_apply_rejects(t)
	_test_summary(t)
	t.finish()


## describe_card 的文案要对拍 Python 版（含未知 scope 的兜底句式）
func _test_describe(t) -> void:
	t.check("describe global attack_speed",
			CardManager.describe_card({"scope": "global", "target": "all_towers",
					"stat": "attack_speed", "value": 0.10}),
			"攻击速度 +10%")
	t.check("describe element 火 damage 0.10",
			CardManager.describe_card({"scope": "element", "target": "火",
					"stat": "damage", "value": 0.10}),
			"火元素伤害 +10%")
	t.check("describe element 火 damage 0.25",
			CardManager.describe_card({"scope": "element", "target": "火",
					"stat": "damage", "value": 0.25}),
			"火元素伤害 +25%")
	t.check("describe attack_type",
			CardManager.describe_card({"scope": "attack_type", "target": "elemental",
					"stat": "damage", "value": 0.5}),
			"elemental·伤害 +50%")
	t.check("describe tower",
			CardManager.describe_card({"scope": "tower", "target": "fire_mage_tower",
					"stat": "damage", "value": 0.2}),
			"fire_mage_tower 伤害 +20%")
	t.check("describe 未知 scope 兜底",
			CardManager.describe_card({"scope": "unknown", "target": "x",
					"stat": "damage", "value": 0.05}),
			"伤害 +5%")
	# 未映射的 stat 原样显示，不崩
	t.check("describe 未映射 stat",
			CardManager.describe_card({"scope": "global", "target": "all",
					"stat": "unknown_stat", "value": 0.1}),
			"unknown_stat +10%")


## 核心语义：0.10 + 0.20 = 0.30（加法），不是 1.10 × 1.20 = 1.32（复利）
func _test_additive(t) -> void:
	var cm := CardManager.new()
	cm.apply({"scope": "element", "target": "火", "stat": "damage",
			"op": "mul", "value": 0.10})
	cm.apply({"scope": "element", "target": "火", "stat": "damage",
			"op": "mul", "value": 0.20})
	var tower := StubTower.new("火", "elemental", "fire_mage_tower")

	t.check_almost("累加结果 0.10+0.20", cm.get_bonus("damage", tower), 0.30)
	# 基础攻击力 60（fire_mage_tower Lv.1）→ 期望 60 × 1.30 = 78
	t.check_almost("final_value(60) = 78", cm.final_value(60.0, "damage", tower), 78.0)
	# 明确排除复利：若误用乘法会得到 79.2
	t.check_false("不是复利（79.2）",
			absf(cm.final_value(60.0, "damage", tower) - 79.2) < 1e-6)


## 作用范围过滤：global 全生效 / element 只匹配同元素 / tower 只匹配同 id
func _test_scope_filtering(t) -> void:
	var cm := CardManager.new()
	cm.apply({"scope": "global", "target": "all_towers", "stat": "damage",
			"op": "mul", "value": 0.05})          # 全局：对谁都生效
	cm.apply({"scope": "element", "target": "火", "stat": "damage",
			"op": "mul", "value": 0.10})          # 火系
	cm.apply({"scope": "element", "target": "水", "stat": "damage",
			"op": "mul", "value": 0.50})          # 水系
	cm.apply({"scope": "tower", "target": "fire_mage_tower", "stat": "damage",
			"op": "mul", "value": 0.20})          # 指定塔
	cm.apply({"scope": "attack_type", "target": "elemental", "stat": "damage",
			"op": "mul", "value": 0.02})          # 攻击类型

	var fire_tower := StubTower.new("火", "elemental", "fire_mage_tower")
	var water_tower := StubTower.new("水", "elemental", "water_mage_tower")

	# 火塔：0.05 + 0.10 + 0.20 + 0.02 = 0.37
	t.check_almost("火塔 damage 加成", cm.get_bonus("damage", fire_tower), 0.37)
	# 水塔：0.05 + 0.50 + 0.02 = 0.57（火系与指定塔的加成不生效）
	t.check_almost("水塔 damage 加成", cm.get_bonus("damage", water_tower), 0.57)
	# 不同 stat 互不干扰
	t.check_almost("火塔 attack_speed 加成为 0", cm.get_bonus("attack_speed", fire_tower), 0.0)

	# 按塔 id 的加成不会串到同元素的另一座塔
	var other_fire := StubTower.new("火", "elemental", "ice_mage_tower")
	t.check_almost("同元素不同塔 id 不吃 tower 加成",
			cm.get_bonus("damage", other_fire), 0.17)  # 0.05 + 0.10 + 0.02


## 非法卡牌应被拒绝：op 不是 mul、或数值为 0
func _test_apply_rejects(t) -> void:
	var cm := CardManager.new()
	t.check_false("op=add 被拒绝", cm.apply({"scope": "global", "target": "all",
			"stat": "damage", "op": "add", "value": 0.1}))
	t.check_false("value=0 被拒绝", cm.apply({"scope": "global", "target": "all",
			"stat": "damage", "op": "mul", "value": 0.0}))
	# op 缺省视为 mul，应被接受
	t.check_true("op 缺省按 mul 处理", cm.apply({"scope": "global", "target": "all",
			"stat": "damage", "value": 0.1}))
	t.check("被拒绝的卡不计入 purchased", cm.purchased.size(), 1)


## summary 按稀有度分组，同类 buff 合并计数
func _test_summary(t) -> void:
	var cm := CardManager.new()
	cm.apply({"name": "黄铜·火元素伤害", "rarity": "brass", "scope": "element",
			"target": "火", "stat": "damage", "op": "mul", "value": 0.10})
	cm.apply({"name": "黄铜·火元素伤害", "rarity": "brass", "scope": "element",
			"target": "火", "stat": "damage", "op": "mul", "value": 0.10})
	cm.apply({"name": "黄金·攻击速度", "rarity": "gold", "scope": "global",
			"target": "all_towers", "stat": "attack_speed", "op": "mul", "value": 0.30})

	var groups: Array = cm.summary()
	t.check("summary 分组数", groups.size(), 2)
	# 稀有度顺序固定：brass 在 gold 前
	t.check("第一组是 brass", groups[0]["rarity"], "brass")
	t.check("第二组是 gold", groups[1]["rarity"], "gold")
	# 同两张卡合并为一条 ×2、合计 20%
	t.check("brass 条目数", groups[0]["items"].size(), 1)
	t.check("brass 合并计数", groups[0]["items"][0]["count"], 2)
	t.check_almost("brass 合并总额", groups[0]["items"][0]["total"], 0.20)
	t.check("brass 描述按合并后数值生成",
			groups[0]["items"][0]["desc"], "火元素伤害 +20%")
	# 空管理器返回空数组
	t.check("空 summary", CardManager.new().summary(), [])
