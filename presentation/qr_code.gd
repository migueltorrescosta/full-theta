class_name QrCode
extends RefCounted
## A small QR encoder (ISO/IEC 18004): byte mode, error correction level M, versions
## 1 to 5 (up to 84 bytes), the mask chosen by the standard penalty rules. Used for the
## join address in the host's lobby; QrView draws the result.
## encode() returns the modules as rows of bools (true = dark), without a quiet zone.

## Per version 1..5 at level M: [data codewords per block, blocks, ECC codewords per
## block] (ISO/IEC 18004 table 9).
const BLOCKS: Array = [[], [16, 1, 10], [28, 1, 16], [44, 1, 26], [32, 2, 18], [43, 2, 24]]
## Alignment pattern centre per version 2..5 (version 1 has none).
const ALIGN: Array[int] = [0, 0, 18, 22, 26, 30]
const MAX_VERSION: int = 5
const FORMAT_MASK: int = 0x5412
const FORMAT_POLY: int = 0x537


## The module matrix of `text`, or [] when it needs more than version 5. `mask` -1
## picks the best of the eight; 0 to 7 forces one (tests).
static func encode(text: String, mask: int = -1) -> Array:
	var data: PackedByteArray = text.to_utf8_buffer()
	var version: int = 0
	for v: int in range(1, MAX_VERSION + 1):
		if data.size() <= int(BLOCKS[v][0]) * int(BLOCKS[v][1]) - 2:
			version = v
			break
	if version == 0:
		return []
	var size: int = 17 + 4 * version
	var is_fn: Array = _function_modules(version, size)
	var base: Array = _blank(size)
	_place_data(base, is_fn, _codewords(data, version), size)
	var masks: Array = range(8) if mask < 0 else [mask]
	var best: Array = []
	var best_mask: int = 0
	var best_penalty: int = -1
	for m: int in masks:
		var grid: Array = _copy(base)
		_apply_mask(grid, is_fn, m, size)
		_draw_function_patterns(grid, version, size)
		# Scored without the format bits, as ISO/IEC 18004:2015 section 7.8 asks.
		var p: int = _penalty(grid, size)
		if best_penalty < 0 or p < best_penalty:
			best = grid
			best_mask = m
			best_penalty = p
	_draw_format(best, best_mask, size)
	return best


# --- Codewords. ---


## Data codewords with Reed-Solomon ECC, interleaved across blocks.
static func _codewords(data: PackedByteArray, version: int) -> PackedByteArray:
	var per_block: int = BLOCKS[version][0]
	var blocks: int = BLOCKS[version][1]
	var ecc_len: int = BLOCKS[version][2]
	var bits: Array[int] = []
	_push_bits(bits, 0b0100, 4)
	_push_bits(bits, data.size(), 8)
	for b: int in data:
		_push_bits(bits, b, 8)
	_push_bits(bits, 0, mini(4, per_block * blocks * 8 - bits.size()))
	while bits.size() % 8 != 0:
		bits.append(0)
	var words: PackedByteArray = []
	for i: int in range(0, bits.size(), 8):
		var w: int = 0
		for j: int in 8:
			w = (w << 1) | bits[i + j]
		words.append(w)
	var pad: int = 0xEC
	while words.size() < per_block * blocks:
		words.append(pad)
		pad = 0x11 if pad == 0xEC else 0xEC
	var divisor: PackedByteArray = _rs_divisor(ecc_len)
	var data_blocks: Array[PackedByteArray] = []
	var ecc_blocks: Array[PackedByteArray] = []
	for k: int in blocks:
		var block: PackedByteArray = words.slice(k * per_block, (k + 1) * per_block)
		data_blocks.append(block)
		ecc_blocks.append(_rs_remainder(block, divisor))
	var out: PackedByteArray = []
	for i: int in per_block:
		for block: PackedByteArray in data_blocks:
			out.append(block[i])
	for i: int in ecc_len:
		for block: PackedByteArray in ecc_blocks:
			out.append(block[i])
	return out


