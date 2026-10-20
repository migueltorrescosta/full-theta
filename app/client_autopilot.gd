class_name ClientAutopilot
extends Node
## Client test flags (T059, FT-M1-016): drive the main menu without a mouse, e.g. a
## client export under Xvfb following docs/launch.md. Development only.
##
## full-theta.x86_64 -- [--auto-host BIND | --auto-join ADDR] [--screenshot PATH]
##     [--quit-after S]
##   --auto-host BIND   press Host with this bind address (127.0.0.1 or a LAN address).
##   --auto-join ADDR   press Join with this address (host or host:port).
##   --screenshot PATH  save the window as a PNG just before quitting.
##   --quit-after S     quit through the menu's Quit after S seconds (a host stops its
##                      server too) [10 with --screenshot, else never].

const FLAGS: PackedStringArray = ["--auto-host", "--auto-join", "--screenshot", "--quit-after"]

var menu: MainMenu
var host_bind: String = ""
var join_address: String = ""
var screenshot: String = ""
var quit_after: float = 0.0


## True when the command line has any of these flags.
static func wanted(args: PackedStringArray) -> bool:
	for f: String in FLAGS:
		if args.has(f):
			return true
	return false


## Reads the flags; reports the problem and returns false on a bad command line.
func parse_args(args: PackedStringArray) -> bool:
	for i: int in args.size():
		var flag: String = args[i]
		if flag not in FLAGS:
			continue
		if i + 1 >= args.size():
			push_error("%s needs a value" % flag)
			return false
		var value: String = args[i + 1]
		match flag:
			"--auto-host":
				host_bind = value
			"--auto-join":
				join_address = value
			"--screenshot":
				screenshot = value
			_:
				if not value.is_valid_float():
					push_error("--quit-after needs a number")
					return false
				quit_after = value.to_float()
	if screenshot != "" and quit_after <= 0.0:
		quit_after = 10.0
	return true


func _ready() -> void:
	# After the menu's own deferred start (orphan check).
	await get_tree().process_frame
	if host_bind != "":
		menu.host(host_bind)
	elif join_address != "":
		menu.join(join_address)
	if quit_after > 0.0:
		await get_tree().create_timer(quit_after).timeout
		if screenshot != "":
			var image: Image = get_viewport().get_texture().get_image()
			if image == null or image.save_png(screenshot) != OK:
				push_error("cannot write the screenshot %s" % screenshot)
		menu.quit()
