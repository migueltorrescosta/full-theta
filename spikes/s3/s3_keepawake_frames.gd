extends SceneTree
## Writes tiny near-black JPEG frames back to back, for build.sh to turn into
## the keep-awake video (FT-NET-046) with an image2pipe ffmpeg input.
## godot --headless --path . -s res://spikes/s3/s3_keepawake_frames.gd -- OUT [frames] [size]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var frames: int = int(args[1]) if args.size() > 1 else 10
	var size: int = int(args[2]) if args.size() > 2 else 64
	var f: FileAccess = FileAccess.open(args[0], FileAccess.WRITE)
	for i: int in range(frames):
		var img: Image = Image.create(size, size, false, Image.FORMAT_RGB8)
		var shade: float = (8 + (i % 2) * 4) / 255.0
		img.fill(Color(shade, shade, shade))
		f.store_buffer(img.save_jpg_to_buffer(0.9))
	f.close()
	quit(0)
