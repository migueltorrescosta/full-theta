class_name NumberWords
extends RefCounted
## Composes a whole number from the prerendered fragments of content/dialogue/numbers.json
## (D101, FT-AUD-018): each language has its 0-99 words whole, plus hundreds, thousands and
## connectors, so about 110-140 fragments (about 2 MB) replace S7b's 1,000 whole numbers.
## Returns fragment keys (numbers.json keys, without the "num:" prefix). Values are
## clamped to +-999,999. `feminine` picks pt_PT "uma"/"duas"/"duzentas" and it "una" for
## a feminine counted noun (the slot's `feminine` list in the dialogue JSON).

const LIMIT: int = 999_999


static func compose(n: int, lang: String, feminine: bool = false) -> PackedStringArray:
	n = clampi(n, -LIMIT, LIMIT)
	var out: PackedStringArray = PackedStringArray()
	if n < 0:
		out.append({"en": "minus", "pt_PT": "menos", "it": "meno"}.get(lang, "minus"))
		n = -n
	match lang:
		"pt_PT":
			out.append_array(_pt(n, feminine))
		"it":
			out.append_array(_it(n, feminine))
		_:
			out.append_array(_en(n))
	return out


## British English: "three hundred and forty two", "two thousand and five".
static func _en(n: int) -> PackedStringArray:
	if n < 100:
		return PackedStringArray([str(n)])
	if n < 1000:
		var out: PackedStringArray = PackedStringArray([str(n / 100), "hundred"])
		if n % 100 > 0:
			out.append_array(PackedStringArray(["and", str(n % 100)]))
		return out
	var head: PackedStringArray = _en(n / 1000)
	head.append("thousand")
	var rest: int = n % 1000
	if rest == 0:
		return head
	if rest < 100:
		head.append("and")
	head.append_array(_en(rest))
	return head


## European Portuguese: "trezentos e quarenta e dois", "cem", "cento e um", "mil e
## duzentos", "dois mil trezentos e um"; feminine "duas", "duzentas", "vinte e uma".
static func _pt(n: int, fem: bool) -> PackedStringArray:
	if n < 100:
		var u: int = n % 10
		if fem and (u == 1 or u == 2) and n != 11 and n != 12:
			return PackedStringArray(["f%d" % n])
		return PackedStringArray([str(n)])
	if n < 1000:
		if n == 100:
			return PackedStringArray(["c100"])
		var h: int = n / 100
		var head: String = "c1" if h == 1 else ("cf%d" % h if fem else "c%d" % h)
		var out: PackedStringArray = PackedStringArray([head])
		if n % 100 > 0:
			out.append("e")
			out.append_array(_pt(n % 100, fem))
		return out
	var t: int = n / 1000
	var rest: int = n % 1000
	var outk: PackedStringArray = PackedStringArray() if t == 1 else _pt(t, fem)
	outk.append("mil")
	if rest == 0:
		return outk
	if rest < 100 or rest % 100 == 0:
		outk.append("e")
	outk.append_array(_pt(rest, fem))
	return outk


## Italian: "trecento quarantadue", "mille", "duemila", feminine "una".
static func _it(n: int, fem: bool) -> PackedStringArray:
	if n < 100:
		return PackedStringArray(["f1" if fem and n == 1 else str(n)])
	if n < 1000:
		var out: PackedStringArray = PackedStringArray(["c%d" % (n / 100)])
		if n % 100 > 0:
			out.append_array(_it(n % 100, fem))
		return out
	var t: int = n / 1000
	var outk: PackedStringArray = PackedStringArray(["mille"])
	if t > 1:
		outk = _it(t, false)
		outk.append("mila")
	if n % 1000 > 0:
		outk.append_array(_it(n % 1000, fem))
	return outk
