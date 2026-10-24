class_name Monster
extends Node2D
## 怪物实体 —— 移植自 src/entities.py 的 Monster
##
## 按 waypoints（路径折线的像素坐标）逐段前进，走到终点就算「漏怪」。
## 还负责保存元素附着（attachment）与元素反应冷却（reaction_cooldown），
## 供战斗系统结算火/水/雷/冰之间的反应。
##
## 使用方式：instantiate() -> add_child() -> setup()。
## （先入树再加 setup，@onready 的 sprite 才就绪；若顺序反了，_ready 会补做贴图配置。）

## 与 Python 版一致：用 x/y 暴露坐标，内部落在 Node2D 的 position 上。
## 这样 combat.gd 等模块不必关心实体是不是节点。
var x: float:
	get: return position.x
	set(value): position.x = value
var y: float:
	get: return position.y
	set(value): position.y = value

var monster_id := ""
## 显示名。注意不能叫 name —— 那是 Node 的内置属性，赋值会改写节点名。
var display_name := ""
var element := ""                       ## 所属元素（火/水/雷/冰 或空）
var immune: Array = []                  ## 免疫的元素列表（被这些元素攻击会 MISS）
var max_hp := 100.0
var hp := 100.0
var defense_element := 0.0
var defense_physical := 0.0
var speed := 40.0                       ## 移动速度（像素/秒）

# 精灵图信息
var image_path := ""
var frame_count := 1                    ## 动画总帧数
var frame_width := 32                   ## 单帧显示宽度
var frame_height := 32                  ## 单帧显示高度
var sprite_width := 32                  ## 源帧宽度（切帧用）
var sprite_height := 32
var animation_timer := 0.0
var animation_fps := 8.0

var radius := 16                        ## 碰撞/渲染半径：取帧宽帧高的较大者的一半
var waypoints: Array = []               ## 路径折线像素坐标
var waypoint_index := 1                 ## 下一个要前往的路径点下标
var alive := true
var reached_castle := false

var attachment = null                   ## 元素附着 {"element": str, "remaining": float} 或 null
var reaction_cooldown := 0.0            ## 元素反应冷却剩余时间
var knockback_vx := 0.0                 ## 击退冲量 X
var knockback_vy := 0.0                 ## 击退冲量 Y
var frozen := 0.0                       ## 冻结剩余时间（>0 时完全无法移动）
var slow_timer := 0.0                   ## 减速剩余时间（>0 时移动速度降低）

var masks: Array = []                   ## 逐帧碰撞遮罩（由 Game 填充）
var db_id := 0                          ## 唯一标识（防投射物重复命中）
var _rewarded := false                  ## 击杀是否已结算
var _leaked := false                    ## 漏怪是否已结算

var _texture: Texture2D = null


func _ready() -> void:
	# setup 可能在入树前就被调用，这里补做一次贴图加载
	_apply_sprite()


## 用怪物数据创建一只怪物，出生在路径起点。
func setup(p_monster_id: String, data: Dictionary, p_waypoints: Array) -> void:
	monster_id = p_monster_id
	display_name = data.get("name", p_monster_id)
	element = data.get("element", "")
	immune = data.get("immune", [])
	max_hp = float(data.get("hp", 100))
	hp = max_hp
	defense_element = float(data.get("defense_element", 0))
	defense_physical = float(data.get("defense_physical", 0))
	speed = float(data.get("speed", 40.0))

	image_path = data.get("image", "")
	frame_count = int(data.get("frame_count", 1))
	frame_width = int(data.get("frame_width", 32))
	frame_height = int(data.get("frame_height", 32))
	sprite_width = int(data.get("sprite_width", frame_width))
	sprite_height = int(data.get("sprite_height", frame_height))

	# 碰撞/渲染半径：取帧宽和帧高的较大者的一半（近似圆形）
	radius = maxi(frame_width, frame_height) / 2

	waypoints = p_waypoints
	if waypoints.size() > 0:
		position = waypoints[0]        # 出生在第一个路径点
	waypoint_index = 1
	alive = true
	reached_castle = false
	db_id = int(get_instance_id())     # 用实例 id 做唯一标识（防重复命中）
	_apply_sprite()


## 加载精灵图（整张 sheet，切帧在 _draw 里按源帧矩形取）。
func _apply_sprite() -> void:
	_texture = null
	if not image_path.is_empty():
		_texture = GameData.load_texture(image_path)
	queue_redraw()


## 根据动画计时器计算当前应显示第几帧（循环播放）。
func frame_index() -> int:
	if frame_count <= 0:
		return 0
	# 动画时间 × 帧率 = 已播放帧数，取模实现循环
	return int(animation_timer * animation_fps) % frame_count


## 返回被命中的目标点：优先精灵遮罩重心（去除透明偏移），回退到中心。
func hit_position() -> Vector2:
	if masks.size() > 0:
		var mask: Dictionary = masks[frame_index() % masks.size()]
		var c: Vector2 = mask["centroid"]     # 遮罩重心（不透明像素的中心，相对帧左上角）
		# 换算回世界坐标
		return Vector2(x - frame_width / 2.0 + c.x, y - frame_height / 2.0 + c.y)
	return Vector2(x, y)


