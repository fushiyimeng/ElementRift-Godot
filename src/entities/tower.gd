class_name Tower
extends Node2D
## 防御塔实体 —— 移植自 src/entities.py 的 Tower
##
## 固定在某个位置，按攻击速度自动索敌并发射投射物。
## 使用方式：instantiate() -> add_child() -> setup()。

## 与 Python 版一致：用 x/y 暴露坐标，内部落在 Node2D 的 position 上。
var x: float:
	get: return position.x
	set(value): position.x = value
var y: float:
	get: return position.y
	set(value): position.y = value

var tower_id := ""
## 显示名。注意不能叫 name —— 那是 Node 的内置属性。
var display_name := ""
var attack_element := ""
var attack_type := "elemental"          ## 攻击类型（elemental/physical）
var attack_mode := "single"             ## 攻击模式（single/aoe/pierce/chain）
var targeting := "random"               ## 索敌策略（random/highest_hp/lowest_hp）
var aoe_radius := 0.0                   ## AOE 爆炸半径（0 表示无）
var pierce_count := 0                   ## 穿透数量（0 表示不穿透）
var max_targets := 1                    ## 单次攻击最多命中的目标数（连锁雷击用）
var build_cost := 50                    ## 建造价格（局内点数）
var image_path := ""

var level := 1
var base_attack_power := 50.0           ## 当前等级的基础攻击力
var base_attack_speed := 1.0            ## 当前等级的基础攻速（次/秒）
var range := 100.0                      ## 攻击射程（像素）
var radius := Config.TOWER_RADIUS       ## 视觉半径（画色块/选中圈用）
var color := Color.WHITE                ## 元素对应颜色
var attack_cooldown := 0.0              ## 攻击冷却剩余时间
var chain_hits := 0                     ## 本次攻击命中的单位数（雷塔循环音效用）

## 由 game/renderer 控制的显示开关
var show_range := false                 ## 是否画攻击范围圈
var selected := false                   ## 是否被选中（画白色高亮圈）

var _texture: Texture2D = null


func _ready() -> void:
	_apply_sprite()


## 用塔数据创建一座塔。
func setup(p_tower_id: String, data: Dictionary, p_level: int,
		level_data: Dictionary, px: float, py: float, range_px: float) -> void:
	tower_id = p_tower_id
	display_name = data.get("name", p_tower_id)
	attack_element = data.get("attack_element", "")
	attack_type = data.get("attack_type", "elemental")
	attack_mode = data.get("attack_mode", "single")
	targeting = data.get("targeting", "random")
	aoe_radius = float(data.get("aoe_radius", 0.0))
	pierce_count = int(data.get("pierce_count", 0))
	max_targets = int(data.get("max_targets", 1))
	build_cost = int(data.get("build_cost", 50))
	image_path = data.get("image", "")

	level = p_level
	# 当前等级的攻击力/攻速（优先取 level_data，缺省回退到 data 里的默认值）
	base_attack_power = float(level_data.get("attack_power",
			data.get("attack_power", 50)))
	base_attack_speed = float(level_data.get("attack_speed",
			data.get("attack_speed", 1.0)))
	range = range_px

	position = Vector2(px, py)
	radius = Config.TOWER_RADIUS
	color = Config.ELEMENT_COLORS.get(attack_element, Color.WHITE)
	attack_cooldown = 0.0
	_apply_sprite()
	queue_redraw()


## 每秒伤害（DPS）：单次攻击力 × 每秒攻击次数。
func dps() -> float:
	return base_attack_power * base_attack_speed


## 每帧更新：攻击冷却倒计时。
func tick(dt: float) -> void:
	if attack_cooldown > 0.0:
		attack_cooldown -= dt


## 加载立绘（缩放放在 _draw 里做，不借助 Sprite2D 子节点）。
##
## 与怪物同理：z_index 是画布内全局排序，给子节点设负值会把整座塔排到棋盘后面。
func _apply_sprite() -> void:
	_texture = null
	if not image_path.is_empty():
		_texture = GameData.load_texture(image_path)
	queue_redraw()


func _draw() -> void:
	# 立绘：统一缩放到占地尺寸（Python 版是加载时 smoothscale）
	if _texture != null:
		var dst := Rect2(
				-Config.TOWER_FOOTPRINT.x / 2.0, -Config.TOWER_FOOTPRINT.y / 2.0,
				float(Config.TOWER_FOOTPRINT.x), float(Config.TOWER_FOOTPRINT.y))
		draw_texture_rect(_texture, dst, false)
	else:
		# 立绘缺失时回退：元素色块圆 + 中心小黑点
		draw_circle(Vector2.ZERO, radius, color)
		draw_circle(Vector2.ZERO, 6.0, Color8(30, 30, 30))
	# 开启全部范围显示，或该塔被选中时，画攻击范围圈
	if show_range or selected:
		draw_arc(Vector2.ZERO, range, 0.0, TAU, 96, Color8(90, 90, 110), 1.0)
	# 被选中时额外画一个白色高亮圈
	if selected:
		draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 48, Color8(255, 255, 255), 2.0)
