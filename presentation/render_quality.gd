class_name RenderQuality
extends RefCounted
## The graphics settings of the 3D views (E2, R20-2, R20-9): the 3D resolution, the optional
## 30 fps cap and the Low Graphics tier. The 3D views are SubViewports in stretching
## containers, so `stretch_shrink` renders them at half size while the 2D HUD above them
## stays crisp; the web page's devicePixelRatio cap (D277, D282) is untouched. `apply` is
## called when the shell starts and whenever a setting changes.

const GROUP: StringName = &"view3d"
## Shown as 'Auto' (half size on a touch layout), 'Full' and 'Half'.
const MODES: Array[String] = ["auto", "full", "half"]
const FPS_CAP: int = 30

## The `stretch_shrink` the 3D views use now.
static var shrink: int = 1


## The shrink a mode gives: 2 for half, or for auto on a touch layout.
static func shrink_for(mode: String, touch: bool) -> int:
	return 2 if mode == "half" or (mode == "auto" and touch) else 1


## Registers a 3D view's container so a setting change reaches it, and sizes it now.
static func track(container: SubViewportContainer) -> void:
	container.add_to_group(GROUP)
	container.stretch_shrink = shrink


## Applies `settings` to the tracked views, the ships' materials and the frame cap.
static func apply(settings: ClientSettings, touch: bool, tree: SceneTree) -> void:
	shrink = shrink_for(settings.render_3d, touch)
	ProceduralShip.low_graphics = settings.low_graphics
	Engine.max_fps = FPS_CAP if settings.fps_cap else 0
	for node: Node in tree.get_nodes_in_group(GROUP):
		(node as SubViewportContainer).stretch_shrink = shrink
