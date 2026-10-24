# 元素裂隙 · Godot 版

用 **Godot 4.7** 重写的 2D 塔防游戏。表现层与界面用 Godot 原生节点重做；关卡 1 的玩法、数值、公式与 pygame 原版**完全一致**。

> 本版在原版基础上新增了**关卡 2~5**（见「关卡与难度」）与**金币规则**（普通关一局 100、无尽模式按波次发 + 10 波里程碑），这两块是原版没有的。

> 原版：`C:\Users\LiuHu\Desktop\galgem`（pygame + Python，3760 行）

---

## 快速开始

**用编辑器打开**

1. 启动 Godot 4.7（标准版，非 .NET 版）
2. 「导入」→ 选择本目录下的 `project.godot`
3. 按 `F5` 运行

**命令行运行**

```bash
# 换成你自己的 Godot 路径
"D:\Godet\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\LiuHu\Desktop\ElementRift-Godot"
```

**操作**

| 操作 | 按键 |
|---|---|
| 建造防御塔 | 点底部塔栏选塔 → 左键点地面放置 |
| 取消放置 | 右键 |
| 选中已放置的塔 | 左键点它（显示范围与索敌按钮） |
| 回收防御塔 | 右键点它 → 确认 |
| 暂停 / 继续 | 空格，或右上角按钮 |
| 快进 1x/2x/4x | 右上角快进按钮 |
| 显示所有塔范围 | `R` |
| 暂停菜单 / 退出本局 | `Esc` |

---

## 目录结构

```
project.godot          # 项目配置（autoload、分辨率、全局字体）
theme / cjk_font.tres  # 中文字体（微软雅黑，带系统回退）
data/                  # 关卡/怪物/塔/卡牌 JSON + 美术 + 音频（与 Python 版共用的同一份）
scenes/
  main.tscn            # 主场景：状态机入口
  game_screen.tscn     # 游戏画面（棋盘 / 实体 / 特效 / UI 各层）
src/
  main.gd              # 状态机：主菜单/选关/游戏/暂停/设置/升级
  autoload/
    loader.gd          # JSON 读取、存档读写、精灵图遮罩与重心
    audio.gd           # 背景音乐轮播、可叠加的循环音效
  core/
    config.gd          # 常量、元素反应表、成长公式
    cards.gd           # 卡牌加成（三维度纯加法）
    combat.gd          # 伤害公式、元素附着与反应结算
    game.gd            # 游戏核心逻辑（波次/塔/怪物/双货币）
  entities/
    monster.gd/.tscn   # 怪物
    tower.gd/.tscn     # 防御塔
    projectile.gd/.tscn# 投射物
    fx.gd / fx_layer.gd# 飘字/粒子/闪电（数据类 + 批量绘制层）
  ui/                  # 各界面与控件
tests/                 # 无头测试（见下）
tools/screenshot.gd    # 开发用：把各界面渲染成 PNG
```

### 与原版的对应关系

移植时逐个文件对照，便于两边核数值：

| Python 原版 | Godot 版 |
|---|---|
| `src/config.py` | `src/core/config.gd` |
| `src/loader.py` | `src/autoload/loader.gd` |
| `src/cards.py` | `src/core/cards.gd` |
| `src/combat.py` | `src/core/combat.gd` |
| `src/entities.py` | `src/entities/*.gd` |
| `src/game.py` | `src/core/game.gd` |
| `src/renderer.py` | `src/ui/*.gd` + `src/entities/fx_layer.gd` |
| `src/audio.py` | `src/autoload/audio.gd` |
| `src/main.py` | `src/main.gd` + `src/ui/*.gd` |
| `tools/*.py` | `tests/cases/*.gd` |

---

## 测试

```bash
bash run_tests.sh            # 跑测试
bash run_tests.sh --import   # 先让 Godot 重新扫描资源与全局类名
```

**新增/改名了带 `class_name` 的脚本，或新增了美术资源后，必须带 `--import`** —— 否则全局类名缓存是旧的，会报 `Identifier ... not declared in the current scope`。

测试走无头模式（`--headless`），不需要显示器和音频设备。

### 覆盖范围

| 用例 | 内容 |
|---|---|
| `test_config` | 常量、10 条反应表、三条成长公式 |
| `test_cards` | 卡牌三维度纯加法、描述文案、稀有度分组 |
| `test_combat` | 伤害公式采样点、5 种反应、免疫/附着/冷却、冰系控制 |
| `test_loader` | JSON 读取、存档往返与防篡改、遮罩与重心、中文文件名资源 |
| `test_levels` | 6 张地图的设计约束：路径/障碍几何、难度倍率递增、波次合法性、金币字段 |
| `test_game` | 建塔/开火/卡牌/击杀/回收、波次曲线、无尽成长、塔占地判定、连锁雷击 |
| `test_ui` | 真实加载 `game_screen.tscn` 连续跑帧，走一遍 UI 交互路径 |
| `test_save_flow` | 金币发放规则、设置草稿、升级扣费 |
| `test_soak` | 打通 level_01 全部 7 波、无尽模式 15 波、飞行中回收塔 |

