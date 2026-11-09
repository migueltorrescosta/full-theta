class_name ChipLayout
extends RefCounted
## Where a chip or label goes (R13-9, G3): the placement the disc radar, the Relay map and
## the Helm HUD share. `declutter` puts each chip beside its own blip, clear of the clock
## numbers, the blips, the stems and the other chips (D319); `gap_to`, `hits` and
## `leader_clear` are the box tests the Helm HUD's marker labels use too.

## A chip stays within this distance (px) of its own blip: when no spot is free that near,
## the chip is shortened before it is moved farther (D319).
const CHIP_REACH: float = 48.0
## The nearer reach tried first (px): a shorter chip close to its blip reads better than
## the full chip a line away.
const CHIP_NEAR: float = 24.0
const CACHE_MAX: int = 2048

static var _sizes: Dictionary = {}


## The size (px) of `text` in `font` at `font_size`: its width and the line height. Measured
## once per font, size and text (shaping a string is the dearest part of laying out chips
## every frame, R20-3); the cache is dropped when it grows past CACHE_MAX.
static func text_size(font: Font, text: String, font_size: int) -> Vector2:
	var key: String = "%d|%d|%s" % [font.get_instance_id(), font_size, text]
	if not _sizes.has(key):
		if _sizes.size() >= CACHE_MAX:
			_sizes.clear()
		_sizes[key] = Vector2(
			font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x,
			font.get_height(font_size)
		)
	return _sizes[key]


## A chip's shorter forms, longest first ("H2 · 4 high · mid", "H2 · 4 high", "H2"), with
## their sizes (px): [Array[String], Array[Vector2]]. The placement falls back on them when
## no spot near the blip is free (D319).
static func chip_forms(font: Font, chip: String, font_size: int = 13) -> Array:
	var variants: Array[String] = []
	var sizes: Array[Vector2] = []
	var all: PackedStringArray = chip.split(ChipText.SEP)
	for n: int in range(all.size(), 0, -1):
		var form: String = ChipText.SEP.join(all.slice(0, n))
		variants.append(form)
		sizes.append(text_size(font, form, font_size))
	return [variants, sizes]


## Places each chip next to its own blip, then moves it by the least that clears what it
## must not cover (spots tried: beside the default, right, left, above, below, a line off).
## Hard obstacles: the clock numbers and other boxes in `fixed`, every blip's box (entries
## with a "pos"), the chips already placed and the other items' stems; a spot also has to
## keep inside `limit` and within CHIP_REACH of its own blip. When no spot is free, the
## chip is shortened (its "variants", longest first, with their "sizes"), then may cross
## other stems (soft, as is leaving `disc`'s ellipse, charged as a cost), then takes the
## free spot nearest its blip with the callsign alone. Selected chips are placed first,
## then top to bottom. Without a blip a chip with no free spot drops below what it overlaps.
static func declutter(
	entries: Array[Dictionary],
	fixed: Array = [],
	limit: Rect2 = Rect2(),
	disc: Rect2 = Rect2(),
	blip: float = 9.0
) -> void:
	var boxes: Array[Rect2] = []
	var blocked: Array[Rect2] = []
	var stems: Array[Dictionary] = []
	for f: Variant in fixed:
		boxes.append(f as Rect2)
	for e: Dictionary in entries:
		if not e.has("pos"):
			continue
		var p: Vector2 = e["pos"]
		blocked.append(Rect2(p - Vector2(blip, blip), Vector2(blip, blip) * 2.0))
		if e.has("foot") and not e.get("beyond", false):
			var f: Vector2 = e["foot"]
			(
				stems
				. append(
					{
						"rect": Rect2(minf(f.x, p.x) - 1.0, minf(f.y, p.y), 2.0, absf(f.y - p.y)),
						"owner": e,
					}
				)
			)
	var order: Array[Dictionary] = entries.filter(
		func(e: Dictionary) -> bool: return e["chip"] != ""
	)
	order.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a.get("selected", false) != b.get("selected", false):
				return a.get("selected", false)
			return (a["chip_rect"] as Rect2).position.y < (b["chip_rect"] as Rect2).position.y
	)
	blocked.append_array(boxes)
	var placed: Array[Rect2] = []
	for e: Dictionary in order:
		var home: Rect2 = e["chip_rect"]
		var variants: Array = e.get("variants", [])
		var sizes: Array = e.get("sizes", [])
		var n: int = maxi(variants.size(), 1)
		var pick: Rect2 = Rect2()
		var text: String = e["chip"]
		# (near, then up to CHIP_REACH, with the other stems hard, then soft: every form, the
		# longest first, at each step)
		# (the spots no box covers do not depend on the step: found once per form)
		var homes: Dictionary = {}
		var frees: Dictionary = {}
		for step: Array in [
			[CHIP_NEAR, true], [CHIP_REACH, true], [CHIP_NEAR, false], [CHIP_REACH, false]
		]:
			for k: int in n:
				if not homes.has(k):
					homes[k] = home if k == 0 else _home_for(home, e["pos"], sizes[k])
					frees[k] = _free_spots(e, homes[k], blocked, placed, limit, blip)
				pick = _best_spot(e, homes[k], frees[k], stems, disc, step[1], step[0])
				if pick.has_area():
					text = variants[k] if k > 0 else text
					break
			if pick.has_area():
				break
		if pick.has_area():
			e["chip"] = text
		else:
			# No free spot near the blip: the callsign alone, nearest to it that is free of
			# the hard boxes, else stepped down below what it overlaps.
			if n > 1:
				e["chip"] = variants[n - 1]
				home = _home_for(home, e["pos"], sizes[n - 1])
			pick = home
			for _pass: int in order.size() + boxes.size():
				var hit: bool = false
				for group: Array[Rect2] in [boxes, placed]:
					for o: Rect2 in group:
						if o.intersects(pick):
							pick.position.y = o.end.y
							hit = true
				if not hit:
					break
		e["chip_rect"] = pick
		placed.append(pick)


