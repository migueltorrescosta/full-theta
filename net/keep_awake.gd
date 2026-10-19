class_name KeepAwake
extends RefCounted
## Keeps a browser tablet's screen on over plain http:// while connected
## (FT-NET-046, D108), promoted from spike S3. The client calls `start()` from
## the first tap and `stop()` when the link closes; off the web every call is
## a no-op.
##
## The Screen Wake Lock API needs a secure context, which an http:// LAN page
## isn't, so this plays a tiny muted looping video, as NoSleep.js does. It has
## to start from a user gesture. The video (keepawake.webm, plus keepawake.mp4
## if present) must sit next to index.html; spikes/s3/build.sh builds it until
## the export pipeline (#12) takes it over. Uses the Wake Lock API instead when
## the page is a secure context. Browsers release a wake lock and pause the
## video when the page is hidden, so both are taken again when it becomes
## visible, until `stop()`.

const START_JS: String = """
(function () {
  var ka = window.ftKa;
  if (!ka) {
    ka = window.ftKa = { on: false, lock: null };
    ka.lockScreen = function () {
      navigator.wakeLock.request('screen').then(
        function (s) {
          if (!ka.on) { s.release().catch(function () {}); return; }
          ka.lock = s;
          window.ftKeepAwake = 'wakelock';
        },
        function (e) { window.ftKeepAwake = 'wakelock-error:' + e.name; });
    };
    ka.video = function () {
      var v = document.getElementById('ft-keepawake');
      if (v) { return v; }
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
      return v;
    };
    document.addEventListener('visibilitychange', function () {
      if (!ka.on || document.hidden) { return; }
      if (ka.mode === 'wakelock') {
        if (!ka.lock || ka.lock.released) { ka.lockScreen(); }
      } else {
        ka.video().play().catch(function () {});
      }
    });
  }
  ka.on = true;
  ka.mode = (window.isSecureContext && navigator.wakeLock) ? 'wakelock' : 'video';
  if (ka.mode === 'wakelock') {
    if (!ka.lock || ka.lock.released) { ka.lockScreen(); }
    return 'wakelock';
  }
  window.ftKeepAwake = 'starting';
  ka.video().play().then(
    function () { window.ftKeepAwake = 'video'; },
    function (e) { window.ftKeepAwake = 'video-error:' + e.name; });
  return 'video';
})()
"""

const STOP_JS: String = """
(function () {
  var ka = window.ftKa;
  if (!ka) { return; }
  ka.on = false;
  if (ka.lock) { ka.lock.release().catch(function () {}); ka.lock = null; }
  var v = document.getElementById('ft-keepawake');
  if (v) { v.pause(); }
  window.ftKeepAwake = 'off';
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


## Lets the screen sleep again: releases the wake lock or pauses the video, and
## stops retaking them on visibility changes. Call it when the link closes.
static func stop() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(STOP_JS, true)


## {"mode", "secure", "playing", "time", "src", "hidden"}, or {} off the web.
static func status() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var parsed: Variant = JSON.parse_string(str(JavaScriptBridge.eval(STATUS_JS, true)))
	return parsed if parsed is Dictionary else {}
