extends Node
## 音频管理：背景音乐与音效 —— 移植自 src/audio.py
##
## 音频资源放在 data 目录下：
## - data/音乐：背景音乐（主界面、关卡、无尽模式等）；
## - data/音效：一次性音效（升级、卡牌、按钮、塔攻击等）。
##
## 本模块集中定义「语义 key -> 文件名」的映射，游戏逻辑只通过 key 调用，
## 避免在业务代码里散落硬编码路径。
##
## 与 Python 版的差异（Godot 特性导致）：
## - pygame 的 Channel 换成 AudioStreamPlayer，同样提供 stop()，调用点写法不变；
## - 循环音效用的声道从「池」里取，用完由调用方 stop()，下次自动复用；
## - MP3 导入时 loop=false，需要循环的流在这里 duplicate 一份再打开 loop；
## - **循环流永远不会发出 finished 信号**，所以无尽模式的轮播用「不循环」的流
##   播完一首、由 finished 信号接下一首（对应 Python 版的 MUSIC_END 事件）。

## 无尽模式背景音乐前缀：data/音乐 下同名前缀 + "_1/_2/_3..." 的文件会自动加入，
## 并按编号轮流播放；新增文件无需改代码。
const ENDLESS_MUSIC_PREFIX := "无限模式音乐"
const MUSIC_DIR := "res://data/音乐"
## 探测兜底时最多试到第几首（见 _find_endless_tracks：导出后列目录拿不到曲目）
const ENDLESS_MUSIC_MAX_INDEX := 20

## 背景音乐：语义 key -> 相对 data 目录的文件路径（空串 = 暂未找到文件，接口留白）
const MUSIC_PATHS := {
	"main_menu": "音乐/主界面背景音乐.mp3",   # 主界面背景音乐
	"level_01": "音乐/休闲音乐.mp3",          # 第一关背景音乐
	# level_endless 不在此配置具体文件，由 ENDLESS_MUSIC_PREFIX 扫描自动发现
	"level_endless": "",
}

## 音效：语义 key -> 相对 data 目录的文件路径
const SOUND_PATHS := {
	"upgrade": "音效/升级音效.mp3",              # 升级按钮成功升级
	"card_click": "音效/点击卡牌的音效.mp3",      # 游戏内卡牌点击/选择
	"button_click": "音效/界面按钮点击音效.mp3",   # 界面按钮点击
	"tower_attack": "音效/防御塔攻击音效.mp3",     # 普通防御塔攻击（共用）
	"thunder_attack": "音效/雷防御塔攻击音效.mp3",  # 雷防御塔攻击（专用）
}

## 界面音效（受「UI音量」控制）：操作界面时响的，与战斗无关
const UI_SOUND_KEYS := ["upgrade", "card_click", "button_click"]
## 战斗音效（受「音效音量」控制）
const BATTLE_SOUND_KEYS := ["tower_attack", "thunder_attack"]

var music_volume := 1.0                   ## 背景音乐音量
var sfx_volume := 1.0                     ## 战斗音效音量
var ui_volume := 1.0                      ## 界面音效音量
var current_music := ""                   ## 当前正在播放的背景音乐 key

var _sounds := {}                         ## {key: AudioStream}（文件缺失则值为 null）
var _loop_streams := {}                   ## {key: AudioStream} 打开了 loop 的副本
var _music_player: AudioStreamPlayer = null
var _oneshot_players: Array[AudioStreamPlayer] = []  ## 一次性音效的播放器池
var _loop_players: Array[AudioStreamPlayer] = []     ## 循环音效的播放器池
var _endless_tracks: Array = []           ## 无尽模式已发现的曲目路径（按编号排序）
var _endless_index := 0


func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	# 无尽模式播完一首自动接下一首
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)

	for key in SOUND_PATHS:
		var stream := _load_stream(SOUND_PATHS[key])
		_sounds[key] = stream
		if stream != null:
			_loop_streams[key] = _make_looping(stream)