## `home` resized to `size`, on the same side of the blip at `pos`.
static func _home_for(home: Rect2, pos: Vector2, size: Vector2) -> Rect2:
	var x: float = home.position.x if home.position.x >= pos.x else home.end.x - size.x
	return Rect2(Vector2(x, home.get_center().y - size.y / 2.0), size)


## The distance (px) from `p` to the nearest point of `r`.
static func gap_to(r: Rect2, p: Vector2) -> float:
	var dx: float = maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dy: float = maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return Vector2(dx, dy).length()


## The candidate boxes for a chip whose default box is `home` (the home first, then the
## spots round its blip) that keep inside `limit` and cover none of `blocked` and `placed`.
static func _free_spots(
	e: Dictionary,
	home: Rect2,
	blocked: Array[Rect2],
	placed: Array[Rect2],
	limit: Rect2,
	blip: float
) -> Array[Rect2]:
	var sz: Vector2 = home.size
	var spots: Array[Rect2] = [home]
	if e.has("pos"):
		var p: Vector2 = e["pos"]
		var gap: float = blip + 1.0
		var ys: Array[float] = [0.0, sz.y, -sz.y, sz.y * 2.0, -sz.y * 2.0]
		for dy: float in ys:
			spots.append(Rect2(Vector2(p.x + gap, p.y - sz.y / 2.0 + dy), sz))
			spots.append(Rect2(Vector2(p.x - gap - sz.x, p.y - sz.y / 2.0 + dy), sz))
		spots.append(Rect2(Vector2(p.x - sz.x / 2.0, p.y - gap - sz.y), sz))
		spots.append(Rect2(Vector2(p.x - sz.x / 2.0, p.y + gap), sz))
		# (corners: above and below, flush with the blip's right or left side)
		spots.append(Rect2(Vector2(p.x, p.y - gap - sz.y), sz))
		spots.append(Rect2(Vector2(p.x - sz.x, p.y - gap - sz.y), sz))
		spots.append(Rect2(Vector2(p.x, p.y + gap), sz))
		spots.append(Rect2(Vector2(p.x - sz.x, p.y + gap), sz))
	var inner: Rect2 = limit.grow(0.5) if limit.has_area() else Rect2()
	var out: Array[Rect2] = []
	for spot: Rect2 in spots:
		if inner.has_area() and not inner.encloses(spot):
			continue
		var free: bool = true
		for o: Rect2 in blocked:
			if o.intersects(spot):
				free = false
				break
		if free:
			for o: Rect2 in placed:
				if o.intersects(spot):
					free = false
					break
		if free:
			out.append(spot)
	return out


