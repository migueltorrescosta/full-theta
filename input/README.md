# input/

Devices to intents (FT-STN-005, D95). May name `stations/`, `presentation/`, `audio/`, `net/`, `shared/` and `content/` only.

## Files

- `intent_table.gd`: `IntentTable`, the one binding table. Every intent of every station and view, with its group, kind, default KB/M and controller bindings, the devices on which it ignores focus (`live`), the focused stations it still reaches its panel through (`via`) and the pitch flag. `IntentTable.target` decides who handles an intent on a screen.
- `bindings.gd`: `Bindings`, the player's rebinds and hold-to-toggle choices over the table's defaults (FT-STN-007, FT-STN-014), persisted through `to_dict`/`from_dict`.
- `input_matcher.gd`: `InputMatcher`, which turns `InputEvent`s into intent events using the live `Bindings` and the screen's context. Pure logic; time is passed in.
- `mouse_stick.gd`: `MouseStick`, Helm's mouse virtual stick (S5).
- `touch_intents.gd`: `TouchIntents`, which wires on-screen touch controls (presentation/touch/) to intents (#28).
- `binding_text.gd`: `BindingText`, the human text of a binding for the overlay, tooltips and Settings, through the `input.*` keys of `content/i18n/strings.json`.

## Binding grammar

A binding is a string in the `kbm` or `pad` list of an `IntentTable` row (or a `Bindings` override). The device list it sits in decides how its names read: "A" is the A key on KB/M and the A button on a pad.

- Keyboard keys: the names `OS.find_keycode_from_string` accepts ("T", "Space", "Enter", "Backspace", "Escape", "Tab", "Delete", "F1", "Kp 1", "Kp Add", "Equal", "Minus", "1"). They match the physical key (`physical_keycode`, named after the US layout), so WASD stays in place on other layouts. "?" matches any key press that types "?".
- Mouse buttons: "LMB", "RMB", "MMB", "WheelUp", "WheelDown".
- Pad buttons: "A", "B", "X", "Y", "LB", "RB", "L3", "R3", "View" (Back), "Menu" (Start), "Up", "Down", "Left", "Right" (d-pad). The triggers "LT", "RT" act as buttons past the trigger dead zone (0.1); the sticks "LS", "RS" act as buttons past half deflection.
- Axes (rows of kind `axis`): "LS_X", "LS_Y", "RS_X", "RS_Y", "LT", "RT", and "MouseX"/"MouseY" (the mouse stick). A leading "-" inverts ("-RS_Y"). Godot's stick Y is positive down; values pass through as they are.
- Button pair axis: "NEG/POS" ("S/W" is -1 while S is held, +1 while W is held; "LT/RT" uses the trigger values).
- Modifiers: "Shift+", "Alt+", "Ctrl+" on KB/M; any pad button on a pad ("View+X", "LB+Up", "LB+LS_X", "View+RS").
- Long press: "long RB" fires once RB has been held `InputMatcher.LONG_MS`.
- Sequence: "B,2" is B, then 2 within `InputMatcher.SEQUENCE_MS`.

## Matcher semantics

`InputMatcher.set_context(stations, focused)` sets the screen. An intent is active for an event from a device when `IntentTable.target` names a handler for it: common and live rows always, the focused station's rows, other stations' rows that are live on that device (FT-JNT-007), and rows that reach their station `via` the focused one (Weapons' KB/M fire buttons in Tactical's cockpit, FT-JNT-008). Each emitted event is a Dictionary with `id`, `group`, `target`, `kind`, `pressed`, `value` and `device`.

- Longest chord wins: when an active binding with modifiers matches ("View+X"), plain bindings on the same button ("X") don't fire. The same holds for axes: while LB is held, "LB+LS_X" suppresses "LS_X", and "View+RS" suppresses the right-stick axes.
- Identical bindings on two active intents both fire, in table order. The binding-table check exempts one pointer case, LMB select and Weapons fire: the screen consumes select only over a pickable item.
- A button that is a modifier of an active binding, or has an active "long" binding, fires its plain press on release, if released before `LONG_MS` and no chord used it (View tap opens the overlay, hold View is a modifier; RB tap cycles the target, hold RB selects the pinged item; R3 tap pings, hold R3 marks). Other plain presses fire on press.
- A sequence's first button waits up to `SEQUENCE_MS` when an active sequence starts with it. The second button fires the sequence (and not its own binding); another button, or the timeout, fires the first button's own binding.
- Kinds: `press` emits one event. `hold` emits pressed on press and released on release; a hold bound to a chord is released when either the modifier or the button is released. With `Bindings.set_toggle` each press flips it and release does nothing. A hold whose button fires on release (a tap) emits pressed and released together. `axis` rows are polled.
- `is_held` reports hold and toggle state. `release_all` and `set_context` release held and toggled intents that leave the active set (`set_context` queues them for the next `feed` or `update`).
- `device` follows every KB/M or pad event, except stick and trigger motion inside the dead zone and mouse motion under 2 px.
- `invert_pitch` flips the rows marked `pitch`.

Call `feed(event, now_ms)` from the screen's `_input` (`StationScreen._input`, which skips events a button, the tooltip or a focused text field owns; feed mouse motion only while the mouse steers) and `update(now_ms, delta)` every frame for long presses, sequence timeouts and the mouse stick's re-centring. Both return the intent events to dispatch.

## Polling axes

Axes emit no events. A radial menu held on a chord that suppresses a stick reads the raw stick with `InputMatcher.stick("RS")`. Read `InputMatcher.axis(id)` each frame: the largest deflection over the active bindings of both devices, -1..1, after dead zones, chord suppression and pitch inversion; 0 when the intent isn't active.

## Adding an intent

1. A row in `IntentTable.INTENTS` with the station's group, its kind and bindings that avoid the common and always-live keys (FT-STN-009; `tests/input/test_binding_table.gd` checks the whole table).
2. Its `intent.<id>` key in every language of `content/i18n/strings.json`.
3. A handler in the panel of its group (`StationPanel.handle_intent`), or an `axis` poll in the panel's frame update.

## Touch controls

On-screen controls have no bindings: they name the intent. `InputMatcher.touch_press(id)` (a tap: a press fires, a hold pulses or flips when it is a toggle), `touch_hold(id, down)` and `touch_axis(id, value)` give the same events and axis values as a key or a stick; `axis()` reads touch values like a stick's, and `release_all` drops them. Events carry device `IntentTable.TOUCH`, which has no live rows, so they reach the screen and the focused station only.

`TouchIntents.new(ctx.matcher, screen.dispatch)` wires widgets: `button(rail_button, id)` (a hold intent makes it a `hold` button), `stick(virtual_stick, x_id, y_id, x_sign, y_sign)`, `press(id)`, `hold(id, down)` and `axis(id, value)` for computed values (Helm's throttle feeds `helm_surge` toward a setpoint). Panels keep polling `axis` and `is_held`.