## 把相对 data 目录的路径转成 res:// 路径。
func _abs_path(rel: String) -> String:
	if rel.is_empty():
		return ""
	return "res://data/%s" % rel


## 加载单个音频流，失败返回 null（调用方静默忽略）。无声卡时也不会崩。
func _load_stream(rel: String) -> AudioStream:
	var path := _abs_path(rel)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


## 复制一份并把 loop 打开（导入的 MP3 默认 loop=false）。
func _make_looping(stream: AudioStream) -> AudioStream:
	var s := stream.duplicate() as AudioStream
	if s == null:
		return null
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	return s


## 设置音乐 / 战斗音效 / 界面音效音量（0~1），并立即生效。
func set_volumes(music_vol: float, sfx_vol: float, ui_vol: float = 1.0) -> void:
	music_volume = clampf(music_vol, 0.0, 1.0)
	sfx_volume = clampf(sfx_vol, 0.0, 1.0)
	ui_volume = clampf(ui_vol, 0.0, 1.0)
	if _music_player != null:
		_music_player.volume_db = _to_db(music_volume)
	# 正在循环播放的都是战斗音效（雷塔电流声），所以按 sfx_volume 更新。
	# 一次性的 UI 音效很短，播放时就把音量定好了，不需要事后改。
	for p in _loop_players:
		p.volume_db = _to_db(sfx_volume)


## 某个音效 key 该用哪档音量。
func volume_for(key: String) -> float:
	return ui_volume if UI_SOUND_KEYS.has(key) else sfx_volume


## 线性音量 0~1 转分贝；0 静音用极小值表示。
func _to_db(vol: float) -> float:
	if vol <= 0.0:
		return -80.0
	return linear_to_db(vol)


## 播放一次音效；音效不存在或该档音量为 0 时静默跳过。
func play_sound(key: String) -> void:
	var vol := volume_for(key)
	if vol <= 0.0:
		return
	var stream: AudioStream = _sounds.get(key)
	if stream == null:
		return
	# 从池里借一个空闲播放器，避免每次播放都新建节点
	var player := _acquire(_oneshot_players)
	player.stream = stream
	player.volume_db = _to_db(vol)
	player.play()


## 循环播放一个音效，返回正在播放的 AudioStreamPlayer；失败返回 null。
##
## 用于雷塔等需要「持续播放、按需起停」的循环音效，调用方拿到后自行 stop()。
func play_loop(key: String) -> AudioStreamPlayer:
	if sfx_volume <= 0.0:
		return null
	var stream: AudioStream = _loop_streams.get(key)
	if stream == null:
		return null
	var player := _acquire(_loop_players)
	player.stream = stream
	player.volume_db = _to_db(sfx_volume)
	player.play()
	return player


## 从指定池里取一个未在播放的 AudioStreamPlayer，没有就新建。
##
## 一次性音效与循环音效各用一个池：循环音效需要在音量变化时被重新赋值，
## 混在一起会把正在播的 UI 音效也按战斗音量改掉。
func _acquire(pool: Array) -> AudioStreamPlayer:
	for p in pool:
		if not (p as AudioStreamPlayer).playing:
			return p
	var p := AudioStreamPlayer.new()
	add_child(p)
	pool.append(p)
	return p