## 给怪物叠加一个击退冲量（速度），用于超载反应的击退效果。
func apply_knockback(vx: float, vy: float) -> void:
	knockback_vx += vx
	knockback_vy += vy


## 冻结：怪物在 duration 秒内完全无法移动（取与剩余时长的较大值）。
func apply_freeze(duration: float) -> void:
	frozen = maxf(frozen, duration)


## 减速：怪物在 duration 秒内移动速度降低（取与剩余时长的较大值）。
func apply_slow(duration: float) -> void:
	slow_timer = maxf(slow_timer, duration)


## 每帧更新：动画计时、附着/冷却倒计时、击退衰减，再沿路径向前移动。
func tick(dt: float) -> void:
	animation_timer += dt

	if reaction_cooldown > 0.0:
		reaction_cooldown -= dt

	if attachment != null:
		attachment["remaining"] -= dt
		if attachment["remaining"] <= 0.0:
			attachment = null           # 附着到期则清除

	if knockback_vx != 0.0 or knockback_vy != 0.0:
		# 有击退冲量：按冲量移动，并做指数衰减（阻尼）
		x += knockback_vx * dt
		y += knockback_vy * dt
		var damp := maxf(0.0, 1.0 - 6.0 * dt)   # 每帧衰减系数（约 6/s）
		knockback_vx *= damp
		knockback_vy *= damp

	if not alive or reached_castle:
		_sync_visual()
		return                          # 死亡或已漏怪则不再前进

	# 冻结：期间完全无法移动（动画/附着/击退倒计时已在上方推进）
	if frozen > 0.0:
		frozen -= dt
		_sync_visual()
		return

	# 减速：移动速度按倍率降低
	var move_speed := speed
	if slow_timer > 0.0:
		slow_timer -= dt
		move_speed = speed * Config.SLOW_FACTOR

	var remaining := move_speed * dt    # 本帧可移动的总距离
	# 只要还有剩余距离且没走到终点，就继续沿路径前进
	while remaining > 0.0 and not reached_castle:
		if waypoint_index >= waypoints.size():
			reached_castle = true       # 没有下一个路径点 => 到达城堡（漏怪）
			break

		var target: Vector2 = waypoints[waypoint_index]
		var delta := target - position
		var dist := delta.length()
		if dist <= remaining:
			# 剩余距离足够走到（或超过）目标点：直接站上目标点
			position = target
			remaining -= dist
			waypoint_index += 1
		else:
			# 剩余距离不够走到目标点：按比例前进一段后停下
			position += delta / dist * remaining
			remaining = 0.0

	_sync_visual()


## 把逻辑状态同步到画面（位置、动画帧、血条）。
##
## 精灵图、元素附着圈、血条全部在 _draw() 里按顺序画，不借助 Sprite2D 子节点。
## 原因：z_index 在 Godot 里是「整个画布内全局排序」的，不是相对父节点；
## 之前给 Sprite 子节点设 z_index = -1，结果怪物连棋盘都被排到后面，整只怪沉到路径底下。
func _sync_visual() -> void:
	# 死亡/漏怪后立即隐藏（对应 Python 版渲染器里 `if not m.alive: continue`）
	visible = alive and not reached_castle
	queue_redraw()


func _draw() -> void:
	# 精灵动画：按源帧矩形从整张 sheet 里取当前帧，居中绘制
	if _texture != null and frame_count > 0 and sprite_width > 0 and sprite_height > 0:
		var src := Rect2(float(frame_index() * sprite_width), 0.0,
				float(sprite_width), float(sprite_height))
		var dst := Rect2(-frame_width / 2.0, -frame_height / 2.0,
				float(frame_width), float(frame_height))
		draw_texture_rect_region(_texture, dst, src)
	else:
		# 贴图缺失时回退为元素色块圆（对应 Python 版 renderer 的回退分支）
		var color: Color = Config.ELEMENT_COLORS.get(element, Color8(200, 200, 200))
		draw_circle(Vector2.ZERO, radius, color)

	# 有元素附着时，在怪物外圈画一个白色提示圈
	if attachment != null:
		draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 48, Color8(255, 255, 255), 2.0)

	# 血条：尺寸与位置（怪物头顶上方）
	var hp_w := 80.0
	var hp_h := 18.0
	var hp_x := -hp_w / 2.0
	var hp_y := -radius - hp_h - 6.0
	var ratio := maxf(0.0, hp / max_hp)          # 血量比例（0~1）
	# 血条背景（深灰）
	draw_rect(Rect2(hp_x, hp_y, hp_w, hp_h), Color8(60, 60, 70))
	# 血条前景（红色，长度按比例）
	if ratio > 0.0:
		draw_rect(Rect2(hp_x, hp_y, hp_w * ratio, hp_h), Color8(230, 90, 90))
	# 血条内部显示剩余生命值数字
	var font := ThemeDB.fallback_font
	var txt := str(maxi(0, int(round(hp))))
	var txt_size := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_string(font, Vector2(hp_x + (hp_w - txt_size.x) / 2.0,
			hp_y + hp_h - 4.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color8(255, 255, 255))
