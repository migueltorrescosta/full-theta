class_name JoinAdvice
extends RefCounted
## Plain advice for a join or resume that failed (R24-1): the server's reject codes
## (NetProtocol.REJECT_*) and a socket that just closed, each as a sentence with what to try.
## The texts are in content/i18n/strings.json under `join.*`.


## The advice for a failed join to `url`: `reason` is NetClient.reject_reason, "" when the
## socket closed without an answer (wrong address, host gone, firewall).
static func for_failure(reason: String, url: String) -> String:
	match reason:
		NetProtocol.REJECT_FULL:
			return _t("join.full")
		NetProtocol.REJECT_VERSION:
			return _t("join.version")
		NetProtocol.REJECT_BAD_HELLO:
			return _t("join.bad_hello")
		"":
			return _t("join.unreachable") % url.trim_prefix("ws://").trim_prefix("wss://")
	return _t("join.other") % reason


## What the shell's banner says once it stopped retrying: the host is gone.
static func gone() -> String:
	return _t("join.gone")


static func _t(key: String) -> String:
	return TranslationServer.translate(key)
