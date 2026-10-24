class_name Fx
extends RefCounted
## 纯视觉特效的数据类 —— 移植自 src/entities.py 的 DamageText / Particle / Lightning
##
## 这三种东西没有玩法交互，只是短暂显示后消失，所以不做成节点，
## 而是由 Game 持有数组、交给 FxLayer 一次性画完（见 src/entities/fx_layer.gd）。


## 伤害飘字：短暂上浮后消失，用于显示伤害数字、免疫（MISS）等文字反馈。
class DamageText extends RefCounted:
	var x: float
	var y: float
	var text: String
	var color: Color
	var size: int
	var life := 0.7        ## 剩余存活时间（秒）
	var max_life := 0.7    ## 总存活时间

	func _init(px: float, py: float, ptext: String, pcolor: Color, psize: int = 14) -> void:
		x = px
		y = py
		text = ptext
		color = pcolor
		size = psize

	## 倒计时并上浮；返回是否还存活。
	func update(dt: float) -> bool:
		life -= dt
		y -= 22.0 * dt     # 向上漂浮
		return life > 0.0


## 击杀/元素反应时的小粒子特效：短暂上浮后消失。
class Particle extends RefCounted:
	var x: float
	var y: float
	var color: Color
	var life := 0.35
	var max_life := 0.35

	func _init(px: float, py: float, pcolor: Color) -> void:
		x = px
		y = py
		color = pcolor

	func update(dt: float) -> bool:
		life -= dt
		y -= 18.0 * dt     # 向上漂浮
		return life > 0.0


## 雷击特效：从起点到终点的一条锯齿闪电，短暂显示后消失。
class Lightning extends RefCounted:
	var color: Color
	var life := 0.18
	var max_life := 0.18
	var points: Array[Vector2] = []

	func _init(x1: float, y1: float, x2: float, y2: float,
			pcolor: Color = Color8(190, 110, 250)) -> void:
		color = pcolor
		# 预生成锯齿路径点：首尾固定，中间点沿垂直方向随机偏移，模拟闪电的分叉抖动
		points.append(Vector2(x1, y1))
		var segs := 8                       # 中间分段的段数
		# 计算垂直于连线的单位向量，用于做横向抖动
		var pxp := -(y2 - y1)
		var pyp := (x2 - x1)
		var length := sqrt(pxp * pxp + pyp * pyp)
		if length > 1e-3:
			pxp /= length
			pyp /= length
		for i in range(1, segs + 1):
			var t := float(i) / (segs + 1)  # 从 0 到 1 的插值比例
			var px := x1 + (x2 - x1) * t    # 沿连线方向插值
			var py := y1 + (y2 - y1) * t
			var offset := randf_range(-12.0, 12.0)   # 随机横向偏移量
			points.append(Vector2(px + pxp * offset, py + pyp * offset))
		points.append(Vector2(x2, y2))

	func update(dt: float) -> bool:
		life -= dt
		return life > 0.0
