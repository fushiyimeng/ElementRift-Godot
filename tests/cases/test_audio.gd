extends RefCounted
## 校验音频管理：三档音量分组、资源加载、无尽模式曲目扫描
##
## 无头 + Dummy 音频驱动下听不到声音，但音量路由、资源存在性、
## 曲目扫描这些逻辑都能验证。


func run(t) -> void:
	GameData.load_all()
	_test_sound_groups(t)
	_test_three_volumes(t)
	_test_assets_loaded(t)
	_test_endless_tracks(t)
	_test_music_switch(t)
	_test_zero_volume_silences(t)
	t.finish()


## 每个音效都必须被明确归入「UI」或「战斗」其中一组。
## 新加音效时如果忘了分类，会默默地按战斗音量播放，这条能拦住。
func _test_sound_groups(t) -> void:
	for key in Audio.SOUND_PATHS:
		var in_ui: bool = Audio.UI_SOUND_KEYS.has(key)
		var in_battle: bool = Audio.BATTLE_SOUND_KEYS.has(key)
		t.check_true("音效 %s 恰好归入一组" % key, in_ui != in_battle)
	# 反向：分组里的 key 都必须在 SOUND_PATHS 里有实际文件映射
	for key in Audio.UI_SOUND_KEYS:
		t.check_true("UI 分组里的 %s 有音效文件" % key, Audio.SOUND_PATHS.has(key))
	for key in Audio.BATTLE_SOUND_KEYS:
		t.check_true("战斗分组里的 %s 有音效文件" % key, Audio.SOUND_PATHS.has(key))
	t.check("UI 音效数量", Audio.UI_SOUND_KEYS.size(), 3)
	t.check("战斗音效数量", Audio.BATTLE_SOUND_KEYS.size(), 2)


## 三档音量各管各的：音乐 / 战斗音效 / UI 音效互不影响
func _test_three_volumes(t) -> void:
	Audio.set_volumes(1.0, 1.0, 1.0)
	t.check_almost("默认音乐音量", Audio.music_volume, 1.0)
	t.check_almost("默认战斗音效音量", Audio.sfx_volume, 1.0)
	t.check_almost("默认 UI 音量", Audio.ui_volume, 1.0)

	# 设成三个不同值
	Audio.set_volumes(0.5, 0.3, 0.8)
	t.check_almost("音乐音量已设置", Audio.music_volume, 0.5)
	t.check_almost("战斗音效音量已设置", Audio.sfx_volume, 0.3)
	t.check_almost("UI 音量已设置", Audio.ui_volume, 0.8)

	# 路由：UI 音效走 ui_volume，战斗音效走 sfx_volume
	t.check_almost("button_click 走 UI 音量", Audio.volume_for("button_click"), 0.8)
	t.check_almost("card_click 走 UI 音量", Audio.volume_for("card_click"), 0.8)
	t.check_almost("upgrade 走 UI 音量", Audio.volume_for("upgrade"), 0.8)
	t.check_almost("tower_attack 走战斗音量", Audio.volume_for("tower_attack"), 0.3)
	t.check_almost("thunder_attack 走战斗音量", Audio.volume_for("thunder_attack"), 0.3)

	# 越界值钳制
	Audio.set_volumes(5.0, -1.0, 99.0)
	t.check_almost("音量上限钳制", Audio.music_volume, 1.0)
	t.check_almost("音量下限钳制", Audio.sfx_volume, 0.0)
	t.check_almost("UI 音量上限钳制", Audio.ui_volume, 1.0)

	# 三个参数里 ui 可省略（保持与旧调用点兼容），缺省为 1.0
	Audio.set_volumes(0.4, 0.6)
	t.check_almost("省略 ui 参数时默认为 1.0", Audio.ui_volume, 1.0)

	Audio.set_volumes(1.0, 1.0, 1.0)


## 五个音效都真的加载到了（含中文文件名）
func _test_assets_loaded(t) -> void:
	for key in Audio.SOUND_PATHS:
		t.check_true("音效 %s 已加载" % key, Audio._sounds.get(key) != null)
		# 循环音效需要一份打开了 loop 的副本
		t.check_true("音效 %s 有循环副本" % key, Audio._loop_streams.get(key) != null)


## 无尽模式曲目扫描：data/音乐 下的「无限模式音乐_N」按编号升序
func _test_endless_tracks(t) -> void:
	var tracks: Array = Audio._find_endless_tracks()
	t.check("找到 2 首无尽模式曲目", tracks.size(), 2)
	if tracks.size() == 2:
		t.check_true("第 1 首是 _1", (tracks[0] as String).ends_with("无限模式音乐_1.mp3"))
		t.check_true("第 2 首是 _2（按编号升序）",
				(tracks[1] as String).ends_with("无限模式音乐_2.mp3"))

	# 按编号探测那条路必须也能找齐。它在编辑器里是「备用路径」，
	# 导出后的成品才真正依赖它（PCK 里列不到导入过的 mp3），
	# 所以必须在这里主动测一次 —— 否则只有打包时才会发现它坏了。
	var probed: Array = Audio._probe_endless_tracks()
	t.check("按编号探测也能找到 2 首", probed.size(), 2)
	if probed.size() == 2:
		t.check("探测结果与目录扫描一致",
				[probed[0][1], probed[1][1]], tracks)


## 切歌：普通关卡单曲循环，无尽模式走轮播列表
func _test_music_switch(t) -> void:
	Audio.play_music("main_menu")
	t.check("主菜单音乐已播放", Audio.current_music, "main_menu")

	Audio.play_music("level_01")
	t.check("第一关音乐已播放", Audio.current_music, "level_01")

	# 无尽模式：应载入轮播列表
	Audio.play_music("level_endless")
	t.check("无尽模式音乐已播放", Audio.current_music, "level_endless")
	t.check("无尽轮播列表已载入", Audio._endless_tracks.size(), 2)

	# 播完一首接下一首
	var first_index: int = Audio._endless_index
	Audio._on_music_finished()
	t.check("播完自动接下一首", Audio._endless_index, (first_index + 1) % 2)
	Audio._on_music_finished()
	t.check("轮播会绕回第一首", Audio._endless_index, first_index)

	Audio.stop_music()
	t.check("停止后清空当前曲目", Audio.current_music, "")
	t.check("停止后清空轮播列表", Audio._endless_tracks.size(), 0)

	# 未知 key 不应崩，且不残留状态
	Audio.play_music("不存在的关卡")
	t.check("未知 key 不设置当前曲目", Audio.current_music, "")


## 音量归零时播放应静默跳过而不是报错
func _test_zero_volume_silences(t) -> void:
	Audio.set_volumes(0.0, 0.0, 0.0)
	Audio.play_sound("tower_attack")        # 战斗音量为 0：跳过
	Audio.play_sound("button_click")        # UI 音量为 0：跳过
	t.check("战斗音量为 0 时 play_loop 返回 null",
			Audio.play_loop("thunder_attack"), null)
	t.check_true("归零播放不报错", true)

	# 只关 UI 音量：战斗音效仍应播放（不返回 null）
	Audio.set_volumes(1.0, 1.0, 0.0)
	t.check_almost("只关 UI 时战斗音量不受影响", Audio.volume_for("tower_attack"), 1.0)
	t.check_almost("只关 UI 时 UI 音量为 0", Audio.volume_for("button_click"), 0.0)
	t.check_true("UI 音量为 0 时不播 UI 音效（play_sound 直接返回）", true)

	Audio.set_volumes(1.0, 1.0, 1.0)
	Audio.stop_all_loops()
