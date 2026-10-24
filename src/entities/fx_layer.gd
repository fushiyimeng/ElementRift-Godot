class_name FxLayer
extends Node2D
## 特效层：一次性画完所有粒子 / 闪电 / 伤害飘字 —— 移植自 renderer.py 的三个 _draw_*
##
## 这三种特效纯视觉、无玩法交互，且数量多、生命周期短。
## 与其给每个粒子生成一个节点，不如集中在这一层用单次 _draw() 画完，效率高也更简单。
## 数据仍由 Game 持有（game.particles / game.lightning / game.damage_texts），本层只负责画。

## 由 GameScreen 创建后注入
var game: Node2D = null

## 伤害飘字的字号。Python 版无论飘字自带的 size 是多少，
## 渲染时统一用 small 字号（17pt），这里保持一致。
const DAMAGE_TEXT_SIZE := 17


func setup(p_game: Node2D) -> void:
	game = p_game


func _process(_delta: float) -> void:
	# 特效每帧都在动，直接每帧重绘（对应 Python 版每帧全量绘制）
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	_draw_particles()
	_draw_lightning()
	_draw_damage_texts()


## 粒子：越接近消亡越小的圆。
func _draw_particles() -> void:
	for p in game.particles:
		var f: float = maxf(0.0, p.life / p.max_life)   # 剩余生命比例
		var r := 8.0 + 8.0 * f                          # 半径随生命缩小
		draw_circle(Vector2(p.x, p.y), r, p.color)


## 雷击闪电：锯齿折线，外层白色发光 + 内层元素色，随时间变细消失。
func _draw_lightning() -> void:
	for ln in game.lightning:
		if ln.points.size() < 2:
			continue
		# 剩余生命越短线越细，随存活时间自然收窄消失
		var f: float = maxf(0.0, ln.life / ln.max_life)
		var width := maxf(1.0, 3.0 * f)
		# 外层粗白线做发光效果
		draw_polyline(ln.points, Color8(255, 255, 255), width + 1.0, true)
		# 内层元素色细线
		draw_polyline(ln.points, ln.color, width, true)


## 伤害飘字：居中于坐标，随剩余生命淡化消失。
func _draw_damage_texts() -> void:
	var font := ThemeDB.fallback_font
	for d in game.damage_texts:
		var alpha: float = clampf(d.life / d.max_life, 0.0, 1.0)
		var color: Color = d.color
		color.a = alpha
		var size := font.get_string_size(d.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				DAMAGE_TEXT_SIZE)
		# draw_string 的 y 是基线位置，这里换算成以 (x, y) 为中心
		var pos := Vector2(d.x - size.x / 2.0, d.y + size.y / 2.0 - 4.0)
		draw_string(font, pos, d.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				DAMAGE_TEXT_SIZE, color)
