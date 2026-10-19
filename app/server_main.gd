class_name ServerMain
extends RefCounted
## Headless server entry (stub). Parses the CLI flags the server will take.

const DEFAULT_PORT: int = 47800

var port: int = DEFAULT_PORT
var dev_all_stations: bool = false


## Returns the process exit code.
func run(args: PackedStringArray) -> int:
	if not parse_args(args):
		return 2
	print("server stub: port=%d dev_all_stations=%s" % [port, dev_all_stations])
	return 0


func parse_args(args: PackedStringArray) -> bool:
	var i: int = 0
	while i < args.size():
		match args[i]:
			"--server":
				pass
			"--port":
				i += 1
				if i >= args.size() or not args[i].is_valid_int():
					push_error("--port needs a number")
					return false
				port = args[i].to_int()
			"--dev-all-stations":
				dev_all_stations = true
			_:
				push_error("unknown argument %s" % args[i])
				return false
		i += 1
	return true