**断言的对拍基准来自实际运行 Python 版得到的数值**，不是手算 —— 两边数值一旦漂移立刻能发现。

### 看画面

测试看不到观感。用截图工具把各界面真的渲染出来：

```bash
"D:\Godet\Godot_v4.7.2-stable_win64_console.exe" --path "<项目>" --resolution 1280x720 \
  res://tools/screenshot.tscn -- "<输出目录>"
```

注意 `--headless` 下渲染器是 dummy，截出来是黑的，必须有显示环境。

---

## 打包发布

导出预设写在 `export_presets.cfg`，两个：

| 预设 | 用途 | 产物 |
|---|---|---|
| `Windows Release` | 发给别人的成品 | `dist/元素裂隙.exe`（PCK 内嵌，单文件，约 124MB） |
| `Windows SelfCheck` | 打包自检：把测试也打进去 | `build/selfcheck/ElementRift_selfcheck.exe` |

```bash
GODOT="/d/Godet/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --headless --path "<项目>" --export-release "Windows Release" "<项目>/dist/ElementRift.exe"
```

**首次打包必须先装导出模板**（编辑器菜单「编辑器 → 管理导出模板 → 从网络下载」，
或从官网下 `Godot_v<版本>-stable_export_templates.tpz` 解到
`%APPDATA%\Godot\export_templates\<版本>.stable\`）。模板约 1.2GB，官方不分平台拆包。

### 两个只有打包后才会暴露的坑

1. **`data/*.json` 必须写进 `include_filter`。** 这些 JSON 是运行时用
   `FileAccess` 裸读的，不是 Godot 资源；不显式包含的话，导出的游戏一启动就报
   「JSON 不存在」，整个游戏起不来。预设里已经有 `include_filter="*.json"`，别删。
2. **PCK 里列不到导入过的音频。** 包内存的是 `无限模式音乐_1.mp3.remap`
   （指向 `.godot/imported/*.mp3str`），`DirAccess` 看不到它 ——
   于是无尽模式的曲目扫描在成品里返回空、直接静音，而在编辑器里一切正常。
   `Audio._find_endless_tracks()` 因此补了一条「按编号探测」的兜底
   （`_probe_endless_tracks`，走 `ResourceLoader.exists`，认 remap）。

### 自检版怎么用

官方模板关闭了命令行指定场景（`path overrides`），所以没法直接
`game.exe res://tests/test_runner.tscn`。做法是**临时把主场景换成测试入口**再导出：

```bash
# 1. 备份并改主场景
sed -i 's|res://scenes/main.tscn|res://tests/test_runner.tscn|' project.godot
# 2. 导出 SelfCheck 预设，然后跑（退出码 0 = 全绿）
build/selfcheck/ElementRift_selfcheck.exe --headless --audio-driver Dummy
# 3. 把主场景改回 res://scenes/main.tscn 再导 Release
```

这一步不是形式主义：上面那两个坑都是靠它在成品里跑测试才发现的
（编辑器里 835 项全绿，导出后 4 项红）。改完记得把主场景改回去。

---

## 改数值

直接改 `data/*.json`，游戏里立刻生效 —— 和 Python 版共用同一套数据格式，**改一处两边通用**。

- `data/towers.json`：4 座塔各 5 级的攻击力/攻速/射程、造价、攻击模式
- `data/monsters.json`：怪物的血量/速度/防御/免疫元素/精灵图帧信息
- `data/cards.json`：卡牌的 `scope`（global/element/attack_type/tower）+ `target` + `stat` + 加成值
- `data/maps/*.json`：网格、路径折线、障碍、出怪波次、塔池卡池

### 关卡与难度

5 张普通关 + 1 个无尽模式（`data/maps/index.json` 的顺序就是选关顺序）。

| 关卡 | 章节 | 波数 | 怪物血量倍率 | 开局点数补贴 | 每波点数 | 通关金币 |
|---|---|---|---|---|---|---|
| 史莱姆平原 `level_01` | 1 | 7 | ×1 | 0 | 50 | 100 |
| 迷雾森林 `level_02` | 2 | 8 | ×5 | +200 | 60 | 100 |
| 熔岩裂谷 `level_03` | 3 | 9 | ×10 | +400 | 70 | 100 |
| 冰川回廊 `level_04` | 4 | 10 | ×15 | +700 | 80 | 100 |
| 雷霆之巅 `level_05` | 5 | 12 | ×20 | +1000 | 100 | 100 |
| 无尽裂隙 `level_endless` | — | ∞ | ×1 | 0 | 40 | 每波 100 |

怪物素材只有一套史莱姆，后期关卡的强度全靠地图里的 `monster_hp_multiplier` 拉起来
（第 1 波史莱姆：平原 100 血 → 雷霆之巅 2000 血）。这个倍率和逐波的 `hp_bonus`
是**相乘**的：最终血量 = 基础 100 × 本关倍率 × 波次累乘。

难度涨了，开局资源也得涨，否则第 1 波就会被直接打穿 —— 所以有 `bonus_initial_points`
（叠加在存档升级出来的开局点数之上）。`test_levels` 里有一条断言专门盯这件事：
开局点数买得起的 1 级火塔，至少要能打掉第 1 波 60% 的血量。

**金币规则**：

| 模式 | 发放方式 | 局内是否显示 |
|---|---|---|
| 普通关卡 | 通关时一次性发 100（`clear_gold`），不按波次发 | 不显示 |
| 无尽模式 | 每扛过一波 +100（`gold_reward`）；每扛过 10 波额外一笔里程碑 | 显示本局金币与下一档里程碑 |

里程碑是**各发各的、累加**：10 波 +100、20 波 +200、30 波 +400、40 波 +800……
每档在上一档基础上翻倍（`Config.endless_milestone_bonus`）。

无尽模式没有「通关」，只有城堡被攻破才结束 —— 本局金币要等那一刻才结算入账，
中途按 Esc 退出则本局金币全部作废（与普通关卡「只有胜利才发金币」同一条规则，
见 `Game.finalize_save`）。所以挂着不死的收益是实打实的。

元素反应表在 `src/core/config.gd` 的 `REACTIONS`（当前 10 条：蒸发/感电/超载/融化/冻结）。

### 音量

设置界面有三档独立音量（存档里对应 `settings.volume` / `settings.sfx` / `settings.ui`）：

| 档位 | 控制的音效 |
|---|---|
| 音乐音量 | 背景音乐（含无尽模式的轮播） |
| 音效音量 | 战斗音效：塔攻击、雷塔电流声 |
| UI音量 | 界面音效：按钮点击、卡牌点击、升级 |

**新增音效时必须在 `src/autoload/audio.gd` 的 `UI_SOUND_KEYS` 或 `BATTLE_SOUND_KEYS` 里归组**，否则会默认按战斗音量播放。测试里有一条会检查每个音效都恰好归入一组，忘了加会直接报错。

### 分辨率与窗口模式

分辨率有 4 个档位（`Config.RESOLUTION_PRESETS`）：720P / 1080P / 2K / 4K。

**只显示当前显示器支持得起的档位** —— 2K 显示器只会看到前 3 档，1080p 只看到前 2 档。判定是纯函数 `Config.available_resolutions(screen_size)`，屏幕尺寸由调用方传入，所以各种屏幕尺寸下的行为都有测试覆盖（含 800×600 小屏和 5120×1440 带鱼屏）。

窗口模式三选一（存档里是 `settings.window_mode` 字符串）：

| 模式 | 实现 |
|---|---|
| 全屏 | `WINDOW_MODE_FULLSCREEN` |
| 窗口 | `WINDOW_MODE_WINDOWED` |
| 无边框窗口 | `WINDOW_MODE_WINDOWED` + `WINDOW_FLAG_BORDERLESS` |

几个注意点：

- 游戏按 **1920×1080 设计**，其它分辨率整体等比缩放（`project.godot` 的 `stretch/mode = canvas_items` + `aspect = keep`）。所以 720P 是缩放 0.667、2K 是 1.333，布局不会错位。
- 存档里的档位若超出当前显示器（换显示器、存档被拷过来），启动时会自动收敛到能支持的最大档并写回存档，避免开出比屏幕还大的窗口。
- 显示设置**改动即时预览**（选分辨率立刻能看到效果）；点「返回」会按存档重新应用一次还原。
- 旧存档只有 `fullscreen` 布尔值，加载时自动迁移成 `window_mode` 并删除旧键。

---

## 与原版的设计差异

玩法数值 1:1，以下是**实现**层面的差异，都是有意为之：

1. **实体是节点，特效是绘制层。** 怪物/塔/投射物是 `Node2D` 场景；飘字、粒子、闪电是纯视觉且数量多，集中在 `fx_layer.gd` 一次画完。
2. **实体不用 `_process`，由 `Game.tick(dt)` 手动驱动。** 原版是「固定 1/60 步长 + 快进倍率」模型，快进就是一帧跑 N 次逻辑；实体若挂引擎时钟会与快进脱节。
3. **怪物动画用 `Sprite2D.hframes` + 手动设帧号**，不用 `AnimatedSprite2D` —— 同理，后者有自己的时钟。
4. **存档在 `user://`**（`%APPDATA%\Godot\app_userdata\元素裂隙\`），不再写回 `data/`。
5. **界面用 Godot 原生控件**（按钮/滑块/容器/主题），不再手算像素坐标绘制。游戏画面内的 UI 是运行时构建的（卡牌、塔卡片数量由数据决定），外围界面（主菜单/选关/升级/设置/暂停）是独立脚本各建各的；如果你想要可视编辑，在编辑器里对任一界面用「另存为场景」即可。
6. **中文文件名资源保持原样**（`data/音乐/休闲音乐.mp3`、`data/image/monsters/冰史莱姆.png`），已验证在 Godot 4.7 + Windows 下导入与运行时加载都正常。
7. **音量从两档拆成三档**（音乐 / 战斗音效 / UI 音效）。这是应要求的**玩法外改动**，原版只有「音量」和「音效」两档。旧存档没有 `ui` 键，加载时会补默认值 1.0。

### 绘制层级（改界面时必看）

三层的顺序由**两个不同的机制**决定，搞错会出现「棋盘盖住菜单」或「卡牌面板压住暂停菜单」：

```
游戏世界（Board / Game / FxLayer，默认画布）   ← 树顺序
    ↓
游戏 UI（HUD / 塔栏 / 卡牌面板，CanvasLayer layer=1）
    ↓
外围菜单（主菜单/选关/升级/设置/暂停，CanvasLayer layer=10，见 Main.MENU_LAYER）
```

- 同一 `CanvasLayer` 内靠**树顺序**（靠后的画在上面）
- 不同 `CanvasLayer` 靠 **layer 层号**（数值大的画在上面），与树顺序无关

两个必须注意的点：

1. **游戏画面必须排在所有 `Node2D` 兄弟之前** —— `Main.enter_level()` 里用 `move_child(_game_screen, 0)` 保证。
2. **`CanvasLayer` 不是 `CanvasItem`**，父节点设 `visible = false` **传不到它身上**。隐藏游戏画面必须调用 `GameScreen.set_content_visible()`，它会连同 `UI` 那一层一起设。

实体（怪物/塔）也**不要**用 `z_index`：
`z_index` 是整个画布内的全局排序键，不是相对父节点。给子节点设负值会把整只怪排到棋盘之后（沉到路径底下）。所以精灵图、血条、范围圈全部在实体自己的 `_draw()` 里按顺序画。

## 移植时踩到并已规避的坑

GDScript 与 Python 的语义差异（都写在代码注释里了，改代码时注意）：

- `x = read() or {}` 在 GDScript 里返回 **bool**，不是默认值 —— 必须显式判空
- `name` 是 `Node` 的内置属性，实体类里叫 `display_name`
- JSON 数字一律解析成 **float**，`{"a":1}` 与 `{"a":1.0}` 在字典深比较里不相等
- 节点 `queue_free()` 后**引用会失效**，跨帧持有实体引用（投射物持有 target/发射塔）必须用 `is_instance_valid()` 守卫 —— 这是移植新引入的问题，Python 版对象不会真销毁
- 对无类型来源取属性再运算，`:=` 会推断失败，需显式标注类型；一个推断失败会连带整个脚本编译失败
- 测试里 GDScript 报错只中断**当前函数**，外层仍会跑到结尾，汇总会显示 "ALL PASS" 但实际有错 —— 所以 `run_tests.sh` 把 `SCRIPT ERROR` 单独当失败统计

## 已知限制

- 分辨率档位是固定的 4 档（720P/1080P/2K/4K），不做任意分辨率；窗口模式下窗口比例与设计比例（16:9）不一致时会有黑边（`stretch/aspect = keep`）
- 音频在多声道同时播放时用的是 MP3（原版资源就是 MP3）。Godot 官方建议多声道音效用 WAV，若后续要加大量同时播放的音效，建议把 `data/音效/*.mp3` 转成 WAV
- 像素级命中判定（`BitMap`）已加距离预筛；若日后怪物数量上一个量级，建议再改成圆形粗筛 + 空间划分
- 关卡平衡：**单一元素塔无法通关**，因为每种史莱姆免疫自己那一系（例如第 6 波是水+雷史莱姆，全用雷塔会被免疫怪走通）。这是原版就有的设计
- 关卡 2~5 的难度倍率（5/10/15/20 倍）是**按倍率反推**出来的，不是逐波试玩调出来的：`test_levels` 只锁住了「末波总血量逐关递增且不超过上一关 5 倍」「开局打得动第 1 波」这类约束。真要手感合适，还是得实机打一遍再微调 `monster_hp_multiplier` / `points_per_wave` / `bonus_initial_points`
- 关卡 5 是当前版本的终点（没有第 6 关，也没有专门的 BOSS 怪）