## The cheapest of the free `spots` for a chip whose default box is `home`, or an empty
## Rect2. With a blip, a spot is within `reach` of it; `hard_stems` makes the other items'
## stems obstacles too.
static func _best_spot(
	e: Dictionary,
	home: Rect2,
	spots: Array[Rect2],
	stems: Array[Dictionary],
	disc: Rect2,
	hard_stems: bool,
	reach: float = CHIP_REACH
) -> Rect2:
	var best: Rect2 = Rect2()
	var best_cost: float = INF
	var has_pos: bool = e.has("pos")
	var pos: Vector2 = e["pos"] if has_pos else Vector2.ZERO
	var home_c: Vector2 = home.get_center()
	var half: Rect2 = Rect2(disc.get_center() - disc.size / 4.0, disc.size / 2.0)
	for spot: Rect2 in spots:
		if has_pos and gap_to(spot, pos) > reach:
			continue
		var cost: float = spot.get_center().distance_to(home_c)
		# (the charges below only add: a spot already no better than the best is skipped)
		if cost >= best_cost:
			continue
		var free: bool = true
		for s: Dictionary in stems:
			if (s["rect"] as Rect2).intersects(spot):
				if hard_stems and s["owner"] != e:
					free = false
					break
				cost += 8.0
		if not free or cost >= best_cost:
			continue
		if disc.has_area():
			if not in_ellipse(disc, spot):
				cost += 10.0
			# (a ring's line through the text strikes it out)
			if _crosses_ellipse(disc, spot):
				cost += 6.0
			if _crosses_ellipse(half, spot):
				cost += 6.0
		if cost < best_cost:
			best_cost = cost
			best = spot
	return best


## True when the outline of the ellipse inscribed in `box` passes through `r`: some of the
## corners and edge midpoints of `r` lie inside it and some outside.
static func _crosses_ellipse(box: Rect2, r: Rect2) -> bool:
	var c: Vector2 = box.get_center()
	var h: Vector2 = box.size / 2.0
	var mid: Vector2 = r.get_center()
	var inside: int = 0
	var points: Array[Vector2] = [
		r.position,
		Vector2(r.end.x, r.position.y),
		r.end,
		Vector2(r.position.x, r.end.y),
		Vector2(mid.x, r.position.y),
		Vector2(mid.x, r.end.y),
		Vector2(r.position.x, mid.y),
		Vector2(r.end.x, mid.y),
	]
	for q: Vector2 in points:
		if ((q - c) / h).length_squared() <= 1.0:
			inside += 1
	return inside > 0 and inside < points.size()


## True when all four corners of `r` lie inside the ellipse inscribed in `box`.
static func in_ellipse(box: Rect2, r: Rect2) -> bool:
	var c: Vector2 = box.get_center()
	var h: Vector2 = box.size / 2.0
	for corner: Vector2 in [
		r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)
	]:
		var d: Vector2 = (corner - c) / h
		if d.length_squared() > 1.0:
			return false
	return true


## True when `box` overlaps any of `others`.
static func hits(box: Rect2, others: Array[Rect2]) -> bool:
	for o: Rect2 in others:
		if box.intersects(o):
			return true
	return false


## True when the leader from `p` to the label `box` crosses none of `avoid` (a box that
## holds `p` itself doesn't count).
static func leader_clear(p: Vector2, box: Rect2, avoid: Array[Rect2]) -> bool:
	var tip: Vector2 = Vector2(
		clampf(p.x, box.position.x, box.end.x), clampf(p.y, box.position.y, box.end.y)
	)
	for a: Rect2 in avoid:
		if a.has_point(p):
			continue
		if a.has_point(tip):
			return false
		var corners: Array[Vector2] = [
			a.position,
			Vector2(a.end.x, a.position.y),
			a.end,
			Vector2(a.position.x, a.end.y),
		]
		for i: int in 4:
			if (
				Geometry2D.segment_intersects_segment(p, tip, corners[i], corners[(i + 1) % 4])
				!= null
			):
				return false
	return true
