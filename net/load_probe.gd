class_name LoadProbe
extends RefCounted
## The load gate's server-side probe (#11, FT-GEN-003, FT-NET-040, D161), set by
## `--probe-out` (dev and test only). It waits until `expect_picks` sessions hold a pick
## and a ship has started, lets `warmup_s` pass, then records every main-thread frame
## that stepped the sim for `window_s` seconds: its wall time split into session.process
## (inbound messages), the sim step, after_ticks (rejections and event routing) and the
## SimCopy capture, and the thread's on-CPU and run-queue time from
## /proc/thread-self/schedstat. When the window ends, NetServer quits and write() puts
## these frames, the net thread's records (NetTransport.probe_dump), the sessions and
## the window marks into one JSON file for tools/l4/load_check.py.

enum Phase { WAITING, WARMUP, WINDOW, DONE }

const FRAME_FIELDS: Array[String] = [
	"unix_us",
	"total_us",
	"process_us",
	"sim_us",
	"after_us",
	"capture_us",
	"ticks",
	"oncpu_us",
	"preempt_us"
]

var out_path: String
var expect_picks: int = 64
var warmup_s: float = 3.0
var window_s: float = 60.0
var phase: Phase = Phase.WAITING
var marks: Dictionary = {}
var frames: PackedInt64Array = PackedInt64Array()

var _window_end_us: int = 0


func _init(path: String) -> void:
	out_path = path


## [on-CPU ns, run-queue wait ns] of the calling thread so far, or [0, 0].
func sched() -> PackedInt64Array:
	# Opened afresh each time: procfs reports no length, so a reused handle reads empty.
	var f: FileAccess = FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
	if f == null:
		return PackedInt64Array([0, 0])
	var parts: PackedStringArray = f.get_line().split(" ")
	if parts.size() < 2:
		return PackedInt64Array([0, 0])
	return PackedInt64Array([parts[0].to_int(), parts[1].to_int()])


## Advances the phase once a frame (main thread); true when the window is over and the
## server should quit.
func update(picks: int, started: bool) -> bool:
	var now: int = unix_us()
	match phase:
		Phase.WAITING:
			if picks >= expect_picks and started:
				marks["all_in_unix_us"] = now
				phase = Phase.WARMUP
				print("probe: %d picks and a ship started; warmup %.0f s" % [picks, warmup_s])
		Phase.WARMUP:
			if now - int(marks["all_in_unix_us"]) >= int(warmup_s * 1e6):
				marks["window_start_unix_us"] = now
				_window_end_us = now + int(window_s * 1e6)
				phase = Phase.WINDOW
				print("probe: window start")
		Phase.WINDOW:
			if now >= _window_end_us:
				marks["window_end_unix_us"] = now
				phase = Phase.DONE
				print("probe: window end")
				return true
		Phase.DONE:
			return true
	return false


## Records one frame that stepped the sim (inside the window only). Times are
## Time.get_ticks_usec() stamps: frame start, after process, after the sim, after
## after_ticks, after the capture; s0 and s1 are sched() at the frame's start and end.
func tick_frame(
	t: PackedInt64Array, ticks: int, s0: PackedInt64Array, s1: PackedInt64Array
) -> void:
	if phase != Phase.WINDOW:
		return
	(
		frames
		. append_array(
			[
				unix_us(),
				t[4] - t[0],
				t[1] - t[0],
				t[2] - t[1],
				t[3] - t[2],
				t[4] - t[3],
				ticks,
				(s1[0] - s0[0]) / 1000,
				(s1[1] - s0[1]) / 1000,
			]
		)
	)


## Writes everything to out_path as JSON.
func write(net: Dictionary, sessions: Dictionary, extra: Dictionary) -> Error:
	var doc: Dictionary = {
		"marks": marks,
		"frame_fields": FRAME_FIELDS,
		"frames": Array(frames),
		"net": net,
		"sessions": sessions,
		"server": extra,
	}
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("probe: can't write %s" % out_path)
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(doc))
	f.close()
	print("probe: wrote %s" % out_path)
	return OK


static func unix_us() -> int:
	return int(Time.get_unix_time_from_system() * 1_000_000.0)
