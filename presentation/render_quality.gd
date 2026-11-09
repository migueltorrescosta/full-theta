class_name RenderQuality
extends RefCounted
## The graphics settings of the 3D views (E2, R20-2, R20-9): the 3D resolution, the optional
## 30 fps cap and the Low Graphics tier. The 3D views are SubViewports in stretching
## containers; at half resolution each SubViewport draws its 3D at `scaling_3d_scale` 0.5
## and upscales it, while the viewport (and so `Camera3D.unproject_position`) keeps the
## container's size and the 2D HUD above it stays crisp. The web page's devicePixelRatio cap
## (D277, D282) is untouched. `apply` is called when the shell starts and whenever a setting
## changes.

const GROUP: StringName = &"view3d"
## Shown as 'Auto' (half size on a touch layout), 'Full' and 'Half'.
const MODES: Array[String] = ["auto", "full", "half"]
const FPS_CAP: int = 30

## The `scaling_3d_scale` the 3D views use now.
static var scale: float = 1.0


## The 3D scale a mode gives: 0.5 for half, or for auto on a touch layout.
static func scale_for(mode: String, touch: bool) -> float:
	return 0.5 if mode == "half" or (mode == "auto" and touch) else 1.0


## Registers a 3D view so a setting change reaches it, and scales it now.
static func track(view: SubViewport) -> void:
	view.add_to_group(GROUP)
	view.scaling_3d_scale = scale


## Applies `settings` to the tracked views, the ships' materials and the frame cap.
static func apply(settings: ClientSettings, touch: bool, tree: SceneTree) -> void:
	scale = scale_for(settings.render_3d, touch)
	ProceduralShip.low_graphics = settings.low_graphics
	Engine.max_fps = FPS_CAP if settings.fps_cap else 0
	for node: Node in tree.get_nodes_in_group(GROUP):
		(node as SubViewport).scaling_3d_scale = scale
