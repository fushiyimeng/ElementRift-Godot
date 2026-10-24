extends Node
## 数据加载器：JSON 读取、存档读写、精灵图切帧与遮罩 —— 移植自 src/loader.py
##
## 封装所有「读数据」的操作，是数据与游戏逻辑之间的桥梁：
## 1. 从 data 目录读取各种 JSON（怪物/塔/卡牌/地图/存档）；
## 2. 读写玩家存档（Godot 下走 user://，不再写回 data 目录）；
## 3. 加载图片、生成逐帧碰撞遮罩与重心，并做缓存避免重复加载。
##
## 与 Python 版的差异：
## - 精灵图不再切成多个 Surface，而是返回整张 sheet + 帧数，交给 Sprite2D.hframes 切；
## - pygame 的 Mask 换成 Godot 的 BitMap（alpha > 阈值 视为不透明）；
## - pygame Mask.centroid() 在 Godot 没有对应 API，这里自己扫描像素求重心并缓存。

const DATA_DIR := "res://data"
const SAVE_PATH := "user://meta_save.json"

## 内存缓存：全量实体字典 {id: data}（启动时一次性读入）
var monsters := {}       ## 怪物表 {怪物id: 怪物数据}
var towers := {}         ## 塔表   {塔id: 塔数据}
var cards := {}          ## 卡牌表 {卡牌id: 卡牌数据}
var maps_index: Array = []   ## 关卡索引列表（地图 id 列表）

var _map_cache := {}     ## 地图数据缓存 {地图id: 地图数据}（按需懒加载）
var _texture_cache := {} ## 贴图缓存 {路径: Texture2D}
var _mask_cache := {}    ## 遮罩缓存 {key: Array[Dictionary]}


# ---------- 基础读取 ----------
## 从 data 目录读取一个 JSON 文件并解析返回；失败返回 null。
func _read_json(rel_path: String):
	var path := "%s/%s" % [DATA_DIR, rel_path]
	if not FileAccess.file_exists(path):
		push_error("[loader] JSON 不存在: %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("[loader] JSON 为空或读取失败: %s" % path)
		return null
	var result = JSON.parse_string(text)
	if result == null:
		push_error("[loader] JSON 解析失败: %s" % path)
	return result


# ---------- 启动一次性加载 ----------
## 读 JSON 并保证返回 Dictionary（失败时返回空字典）。
func _read_json_or_empty(rel_path: String) -> Dictionary:
	var data = _read_json(rel_path)
	return data if data is Dictionary else {}


## 启动时一次性把怪物/塔/卡牌/关卡索引读进内存。
func load_all() -> void:
	# 注意：GDScript 的 `a or b` 返回 bool（不像 Python 返回操作数），
	# 所以不能写 `_read_json(...) or {}`，必须显式判空。
	monsters = _read_json_or_empty("monsters.json")
	towers = _read_json_or_empty("towers.json")
	cards = _read_json_or_empty("cards.json")
	var index = _read_json("maps/index.json")
	maps_index = (index.get("maps", []) if index is Dictionary else [])


## 按 id 取怪物数据，不存在返回 null。
func get_monster(monster_id: String):
	return monsters.get(monster_id)


## 按 id 取塔数据，不存在返回 null。
func get_tower(tower_id: String):
	return towers.get(tower_id)


## 按 id 取卡牌数据，不存在返回 null。
func get_card(card_id: String):
	return cards.get(card_id)


## 返回所有关卡（地图）id 的列表。
func level_ids() -> Array:
	return maps_index.duplicate()


# ---------- 地图 ----------
## 读取指定关卡的地图数据（带缓存：同一个关卡只读一次磁盘）。
func preload_level(map_id: String):
	if not _map_cache.has(map_id):
		_map_cache[map_id] = _read_json("maps/%s.json" % map_id)
	return _map_cache[map_id]


# ---------- 存档 ----------
## 全新玩家的默认存档（首次启动或存档文件被删除/损坏时使用）。
func default_save() -> Dictionary:
	# 防御：若在 load_all() 之前被调用，towers/cards/maps_index 还是空的，
	# 会把 unlocked_* 写成空数组并落盘 —— 之后选关和升级界面会永远空白，
	# 而且 sanitize_save 不会自愈。这里先确保数据已载入。
	if towers.is_empty() or maps_index.is_empty():
		load_all()
	return {
		"gold": 0,
		"unlocked_maps": level_ids(),                          # 默认解锁所有已注册关卡
		"unlocked_towers": towers.keys(),                      # 默认解锁所有塔
		"unlocked_cards": cards.keys(),                        # 默认解锁所有卡牌
		"tower_levels": _all_towers_at_level_1(),              # 所有塔 1 级
		"castle_hp_level": 1,
		"initial_points_level": 1,
		"settings": {
			"volume": 1.0,      # 背景音乐
			"sfx": 1.0,         # 战斗音效（塔攻击等）
			"ui": 1.0,          # 界面音效（按钮/卡牌/升级）
			"resolution": [Config.DEFAULT_RESOLUTION.x, Config.DEFAULT_RESOLUTION.y],
			"window_mode": Config.WINDOW_MODE_WINDOWED,
			"fps": Config.FPS_MIN,
		},
	}


func _all_towers_at_level_1() -> Dictionary:
	var out := {}
	for tid in towers:
		out[tid] = 1
	return out


## 读取玩家存档；存档缺失/损坏时自动重建一个默认存档并落盘。
func load_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		var fresh := default_save()
		write_save(fresh)
		return fresh
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var data = JSON.parse_string(text)
	if data == null or not (data is Dictionary):
		# 文件损坏也回退到默认存档
		var fresh := default_save()
		write_save(fresh)
		return fresh
	return sanitize_save(data)


## 把玩家存档写回磁盘（user://meta_save.json）。
func write_save(data: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[loader] 存档写入失败: %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "\t", false))
	f.close()