static func _push_bits(bits: Array[int], value: int, count: int) -> void:
	for i: int in range(count - 1, -1, -1):
		bits.append((value >> i) & 1)


## Multiplication in GF(256) modulo x^8 + x^4 + x^3 + x^2 + 1 (0x11d).
static func _gf_mul(a: int, b: int) -> int:
	var r: int = 0
	for i: int in range(7, -1, -1):
		r <<= 1
		if r & 0x100:
			r ^= 0x11D
		if (b >> i) & 1:
			r ^= a
	return r


## The generator polynomial (x - 1)(x - 2)(x - 4)... without its leading 1.
static func _rs_divisor(degree: int) -> PackedByteArray:
	var result: PackedByteArray = []
	result.resize(degree)
	result[degree - 1] = 1
	var root: int = 1
	for _i: int in degree:
		for j: int in degree:
			result[j] = _gf_mul(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = _gf_mul(root, 2)
	return result


static func _rs_remainder(block: PackedByteArray, divisor: PackedByteArray) -> PackedByteArray:
	var result: PackedByteArray = []
	result.resize(divisor.size())
	for b: int in block:
		var factor: int = b ^ result[0]
		result.remove_at(0)
		result.append(0)
		for i: int in divisor.size():
			result[i] ^= _gf_mul(divisor[i], factor)
	return result


# --- Matrix. ---


static func _blank(size: int) -> Array:
	var grid: Array = []
	for _y: int in size:
		var row: Array[bool] = []
		row.resize(size)
		row.fill(false)
		grid.append(row)
	return grid


static func _copy(grid: Array) -> Array:
	var out: Array = []
	for row: Array in grid:
		out.append(row.duplicate())
	return out


## True where the module belongs to a function pattern (not data): the three finders
## with their separators and the format strips, the timing lines, the alignment pattern
## and the dark module.
static func _function_modules(version: int, size: int) -> Array:
	var fn: Array = _blank(size)
	for y: int in size:
		for x: int in size:
			var corner_x: bool = x < 9 or x >= size - 8
			var corner_y: bool = y < 9 or y >= size - 8
			fn[y][x] = (corner_x and corner_y and (x < 9 or y < 9)) or x == 6 or y == 6
	if version >= 2:
		var c: int = ALIGN[version]
		for y: int in range(c - 2, c + 3):
			for x: int in range(c - 2, c + 3):
				fn[y][x] = true
	return fn


## Finders with separators, timing, alignment and the dark module, drawn over `grid`.
static func _draw_function_patterns(grid: Array, version: int, size: int) -> void:
	for i: int in range(8, size - 8):
		grid[6][i] = i % 2 == 0
		grid[i][6] = i % 2 == 0
	for origin: Vector2i in [Vector2i(0, 0), Vector2i(size - 7, 0), Vector2i(0, size - 7)]:
		for dy: int in range(-1, 8):
			for dx: int in range(-1, 8):
				var x: int = origin.x + dx
				var y: int = origin.y + dy
				if x < 0 or y < 0 or x >= size or y >= size:
					continue
				var ring: int = maxi(absi(dx - 3), absi(dy - 3))
				grid[y][x] = ring != 4 and ring != 2
	if version >= 2:
		var c: int = ALIGN[version]
		for dy: int in range(-2, 3):
			for dx: int in range(-2, 3):
				grid[c + dy][c + dx] = maxi(absi(dx), absi(dy)) != 1
	grid[size - 8][8] = true


## Zigzag placement of the codeword bits in the free modules; the few remainder
## modules stay light.
static func _place_data(grid: Array, fn: Array, words: PackedByteArray, size: int) -> void:
	var i: int = 0
	var total: int = words.size() * 8
	var right: int = size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert: int in size:
			for j: int in 2:
				var x: int = right - j
				var upward: bool = ((right + 1) & 2) == 0
				var y: int = size - 1 - vert if upward else vert
				if not fn[y][x] and i < total:
					grid[y][x] = ((words[i >> 3] >> (7 - (i & 7))) & 1) == 1
					i += 1
		right -= 2


static func _apply_mask(grid: Array, fn: Array, mask: int, size: int) -> void:
	for y: int in size:
		for x: int in size:
			if not fn[y][x] and _masked(mask, x, y):
				grid[y][x] = not grid[y][x]


@warning_ignore("integer_division")
static func _masked(mask: int, x: int, y: int) -> bool:
	match mask:
		0:
			return (x + y) % 2 == 0
		1:
			return y % 2 == 0
		2:
			return x % 3 == 0
		3:
			return (x + y) % 3 == 0
		4:
			return (x / 3 + y / 2) % 2 == 0
		5:
			return x * y % 2 + x * y % 3 == 0
		6:
			return (x * y % 2 + x * y % 3) % 2 == 0
	return ((x + y) % 2 + x * y % 3) % 2 == 0


## The 15 format bits of level M (00) and `mask`: BCH(15,5) with generator 0x537, XOR
## 0x5412.
static func format_bits(mask: int) -> int:
	var rem: int = mask
	for _i: int in 10:
		rem = (rem << 1) ^ ((rem >> 9) * FORMAT_POLY)
	return ((mask << 10) | rem) ^ FORMAT_MASK


static func _draw_format(grid: Array, mask: int, size: int) -> void:
	var bits: int = format_bits(mask)
	for i: int in range(15):
		var bit: bool = ((bits >> i) & 1) == 1
		if i < 6:
			grid[i][8] = bit
		elif i < 8:
			grid[i + 1][8] = bit
		elif i == 8:
			grid[8][7] = bit
		else:
			grid[8][14 - i] = bit
		if i < 8:
			grid[8][size - 1 - i] = bit
		else:
			grid[size - 15 + i][8] = bit


# --- Penalty (ISO/IEC 18004 section 7.8.3). ---


static func _penalty(grid: Array, size: int) -> int:
	var total: int = 0
	var dark: int = 0
	for transpose: bool in [false, true]:
		for a: int in size:
			var color: bool = false
			var run: int = 0
			var history: Array[int] = [0, 0, 0, 0, 0, 0, 0]
			for b: int in size:
				var v: bool = grid[b][a] if transpose else grid[a][b]
				if v == color:
					run += 1
					if run == 5:
						total += 3
					elif run > 5:
						total += 1
				else:
					_add_run(history, run, size)
					if not color:
						total += _finder_like(history) * 40
					color = v
					run = 1
			if color:
				_add_run(history, run, size)
				run = 0
			_add_run(history, run + size, size)
			total += _finder_like(history) * 40
	for y: int in size:
		for x: int in size:
			if grid[y][x]:
				dark += 1
			if x < size - 1 and y < size - 1:
				var c: bool = grid[y][x]
				if c == grid[y][x + 1] and c == grid[y + 1][x] and c == grid[y + 1][x + 1]:
					total += 3
	var cells: int = size * size
	var k: int = ceili(absi(dark * 20 - cells * 10) / float(cells)) - 1
	return total + k * 10


static func _add_run(history: Array[int], run: int, size: int) -> void:
	var r: int = run + size if history[0] == 0 else run
	history.pop_back()
	history.push_front(r)


## How many 1:1:3:1:1 finder-like patterns with 4 light modules beside them end here.
static func _finder_like(h: Array[int]) -> int:
	var n: int = h[1]
	var core: bool = n > 0 and h[2] == n and h[3] == n * 3 and h[4] == n and h[5] == n
	var count: int = 0
	if core and h[0] >= n * 4 and h[6] >= n:
		count += 1
	if core and h[6] >= n * 4 and h[0] >= n:
		count += 1
	return count
