class_name Board
extends Node2D
## 棋盘层：网格线、路径、城堡、障碍 —— 移植自 renderer.py 的 _draw_grid/_draw_path/_draw_castle
##
## 全部是静态几何绘制（只在建塔阶段变化），单独一层方便与实体层分离。
## 网格线在 1920x1080 下有 128+72 条，逐帧重绘代价不小，
## 所以只在数据变化时 queue_redraw，不像特效层那样每帧刷。

var game: Game = null

## 放置预览：待放置的塔类型与鼠标位置（由 GameScreen 每帧写入）
var preview_tower_id := ""
var preview_pos := Vector2.ZERO
var preview_valid := false


func setup(p_game: Game) -> void:
	game = p_game
	queue_redraw()


## 每帧刷新放置预览（鼠标移动、点数变化都会影响是否合法）。
##
## 网格线有 128+72 条，而 _draw 是全量重绘。所以只在放置模式下才重绘
## （预览要跟随鼠标）；平时预览是空的，跳过重绘，省掉每帧上百条线的开销。
func update_preview(tower_id: String, pos: Vector2, valid: bool) -> void:
	var was_active := not preview_tower_id.is_empty()
	preview_tower_id = tower_id
	preview_pos = pos
	preview_valid = valid
	if not tower_id.is_empty() or was_active:
		queue_redraw()


func _draw() -> void:
	if game == null:
		return
	_draw_grid()
	_draw_path()
	_draw_castle()
	_draw_preview()


## 网格线、底部死区背景，以及「不可建塔」格子的深色底。
func _draw_grid() -> void:
	var ts := float(game.tile_size)
	var play_h := float(game.height - Config.UI_HEIGHT)   # 可游玩区域高度（不含底部 UI）
	# 底部死区背景（塔选择 UI 区域，不画网格）
	draw_rect(Rect2(0.0, play_h, game.width, Config.UI_HEIGHT), Color8(18, 18, 26))
	# 网格线
	var cols := int(game.width / game.tile_size) + 1
	for gx in range(cols):
		var x := gx * ts
		draw_line(Vector2(x, 0.0), Vector2(x, play_h), Config.COLOR_GRID, 1.0)
	var rows := int(play_h / ts) + 1
	for gy in range(rows):
		var y := gy * ts
		draw_line(Vector2(0.0, y), Vector2(game.width, y), Config.COLOR_GRID, 1.0)
	# 「不可建塔」的格子（路径/障碍）涂成深色
	for key in game.blocked:
		var g: Vector2i = key
		draw_rect(Rect2(g.x * ts, g.y * ts, ts, ts), Config.COLOR_OBSTACLE)


## 用 PATH_WIDTH 画出更宽的路径（与「不可建塔」的宽度保持一致）。
func _draw_path() -> void:
	if game.waypoints.size() < 2:
		return
	draw_polyline(game.waypoints, Config.COLOR_PATH, float(Config.PATH_WIDTH), true)


## 在城堡位置画一个色块（正方形）。
func _draw_castle() -> void:
	var p: Vector2 = game.castle_pos
	draw_rect(Rect2(p.x - 16.0, p.y - 16.0, 32.0, 32.0), Config.COLOR_CASTLE)


## 放置模式：范围圈跟随鼠标，绿=可建 / 红=不可建。
func _draw_preview() -> void:
	if preview_tower_id.is_empty() or game == null:
		return
	if game.state != Game.STATE_BUILD and game.state != Game.STATE_COMBAT:
		return
	var data = GameData.get_tower(preview_tower_id)
	if data == null:
		return
	var level := int(game.tower_levels.get(preview_tower_id, 1))
	var levels: Array = data.get("levels", [])
	var level_data: Dictionary = levels[level - 1] if (level - 1 >= 0 and level - 1 < levels.size()) else levels[0]
	var range_px := float(level_data.get("attack_range", data.get("attack_range", 3))) * game.tile_size

	# 范围以半透明实心圆盘显示（不是细环）
	var ring: Color = Color8(110, 220, 160) if preview_valid else Color8(220, 90, 90)
	ring.a = 0.35
	draw_circle(preview_pos, range_px, ring)

	# 塔立绘跟随鼠标，缺失则回退色块圆。
	# draw_texture_rect 会按目标矩形自动缩放，无需手动算 scale。
	var tex := GameData.load_texture(data.get("image", ""))
	var color: Color = Config.ELEMENT_COLORS.get(data.get("attack_element"), Color.WHITE)
	if tex != null:
		var dst := Rect2(
				preview_pos - Vector2(Config.TOWER_FOOTPRINT.x / 2.0,
						Config.TOWER_FOOTPRINT.y / 2.0),
				Vector2(Config.TOWER_FOOTPRINT))
		draw_texture_rect(tex, dst, false, Color(1, 1, 1, 0.75))
	else:
		draw_circle(preview_pos, float(Config.TOWER_RADIUS), color)
		draw_circle(preview_pos, 6.0, Color8(30, 30, 30))