## 把等级类字段钳制到 [lo, hi]；非法值（非数字/越界）回退到 lo。
func _clamp_level(raw, lo: int, hi: int) -> int:
	if not (raw is float or raw is int):
		return lo
	var value := int(raw)
	if value < lo:
		return lo
	if value > hi:
		return hi
	return value


## 校验并纠正存档里越界/非法的数值，防止手改存档造成数据不一致。
##
## 手改存档（例如把塔等级改成 10）会导致「显示 10 级但属性仍是 1 级」，
## 因为属性读取时等级越界会回退到第一级。这里把所有等级类字段钳制到合法
## 范围：塔等级 <= 该塔最大等级，城堡/初始点数等级 <= 各自上限，金币修正
## 为非负整数。这样即使存档被随意修改，数值与参数也能保持一致。
func sanitize_save(data: Dictionary) -> Dictionary:
	# 1) 塔等级：逐塔钳制到 [1, 该塔 levels 数量]
	var tower_levels = data.get("tower_levels")
	if not (tower_levels is Dictionary):
		tower_levels = {}
	var cleaned := {}
	for tid in towers:
		var levels: Array = towers[tid].get("levels", [])
		cleaned[tid] = _clamp_level(tower_levels.get(tid, 1), 1, maxi(1, levels.size()))
	data["tower_levels"] = cleaned

	# 2) 城堡生命 / 初始点数等级：钳制到各自上限
	data["castle_hp_level"] = _clamp_level(
			data.get("castle_hp_level", 1), 1, Config.CASTLE_HP_MAX_LEVEL)
	data["initial_points_level"] = _clamp_level(
			data.get("initial_points_level", 1), 1, Config.INITIAL_POINTS_MAX_LEVEL)

	# 3) 金币：修正为非负整数
	var gold = data.get("gold", 0)
	data["gold"] = maxi(0, int(gold) if (gold is float or gold is int) else 0)

	# 4) 解锁列表：缺失/类型不对/为空都回填成「全部解锁」。
	#    空列表会让选关界面和升级界面变成一片空白，属于必须自愈的坏档；
	#    当前版本也没有「部分解锁」的玩法，回填成全部与 default_save 语义一致。
	data["unlocked_maps"] = _fixed_unlock_list(
			data.get("unlocked_maps"), level_ids())
	data["unlocked_towers"] = _fixed_unlock_list(
			data.get("unlocked_towers"), towers.keys())
	data["unlocked_cards"] = _fixed_unlock_list(
			data.get("unlocked_cards"), cards.keys())

	# 5) 设置项兜底（分辨率/帧率越界时回退默认，对应 Python 版的迁移逻辑）
	if not (data.get("settings") is Dictionary):
		data["settings"] = default_save()["settings"]
	else:
		var s: Dictionary = data["settings"]
		# 分辨率必须是已知档位之一，否则回退默认。
		# 这里不管显示器实际支持到几档 —— 那是显示层的事（见 Main._apply_display_settings），
		# 数据层保持不知道显示器存在，便于测试。
		var res = s.get("resolution", [])
		var ok: bool = (res is Array and res.size() == 2
				and Config.is_valid_resolution(Vector2i(int(res[0]), int(res[1]))))
		if not ok:
			s["resolution"] = [Config.DEFAULT_RESOLUTION.x, Config.DEFAULT_RESOLUTION.y]

		# 窗口模式：新存档用 window_mode 字符串；
		# 旧存档只有 fullscreen 布尔值，这里做一次迁移并删掉旧键。
		var mode = s.get("window_mode")
		if not (mode is String) or not Config.WINDOW_MODE_LABELS.has(mode):
			mode = Config.WINDOW_MODE_FULLSCREEN if bool(s.get("fullscreen", false)) \
					else Config.WINDOW_MODE_WINDOWED
		s["window_mode"] = mode
		s.erase("fullscreen")

		s["fps"] = maxi(Config.FPS_MIN, mini(Config.FPS_MAX, int(s.get("fps", Config.FPS_MIN))))
		s["volume"] = clampf(float(s.get("volume", 1.0)), 0.0, 1.0)
		s["sfx"] = clampf(float(s.get("sfx", 1.0)), 0.0, 1.0)
		# 「UI 音量」是后加的档位：旧存档没有这个键，缺失时补 1.0
		s["ui"] = clampf(float(s.get("ui", 1.0)), 0.0, 1.0)
	return data