## 播放背景音乐；无尽模式走多曲轮流播放，其余按 MUSIC_PATHS 单曲循环。
func play_music(key: String) -> void:
	if key == "level_endless":
		_start_endless_music()
		return
	var path := _abs_path(MUSIC_PATHS.get(key, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		stop_music()
		return
	var stream := load(path) as AudioStream
	if stream == null:
		current_music = ""
		return
	# 单曲背景音乐直接循环，不依赖 finished 信号
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_music_player.stream = stream
	_music_player.volume_db = _to_db(music_volume)
	_music_player.play()
	current_music = key


## 扫描 data/音乐 目录，收集「无限模式音乐_1/_2/...」文件，按编号升序返回。
##
## 两条路都要走，缺一不可：
## 1. 列目录 —— 编辑器里跑时走这条，新增文件不用改代码；
## 2. 按编号探测 —— 导出成品的包（PCK）里**列不到**导入过的音频：
##    包内存的是 无限模式音乐_1.mp3.remap（指向 .godot/imported/*.mp3str），
##    DirAccess 看不到它，于是列目录在成品里返回空、无尽模式静音。
##    ResourceLoader.exists() 认 remap，所以探测能拿到。
##    （这是打包时才暴露的坑，test_audio 里那条断言就是为它准备的。）
func _find_endless_tracks() -> Array:
	var found := {}      # {编号: 路径}
	for item in _list_endless_dir():
		found[item[0]] = item[1]
	for item in _probe_endless_tracks():
		if not found.has(item[0]):
			found[item[0]] = item[1]
	var nums := found.keys()
	nums.sort()
	var out := []
	for n in nums:
		out.append(found[n])
	return out


## 列 data/音乐 目录，返回 [[编号, 路径], ...]（不排序；导入资源列不到是正常的）。
func _list_endless_dir() -> Array:
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		return []
	var found := []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var ext := fname.get_extension().to_lower()
			# 只认 Godot 能直接播放的格式
			if ext in ["mp3", "ogg", "wav"]:
				var stem := fname.get_basename()
				if stem.begins_with(ENDLESS_MUSIC_PREFIX):
					var suffix := stem.substr(ENDLESS_MUSIC_PREFIX.length())
					# 只认 _数字 形式，例如 _1 / _2 / _10
					if suffix.begins_with("_") and suffix.substr(1).is_valid_int():
						found.append([suffix.substr(1).to_int(), "%s/%s" % [MUSIC_DIR, fname]])
		fname = dir.get_next()
	dir.list_dir_end()
	return found


## 按编号 1..ENDLESS_MUSIC_MAX_INDEX 探测曲目是否存在，返回 [[编号, 路径], ...]。
##
## 这条是给导出成品兜底的（原因见 _find_endless_tracks）。单独拆出来是为了能在
## **编辑器里**就把这条路径测到 —— 不然它只在打包后才会被执行，等于没测。
func _probe_endless_tracks() -> Array:
	var found := []
	for i in range(1, ENDLESS_MUSIC_MAX_INDEX + 1):
		for ext in ["mp3", "ogg", "wav"]:
			var path := "%s/%s_%d.%s" % [MUSIC_DIR, ENDLESS_MUSIC_PREFIX, i, ext]
			if ResourceLoader.exists(path):
				found.append([i, path])
				break
	return found


## 无尽模式：扫描曲目并轮流播放，播完一首自动接下一首。
func _start_endless_music() -> void:
	var tracks := _find_endless_tracks()
	if tracks.is_empty():
		stop_music()
		return
	_endless_tracks = tracks
	_endless_index = 0
	current_music = "level_endless"
	_play_track(tracks[0])


## 播放单首背景音乐（不循环，播完靠 finished 信号接下一首）。
func _play_track(path: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		return
	# 必须保持不循环 —— 循环流不会发出 finished 信号，轮播就断了
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	_music_player.stream = stream
	_music_player.volume_db = _to_db(music_volume)
	_music_player.play()


## 音乐播完：无尽模式接下一首（循环轮流）。
func _on_music_finished() -> void:
	if current_music == "level_endless" and not _endless_tracks.is_empty():
		_endless_index = (_endless_index + 1) % _endless_tracks.size()
		_play_track(_endless_tracks[_endless_index])


## 停止背景音乐，并清空无尽模式曲目状态。
func stop_music() -> void:
	if _music_player != null:
		_music_player.stop()
	current_music = ""
	_endless_tracks = []
	_endless_index = 0


## 测试用：停止所有还在播放的音效。
func stop_all_loops() -> void:
	for p in _loop_players:
		p.stop()
	for p in _oneshot_players:
		p.stop()
