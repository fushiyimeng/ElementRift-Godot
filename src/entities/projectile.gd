class_name Projectile
extends Node2D
## 投射物 —— 移植自 src/entities.py 的 Projectile
##
## 支持 homing（追踪目标）与 linear（直线穿透）两种飞行模式。
## 只是个小圆点，没有子节点，直接在 _draw 里画。

## 与 Python 版一致：用 x/y 暴露坐标，内部落在 Node2D 的 position 上。
var x: float:
	get: return position.x
	set(value): position.x = value
var y: float:
	get: return position.y
	set(value): position.y = value

var start_pos := Vector2.ZERO            ## 出发坐标（用于计算飞行距离）
var element := ""
var base_damage := 0.0
var speed := 500.0
var mode := "homing"                     ## "homing"（追踪）| "linear"（直线）
var target = null                        ## 追踪目标（homing 模式用）
var aoe_radius := 0.0
var pierce_radius := 0.0
var direction := Vector2.UP              ## 直线飞行的方向单位向量
var source_tower = null                  ## 发射它的塔（用于取攻击类型等）
var max_distance := 600.0                ## 最大飞行距离，超过则消失
var pierce_count := 0                    ## 最大穿透数量
var traveled := 0.0                      ## 已飞行距离
var arrived := false                     ## 是否已到达目标
var alive := true
var hit_ids := {}                        ## 已命中的怪物 db_id 集合（防重复命中）
var hit_count := 0                       ## 已命中次数

## 投射物绘制半径（Python 版固定画半径 12 的圆）
const DRAW_RADIUS := 12.0


## 创建一个投射物。
func setup(px: float, py: float, p_element: String, p_base_damage: float,
		p_speed: float, p_mode: String, opts: Dictionary = {}) -> void:
	position = Vector2(px, py)
	start_pos = position
	element = p_element
	base_damage = p_base_damage
	speed = p_speed
	mode = p_mode
	target = opts.get("target")
	aoe_radius = float(opts.get("aoe_radius", 0.0))
	pierce_radius = float(opts.get("pierce_radius", 0.0))
	direction = opts.get("direction", Vector2.UP)
	source_tower = opts.get("source_tower")
	max_distance = float(opts.get("max_distance", 600.0))
	pierce_count = int(opts.get("pierce_count", 0))
	traveled = 0.0
	arrived = false
	alive = true
	hit_ids = {}
	hit_count = 0
	queue_redraw()


## 追踪目标是否仍然有效。
##
## 必须用 is_instance_valid：怪物死亡后节点会被回收，
## 此时 target 变成「已释放实例」，直接读 .alive 会报错
## （Python 版对象不会真正销毁，所以原版没有这个问题）。
func has_live_target() -> bool:
	return target != null and is_instance_valid(target) and target.alive


## 发射塔的攻击类型；发射塔已被回收时回退为元素攻击。
func source_attack_type() -> String:
	if source_tower != null and is_instance_valid(source_tower):
		return source_tower.attack_type
	return "elemental"


## 发射塔的位置；发射塔已被回收时返回 null。
func source_position():
	if source_tower != null and is_instance_valid(source_tower):
		return source_tower.position
	return null


## 每帧更新：按模式推进飞行位置。
func tick(dt: float) -> void:
	var step := speed * dt              # 本帧飞行距离
	traveled += step                    # 累计飞行距离

	if mode == "homing":
		# 追踪模式：持续朝目标当前位置飞行
		if has_live_target():
			var tp: Vector2 = target.hit_position()   # 取目标命中点（遮罩重心或中心）
			var delta := tp - position
			var dist := delta.length()
			if dist <= step or dist <= 1e-3:
				# 本帧能到达目标：直接命中
				position = tp
				arrived = true
				alive = false
			else:
				# 朝目标方向前进一步
				position += delta / dist * step
		else:
			# 目标已死或不存在：直接标记到达（消失）
			arrived = true
			alive = false
	else:  # linear
		# 直线模式：沿固定方向前进
		position += direction * step

	# 超过最大飞行距离且还没到达，则消失
	if not arrived and traveled >= max_distance:
		alive = false

	_sync_visual()


func _sync_visual() -> void:
	# 位置变化后需要重绘（本项目里投射物每帧都在动）
	queue_redraw()


func _draw() -> void:
	var color: Color = Config.ELEMENT_COLORS.get(element, Color8(245, 245, 200))
	draw_circle(Vector2.ZERO, DRAW_RADIUS, color)