## 解锁列表兜底 + 增量补齐。
##
## 做两件事：
## 1. 非数组（坏数据）或空数组 —— 直接用 fallback（全部解锁）替换，坏档自愈；
## 2. 其余情况 —— 把「已经注册但列表里没有」的条目补到末尾，已有的条目顺序不动。
##
## 第 2 条是为「存档比代码旧」准备的：存档里只记了当年存在的关卡/塔/卡牌，
## 新版本加了新内容之后，那份存档会让新关卡永远显示「未解锁」，
## 而游戏里并没有任何解锁玩法，玩家无从下手 —— 只能在这里补。
func _fixed_unlock_list(raw, fallback: Array) -> Array:
	if not (raw is Array) or (raw as Array).is_empty():
		return fallback.duplicate()
	var out: Array = (raw as Array).duplicate()
	for id in fallback:
		if not out.has(id):
			out.append(id)
	return out


# ---------- 贴图 ----------
## 把数据里的相对图片路径解析成 res:// 下的完整路径；空路径返回空串。
func resolve_path(rel_path: String) -> String:
	if rel_path.is_empty():
		return ""
	if rel_path.begins_with("res://") or rel_path.begins_with("user://"):
		return rel_path
	return "%s/%s" % [DATA_DIR, rel_path]


## 加载单张贴图，缺失或失败返回 null（调用方回退色块显示）。
func load_texture(rel_path: String) -> Texture2D:
	if rel_path.is_empty():
		return null
	if _texture_cache.has(rel_path):
		return _texture_cache[rel_path]
	var full := resolve_path(rel_path)
	var tex: Texture2D = null
	if ResourceLoader.exists(full):
		tex = load(full) as Texture2D
	if tex == null:
		push_warning("[loader] 贴图缺失: %s" % full)
	_texture_cache[rel_path] = tex
	return tex


# ---------- 精灵图遮罩 ----------
## 横向切帧后为每帧生成碰撞遮罩（去除透明像素），返回 [Dictionary, ...]。
##
## 每个元素 {"bitmap": BitMap, "centroid": Vector2}，centroid 是该帧不透明像素的
## 重心（相对帧左上角），用于命中点定位 —— 对应 pygame 的 Mask.centroid()。
##
## 图片缺失或切帧失败返回空数组（调用方退化为圆形判定）。
func load_sprite_masks(rel_path: String, frame_count: int, frame_w: int,
		frame_h: int, sprite_w: int, sprite_h: int) -> Array:
	var key := [rel_path, frame_count, frame_w, frame_h, sprite_w, sprite_h]
	if _mask_cache.has(key):
		return _mask_cache[key]

	var masks: Array = []
	var tex := load_texture(rel_path)
	if tex != null and frame_count > 0 and frame_w > 0 and frame_h > 0:
		var img := tex.get_image()
		if img != null and not img.is_empty():
			# 显示尺寸与源帧尺寸不一致时，先整体缩放到显示尺寸，
			# 这样遮罩坐标与怪物绘制坐标（frame_width/height）同一坐标系。
			if img.get_width() != sprite_w * frame_count or img.get_height() != sprite_h:
				img = img.duplicate()
				img.resize(sprite_w * frame_count, sprite_h, Image.INTERPOLATE_NEAREST)
			if frame_w != sprite_w or frame_h != sprite_h:
				img = img.duplicate()
				img.resize(frame_w * frame_count, frame_h, Image.INTERPOLATE_NEAREST)
			for i in frame_count:
				var rect := Rect2i(i * frame_w, 0, frame_w, frame_h)
				var frame_img := img.get_region(rect)
				var bm := BitMap.new()
				# 阈值 0.5 对齐 pygame Mask.from_surface 的默认阈值 127/255
				bm.create_from_image_alpha(frame_img, 0.5)
				masks.append({
					"bitmap": bm,
					"centroid": _bitmap_centroid(bm),
					"size": Vector2i(frame_w, frame_h),
				})
	_mask_cache[key] = masks
	return masks


## 求 BitMap 中所有不透明像素的重心（相对左上角）；无像素时返回帧中心。
func _bitmap_centroid(bm: BitMap) -> Vector2:
	var size := bm.get_size()
	var sum_x := 0
	var sum_y := 0
	var count := 0
	for y in size.y:
		for x in size.x:
			if bm.get_bitv(Vector2i(x, y)):
				sum_x += x
				sum_y += y
				count += 1
	if count == 0:
		return Vector2(size.x / 2.0, size.y / 2.0)
	return Vector2(float(sum_x) / count, float(sum_y) / count)


## 清空所有缓存（测试用；正常游戏流程不需要）。
func clear_caches() -> void:
	_texture_cache.clear()
	_mask_cache.clear()
	_map_cache.clear()
