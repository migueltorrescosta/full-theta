class_name ReleaseBundle
extends RefCounted
## What a release package carries next to the game (FT-ARC-022, TECH-4): the build
## info written at packaging, and the web export the host serves to browser
## stations. Layout (tools/release/package.py, docs/release.md):
##   Linux, Windows: <exe dir>/web/
##   macOS:          Full Theta.app/Contents/Resources/web/
## Piper and its voices: BundledPiper (audio/).

## Written into the pck by tools/release/build.sh, absent in a development checkout.
const BUILD_INFO_PATH: String = "res://build_info.json"


## {"commit": sha, "version": tag} from the packaged build, or "dev" values when
## the project runs from a checkout.
static func build_info() -> Dictionary:
	var info: Dictionary = {"commit": "dev", "version": "dev"}
	if not FileAccess.file_exists(BUILD_INFO_PATH):
		return info
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BUILD_INFO_PATH))
	if parsed is Dictionary:
		for key: String in ["commit", "version"]:
			if (parsed as Dictionary).get(key) is String:
				info[key] = (parsed as Dictionary)[key]
	return info


## The line the desktop build (`--build-info`) and the web page print: l6 compares
## them to prove the package's web export comes from the same commit (FT-TST-019).
static func build_line() -> String:
	var info: Dictionary = build_info()
	return "build: %s %s" % [info["version"], info["commit"]]


## Folder holding the package's own files: the executable's folder, or the app
## bundle's Resources folder on macOS. "" when running from a checkout.
static func resources_dir() -> String:
	if not OS.has_feature("template"):
		return ""
	return resources_dir_for(OS.get_executable_path(), OS.has_feature("macos"))


static func resources_dir_for(executable: String, macos: bool) -> String:
	var dir: String = executable.get_base_dir()
	return dir.path_join("../Resources").simplify_path() if macos else dir


## The bundled web export's folder, or "" when there is none (a checkout, or a
## package without it).
static func web_root() -> String:
	var base: String = resources_dir()
	if base == "":
		return ""
	var web: String = base.path_join("web")
	return web if FileAccess.file_exists(web.path_join("index.html")) else ""
