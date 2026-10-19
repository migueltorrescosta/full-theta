class_name S3KeepAwake
extends RefCounted
## Keeps a browser tablet's screen on over plain http:// (FT-NET-046). The
## Screen Wake Lock API needs a secure context, which an http:// LAN page
## isn't, so this plays a tiny muted looping video, as NoSleep.js does. It has
## to start from a user gesture, and restarts when the page becomes visible
## again. The video (keepawake.webm, plus keepawake.mp4 if present) is built
## next to index.html by spikes/s3/build.sh. Uses the Wake Lock API instead
## when the page is a secure context.

const START_JS: String = """
(function () {
  if (window.isSecureContext && navigator.wakeLock) {
    navigator.wakeLock.request('screen').then(
      function () { window.ftKeepAwake = 'wakelock'; },
      function (e) { window.ftKeepAwake = 'wakelock-error:' + e.name; });
    return 'wakelock';
  }
  var v = document.getElementById('ft-keepawake');
  if (!v) {
    v = document.createElement('video');
    v.id = 'ft-keepawake';
    v.muted = true;
    v.loop = true;
    v.setAttribute('muted', '');
    v.setAttribute('playsinline', '');
    v.setAttribute('aria-hidden', 'true');
    v.style.cssText = 'position:fixed;left:0;bottom:0;width:4px;height:4px;' +
      'opacity:0.01;pointer-events:none;z-index:-1';
    [['keepawake.mp4', 'video/mp4'], ['keepawake.webm', 'video/webm']].forEach(function (s) {
      var e = document.createElement('source');
      e.src = s[0];
      e.type = s[1];
      v.appendChild(e);
    });
    document.body.appendChild(v);
    document.addEventListener('visibilitychange', function () {
      if (!document.hidden) { v.play().catch(function () {}); }
    });
  }
  window.ftKeepAwake = 'starting';
  v.play().then(
    function () { window.ftKeepAwake = 'video'; },
    function (e) { window.ftKeepAwake = 'video-error:' + e.name; });
  return 'video';
})()
"""

const STATUS_JS: String = """
(function () {
  var v = document.getElementById('ft-keepawake');
  return JSON.stringify({
    mode: window.ftKeepAwake || 'off',
    secure: window.isSecureContext,
    playing: v ? !v.paused : false,
    time: v ? v.currentTime : -1,
    src: v ? v.currentSrc.split('/').pop() : '',
    hidden: document.hidden
  });
})()
"""


## Starts the keep-awake; call it from a user gesture. Returns "video",
## "wakelock", or "" off the web.
static func start() -> String:
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval(START_JS, true))


## {"mode", "secure", "playing", "time", "src", "hidden"}, or {} off the web.
static func status() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var parsed: Variant = JSON.parse_string(str(JavaScriptBridge.eval(STATUS_JS, true)))
	return parsed if parsed is Dictionary else {}
