class_name NetTokenBucket
extends RefCounted
## Token-bucket rate limit for one client's requests (FT-NET-006): `rate` tokens a
## second up to `burst`; each command and each NetProtocol.RATED_REQUESTS message takes
## one. Wall-clock microseconds come from the caller (the server's main thread), never
## from sim/.

var rate: float = 0.0
var burst: float = 0.0
var tokens: float = 0.0
var _last_us: int = -1


func _init(per_second: float, capacity: float) -> void:
	rate = per_second
	burst = capacity
	tokens = capacity


## Takes one token at time now_us; false if the bucket is empty.
func take(now_us: int) -> bool:
	if _last_us >= 0:
		tokens = minf(burst, tokens + (now_us - _last_us) * rate / 1_000_000.0)
	_last_us = now_us
	if tokens < 1.0:
		return false
	tokens -= 1.0
	return true
