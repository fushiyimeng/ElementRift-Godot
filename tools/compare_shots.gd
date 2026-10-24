extends SceneTree
## 开发用：比较两张截图的指定像素，用来验证覆盖层/遮罩是否真的生效。
##
## 有些视觉问题（遮罩没盖住某层、层级排错）靠肉眼看图容易误判，
## 直接比像素亮度更可靠。
##
## 用法：
##   godot --headless --path <项目> --script res://tools/compare_shots.gd -- <图A> <图B> <x,y> [<x,y> ...]
## 输出每个坐标在两张图里的 RGB 与亮度比（B/A）。


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		print("用法: -- <图A> <图B> <x,y> [<x,y> ...]")
		quit(1)
		return

	var img_a := Image.load_from_file(args[0])
	var img_b := Image.load_from_file(args[1])
	if img_a == null or img_b == null:
		print("读取图片失败")
		quit(1)
		return
	print("A = %s  %s" % [args[0].get_file(), img_a.get_size()])
	print("B = %s  %s" % [args[1].get_file(), img_b.get_size()])
	print("")
	print("%-22s %-18s %-18s %s" % ["坐标", "A(基准)", "B(对比)", "亮度比 B/A"])

	for i in range(2, args.size()):
		var parts := args[i].split(",")
		if parts.size() != 2:
			continue
		var x := parts[0].to_int()
		var y := parts[1].to_int()
		if x < 0 or y < 0 or x >= img_a.get_width() or y >= img_a.get_height():
			print("%-22s 超出范围" % args[i])
			continue
		var ca := img_a.get_pixel(x, y)
		var cb := img_b.get_pixel(x, y)
		var la := (ca.r + ca.g + ca.b) / 3.0
		var lb := (cb.r + cb.g + cb.b) / 3.0
		var ratio := (lb / la) if la > 0.001 else 0.0
		print("%-22s %-18s %-18s %.2fx" % [
			args[i],
			"(%d,%d,%d)" % [ca.r8, ca.g8, ca.b8],
			"(%d,%d,%d)" % [cb.r8, cb.g8, cb.b8],
			ratio])
	quit(0)
