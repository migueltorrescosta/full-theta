## TipsView for the L5 harness (#28, P28-Tips): the tips of one `topic` first, in `lang`,
## with the load bar at `progress` (negative: no bar), inside simulated `insets`
## [left, top, right, bottom] (SafeArea.simulate). The shuffle seed is fixed.
extends Control

var lang: String = "en"
var topic: String = "helm"
var progress: float = 0.62
var insets: Array = []


func _ready() -> void:
	SafeArea.simulate(insets)
	I18n.apply(lang)
	LayoutMode.apply(get_tree().root)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v: TipsView = TipsView.new()
	v.shuffle_seed = 7
	v.autoplay = false
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(v)
	var only: Array[String] = [topic]
	v.prefer(only)
	v.set_progress(progress, tr("tips.loading") % roundi(progress * 100.0))


func _exit_tree() -> void:
	SafeArea.simulate([])
	I18n.apply("en")
