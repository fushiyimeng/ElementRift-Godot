extends Node
## 无头测试入口 —— 对应 Python 版的 tools/ 下那批 verify_*.py
##
## 用法：
##   godot --headless --path <项目> res://tests/test_runner.tscn
## 全部通过退出码 0，有失败退出码 1。
##
## 断言的对拍基准来自 Python 版实际跑出来的数值，而不是手算，
## 这样两边行为一旦漂移就能立刻发现。

## 要执行的用例文件（每个文件 extends RefCounted，实现 run(t)）
const CASES := [
	"res://tests/cases/test_config.gd",
	"res://tests/cases/test_cards.gd",
	"res://tests/cases/test_combat.gd",
	"res://tests/cases/test_loader.gd",
	"res://tests/cases/test_levels.gd",
	"res://tests/cases/test_game.gd",
	"res://tests/cases/test_ui.gd",
	"res://tests/cases/test_save_flow.gd",
	"res://tests/cases/test_audio.gd",
	"res://tests/cases/test_soak.gd",
]

var checks := 0
var failures := 0
var _current := ""
var _finished := false


func _ready() -> void:
	print("")
	print("========== ElementRift (Godot) test suite ==========")
	for path in CASES:
		var script: GDScript = load(path)
		# load() 对解析失败的脚本会返回不可实例化的对象；必须拦住，
		# 否则后面的 .new() 抛错会让 _ready 中断、quit() 永不执行，进程空转挂死。
		if script == null or not script.can_instantiate():
			_fail("cannot load case script: %s" % path)
			continue
		_current = path.get_file().get_basename()
		print("")
		print("--- %s ---" % _current)
		# 用例必须显式调用 t.finish()。若 run() 中途抛错（例如某个 autoload 是 Nil），
		# 执行会静默中断，不校验的话整段用例会「0 断言 0 失败」地蒙混成通过。
		_finished = false
		var case = script.new()
		case.run(self)
		if not _finished:
			_fail("%s 中途中断，未跑到 t.finish()（上方应有 SCRIPT ERROR）" % _current)

	print("")
	print("====================================================")
	if failures == 0:
		print("ALL PASS  (%d checks)" % checks)
	else:
		print("FAILED    %d / %d checks failed" % [failures, checks])
	print("")
	# 推进两帧再退出：用例里大量使用 queue_free（延迟到帧末执行），
	# 不跑帧的话这些节点会留到进程退出，被 Godot 报成 "ObjectDB instances leaked"，
	# 掩盖真正的泄漏。
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(1 if failures > 0 else 0)


## 断言两个值相等（严格相等，适合整数/字符串/布尔）。
##
## expected 用哨兵默认值而不是必填：写测试时漏传 expected（例如想断言布尔却写成
## check(label, 条件)）在 GDScript 里只会抛一个难懂的 "Expected 3 argument(s)" 错误，
## 而且会中断当前测试函数、让后面的断言静默跳过。这里把它变成一条明确的失败。
const ARG_UNSET := "\u0000t.check 缺少 expected 参数"

func check(label: String, actual, expected = ARG_UNSET) -> void:
	checks += 1
	# 必须先判类型：GDScript 里 Color == String 这类跨类型比较会直接报错，
	# 而不是像 Python 那样返回 False。
	if typeof(expected) == TYPE_STRING and (expected as String) == ARG_UNSET:
		_fail("%s\n         t.check 少传了 expected 参数；断言布尔请改用 check_true/check_false"
				% label)
		return
	if _equal(actual, expected):
		print("  ok   %s" % label)
	else:
		_fail("%s\n         expected: %s\n         actual:   %s" % [label, expected, actual])


## 断言两个浮点数近似相等（默认容差 1e-6，与 Python 版浮点精度对齐）。
func check_almost(label: String, actual: float, expected: float, tol: float = 1e-6) -> void:
	checks += 1
	if absf(actual - expected) <= tol:
		print("  ok   %s = %s" % [label, actual])
	else:
		_fail("%s\n         expected: %s (+- %s)\n         actual:   %s"
				% [label, expected, tol, actual])


## 断言条件为真。
func check_true(label: String, condition: bool) -> void:
	checks += 1
	if condition:
		print("  ok   %s" % label)
	else:
		_fail(label)


## 断言条件为假。
func check_false(label: String, condition: bool) -> void:
	check_true(label, not condition)


## 单独打印一行信息（不计入断言数）。
func info(text: String) -> void:
	print("       %s" % text)


## 用例跑完必须调用它，用来证明执行没有中途中断（见 _ready 里的校验）。
func finish() -> void:
	_finished = true


func _fail(message: String) -> void:
	failures += 1
	print("  FAIL %s" % message)


## 同类型才直接比较；数字类型之间允许 int/float 互通。
## 其它跨类型一律判不等 —— GDScript 的 == 对不兼容类型会直接抛错，
## 而测试里本来就常常要断言「实际值与期望值类型不同」。
func _equal(a, b) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	var numeric_a := ta == TYPE_INT or ta == TYPE_FLOAT
	var numeric_b := tb == TYPE_INT or tb == TYPE_FLOAT

	if ta != tb:
		if numeric_a and numeric_b:
			return absf(float(a) - float(b)) <= 1e-9
		return false
	if ta == TYPE_FLOAT:
		return absf(a - b) <= 1e-9
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _equal(a[i], b[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _equal(a[k], b[k]):
				return false
		return true
	return a == b
