class_name SnapshotAgeStats
extends RefCounted
## Per-client snapshot age and receipt gaps, pooled and per device (D199, TECH-9, FT-NET-046).
## Age is measured as in D161: the client's arrival time, before decoding, minus the
## server's capture stamp, joined by snapshot seq. Clients on other machines have another
## clock, so each report also carries the client's own send time; the offset is the
## smallest `server receive time - client send time` seen, which holds the client's clock
## skew plus the quickest uplink trip, so ages read at most that trip (a few ms on Wi-Fi)
## too high, never too low. Both clocks are unix time (LoadProbe.unix_us()).
## Values go into 1 ms histograms (constant memory for 64 clients over hours); a
## window histogram is reset after every summary line.

const BUCKETS: int = 3000


## A 1 ms histogram; values above the last bucket count in it, negatives in the first.
class Hist:
	extends RefCounted
	var counts: PackedInt32Array = PackedInt32Array()
	var n: int = 0

	func _init() -> void:
		counts.resize(BUCKETS)

	func add_us(us: int) -> void:
		counts[clampi(us / 1000, 0, BUCKETS - 1)] += 1
		n += 1

	func clear() -> void:
		counts.fill(0)
		n = 0

	## The percentile p (0..100) in ms (the bucket's upper edge), or -1 when empty.
	func percentile(p: float) -> int:
		if n == 0:
			return -1
		var want: int = maxi(1, ceili(n * p / 100.0))
		var seen: int = 0
		for i: int in BUCKETS:
			seen += counts[i]
			if seen >= want:
				return i + 1
		return BUCKETS

	func max_ms() -> int:
		for i: int in range(BUCKETS - 1, -1, -1):
			if counts[i] > 0:
				return i + 1
		return -1


class Client:
	extends RefCounted
	var session: int = 0
	var name: String = ""
	var kind: String = ""
	var user_agent: String = ""
	## min(server receive - client send) over the reports so far, or INT64 max before one.
	var offset_us: int = 0x7fffffffffffffff
	var last_arrival_us: int = 0
	var age_window: Hist = Hist.new()
	var age_total: Hist = Hist.new()
	var gap_window: Hist = Hist.new()
	var gap_total: Hist = Hist.new()
	## Arrivals whose snapshot the server no longer knew the stamp of.
	var unmatched: int = 0


var clients: Dictionary[int, Client] = {}
var pooled_age_window: Hist = Hist.new()
var pooled_age_total: Hist = Hist.new()
var pooled_gap_window: Hist = Hist.new()
var pooled_gap_total: Hist = Hist.new()


## Applies one report. `pairs` is [seq, arrival unix us, ...] oldest first; `stamp_of` maps
## a seq to the server's capture stamp (NetTransport.stamp_of), 0 when unknown.
func report(
	client: Client, sent_us: int, rx_us: int, pairs: PackedInt64Array, stamp_of: Callable
) -> void:
	client.offset_us = mini(client.offset_us, rx_us - sent_us)
	for i: int in range(0, pairs.size() - 1, 2):
		var arrival: int = pairs[i + 1]
		if client.last_arrival_us > 0 and arrival > client.last_arrival_us:
			var gap: int = arrival - client.last_arrival_us
			client.gap_window.add_us(gap)
			client.gap_total.add_us(gap)
			pooled_gap_window.add_us(gap)
			pooled_gap_total.add_us(gap)
		client.last_arrival_us = maxi(client.last_arrival_us, arrival)
		var stamp: int = stamp_of.call(pairs[i])
		if stamp <= 0:
			client.unmatched += 1
			continue
		var age: int = arrival + client.offset_us - stamp
		client.age_window.add_us(age)
		client.age_total.add_us(age)
		pooled_age_window.add_us(age)
		pooled_age_total.add_us(age)


func client_for(session: int, name: String, kind: String) -> Client:
	var c: Client = clients.get(session)
	if c == null:
		c = Client.new()
		c.session = session
		clients[session] = c
	c.name = name
	c.kind = kind
	return c


## The summary line for the window since the last call: {"pooled", "clients"} with
## `n`, `age_p50_ms`, `age_p99_ms` and `gap_p99_ms` each; per client also name, kind,
## user agent. Resets the windows. Clients with no snapshot in the window are left out.
func window_summary() -> Dictionary:
	var out: Dictionary = {"pooled": _line(pooled_age_window, pooled_gap_window), "clients": []}
	for c: Client in clients.values():
		if c.age_window.n == 0 and c.gap_window.n == 0:
			continue
		var line: Dictionary = _line(c.age_window, c.gap_window)
		line["session"] = c.session
		line["name"] = c.name
		line["client"] = c.kind
		line["ua"] = c.user_agent
		(out["clients"] as Array).append(line)
		c.age_window.clear()
		c.gap_window.clear()
	pooled_age_window.clear()
	pooled_gap_window.clear()
	return out


## The same over the whole session (the end-of-session JSON summary).
func total_summary() -> Dictionary:
	var out: Dictionary = {"pooled": _line(pooled_age_total, pooled_gap_total), "clients": []}
	for c: Client in clients.values():
		var line: Dictionary = _line(c.age_total, c.gap_total)
		line["session"] = c.session
		line["name"] = c.name
		line["client"] = c.kind
		line["ua"] = c.user_agent
		line["unmatched"] = c.unmatched
		(out["clients"] as Array).append(line)
	return out


static func _line(age: Hist, gap: Hist) -> Dictionary:
	return {
		"n": age.n,
		"age_p50_ms": age.percentile(50.0),
		"age_p99_ms": age.percentile(99.0),
		"gap_p99_ms": gap.percentile(99.0),
	}
