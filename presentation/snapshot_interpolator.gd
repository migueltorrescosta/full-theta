class_name SnapshotInterpolator
extends RefCounted
## Renders the own ship and contacts between received snapshots (FT-ARC-015): no
## prediction, no extrapolation. push() records each applied snapshot by sim tick;
## update() advances a render clock in ticks with real time, held DELAY_TICKS behind the
## newest snapshot (about two snapshot intervals, PROVISIONAL) and never past it, so a
## late snapshot freezes the picture at the newest one rather than guessing ahead.
## Positions interpolate along the minimum image (D124: a site wraps with period P), so
## a contact crossing a seam doesn't sweep across the site.
##
## All positions are metres, site-local, in world axes; local() turns a world offset
## into the ship frame (-Z bow, +X starboard, +Y up) that the radar and chips use.
##
## Contacts at the render tick are those of the older of the two bracketing samples
## (of the only sample when there is one): a new contact appears, and a lost one goes,
## when the render clock reaches the snapshot that says so; one missing from the newer
## sample holds its last position until then.

## Sim ticks per second.
const TICK_HZ: float = 60.0
## Render delay behind the newest snapshot: 2 snapshot intervals at 30 Hz (PROVISIONAL).
const DELAY_TICKS: float = 4.0
## Samples kept.
const KEEP: int = 8
## The render clock runs up to this fraction fast or slow to drift back to its target.
const DRIFT: float = 0.1
## It snaps to the target when more than this many snapshot intervals off.
const SNAP_INTERVALS: float = 2.0

## Ticks per real second the render clock runs at (tests may change it).
var tick_hz: float = TICK_HZ
var delay_ticks: float = DELAY_TICKS
## The tick being rendered (fractional).
var render_tick: float = -1.0
## Site period in position units (NetViewState.p_units).
var p_units: int = 0
## Bumped whenever the interpolated state is re-evaluated (StationContext.picture()).
var revision: int = 0

## Oldest first: {"tick", "site", "pos" (Vector3i units), "rot", "contacts": id ->
## Vector3i units at that tick}.
var _samples: Array[Dictionary] = []
var _last_ms: int = 0
var _own_pos: Vector3 = Vector3.ZERO
var _own_rot: Quaternion = Quaternion.IDENTITY
## id -> Vector3 (m) at the render tick.
var _contacts: Dictionary = {}


## Records the view's current snapshot (call after NetClient.poll() when view.seq
## changed). A full snapshot of a new site or a jump back in ticks restarts the buffer.
func push(view: NetViewState, now_ms: int) -> void:
	if view.kin.is_empty():
		return
	p_units = view.p_units
	var site: int = int(view.kin.get("site", 0))
	if not _samples.is_empty():
		var last: Dictionary = _samples.back()
		if view.tick < int(last["tick"]) or site != int(last["site"]):
			_samples.clear()
		elif view.tick == int(last["tick"]):
			_samples.pop_back()
	var contacts: Dictionary = {}
	var model: Dictionary = view.contacts.get("model", {})
	for id: int in model:
		var e: Array = model[id]
		contacts[id] = NetCodec.predict(e[0], e[1], view.tick - int(e[2]), p_units)
	(
		_samples
		. append(
			{
				"tick": view.tick,
				"site": site,
				"pos": view.kin["pos"],
				"rot": view.kin.get("rot", Quaternion.IDENTITY),
				"contacts": contacts,
			}
		)
	)
	if _samples.size() > KEEP:
		_samples.pop_front()
	if _samples.size() == 1:
		render_tick = float(view.tick)
		_last_ms = now_ms
	_evaluate()


## Advances the render clock to now_ms (real time).
func update(now_ms: int) -> void:
	if _samples.is_empty():
		return
	var step: float = float(now_ms - _last_ms) * tick_hz / 1000.0
	_last_ms = now_ms
	var newest: float = float(_samples.back()["tick"])
	var oldest: float = float(_samples[0]["tick"])
	var target: float = maxf(newest - delay_ticks, oldest)
	render_tick += step + clampf(target - render_tick, -DRIFT * step, DRIFT * step)
	render_tick = minf(render_tick, newest)
	var interval: float = 1.0
	if _samples.size() > 1:
		interval = maxf(1.0, newest - float(_samples[-2]["tick"]))
	if absf(target - render_tick) > SNAP_INTERVALS * interval:
		render_tick = target
	render_tick = maxf(render_tick, oldest)
	_evaluate()


## True once at least one snapshot was pushed.
func has_data() -> bool:
	return not _samples.is_empty()


## The own ship's interpolated position (m) and orientation.
func own_position() -> Vector3:
	return _own_pos


func own_rotation() -> Quaternion:
	return _own_rot


## Contacts present at the render tick, ascending.
func contact_ids() -> Array[int]:
	var out: Array[int] = []
	out.assign(_contacts.keys())
	out.sort()
	return out


## A contact's interpolated position (m), ZERO if unknown.
func contact_position(id: int) -> Vector3:
	return _contacts.get(id, Vector3.ZERO)


## Minimum-image offset (m, world axes) from the own ship to a site-local position.
func offset_to(pos: Vector3) -> Vector3:
	return min_image(pos - _own_pos)


## A world-axes offset in the own ship's frame.
func local(world_offset: Vector3) -> Vector3:
	return own_rotation().inverse() * world_offset


## Interpolates the samples bracketing render_tick into the cached state.
func _evaluate() -> void:
	revision += 1
	var i: int = 0
	while i + 1 < _samples.size() and float(_samples[i + 1]["tick"]) <= render_tick:
		i += 1
	var a: Dictionary = _samples[i]
	var b: Dictionary = _samples[mini(i + 1, _samples.size() - 1)]
	var span: float = float(int(b["tick"]) - int(a["tick"]))
	var t: float = 0.0
	if span > 0.0:
		t = clampf((render_tick - float(a["tick"])) / span, 0.0, 1.0)
	_own_pos = _lerp(a["pos"], b["pos"], t)
	_own_rot = (a["rot"] as Quaternion).slerp(b["rot"], t)
	_contacts.clear()
	var ca: Dictionary = a["contacts"]
	var cb: Dictionary = b["contacts"]
	for id: int in ca:
		_contacts[id] = _lerp(ca[id], cb.get(id, ca[id]), t)


## Position (m) a fraction t from a to b along the minimum image, wrapped.
func _lerp(a: Vector3i, b: Vector3i, t: float) -> Vector3:
	var d: Vector3 = NetCodec.pos_of(NetCodec.diff(b, a, p_units))
	return min_image(NetCodec.pos_of(a) + d * t)


## Wraps each axis of a position or offset (m) into [-P/2, P/2) (no wrap without P).
func min_image(v: Vector3) -> Vector3:
	if p_units <= 0:
		return v
	var p: float = float(p_units) / NetCodec.POS_Q
	return Vector3(
		fposmod(v.x + p / 2.0, p) - p / 2.0,
		fposmod(v.y + p / 2.0, p) - p / 2.0,
		fposmod(v.z + p / 2.0, p) - p / 2.0
	)
