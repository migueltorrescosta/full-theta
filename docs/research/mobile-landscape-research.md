# Mobile landscape layout for browser games: research for Full Theta

Date: 2026-10-27. Web search only (snippets, not full-page reads); items marked (unverified) rest on one secondary source or my own knowledge. Search coverage was thin for Godot-specific safe-area behaviour and for Poki/itch.io guidance.

## 1. Orientation

- `screen.orientation.lock()` works on Android Chrome only while the page is fullscreen. Caniuse lists iOS Safari as unsupported for `lock()` from 3.2 through 26.5 (the read-only `type`/`angle`/`onchange` parts work from 16.4). https://caniuse.com/wf-screen-orientation-lock , https://bugs.webkit.org/show_bug.cgi?id=257695
- iPhone Safari has no element Fullscreen API. iPad has it. A WebKit comment from June 2026 says Safari 27 beta still has nothing for iPhone. https://developer.apple.com/forums/thread/770080 , https://www2.webkit.org/show_bug.cgi?id=206854 . So on iPhone you cannot lock landscape and cannot hide browser chrome by API.
- PWA manifest `orientation` is ignored on iOS Safari, and `display: fullscreen` misbehaves there (WebKit bug 280181, Sept 2024). The accepted workaround is a CSS "rotate your device" overlay. https://FrontendMasters.com/courses/pwas/manifest-orientation-theme-color/ , https://bugs.webkit.org/show_bug.cgi?id=280181
- Portals: CrazyGames allows landscape or portrait, lets the developer declare supported orientations at submission, and the site shows the rotation prompt itself, so no lock logic is needed. https://docs.crazygames.com/requirements/technical . Poki wants the game to fill the screen in either orientation at 16:9 scaling. https://sdk.poki.com/requirements . I found no itch.io guidance (unverified).
- Godot web export: Godot 4 web is WebGL2/Compatibility only. The canvas is the main Window, and `html/canvas_resize_policy = Adaptive` fills the page. The docs say nothing about orientation or safe areas. A custom HTML shell is where `viewport-fit`, the rotate overlay and fullscreen buttons belong. https://docs.godotengine.org/en/4.2/classes/class_editorexportplatformweb.html
- Pattern in practice: landscape-first design, a CSS `@media (orientation: portrait)` overlay or banner, an optional "Fullscreen" button that calls `requestFullscreen()` then `orientation.lock('landscape')` inside try/catch where supported. Feature-detect with `"lock" in screen.orientation`.

## 2. Viewport

- `100vh` equals the large viewport, so it overflows when browser chrome is showing. Use `100dvh` (tracks chrome) or `100svh` (chrome always visible), with a `vh` fallback. Support is now broad. https://web.dev/blog/viewport-units . Dynamic units ignore the virtual keyboard.
- `viewport-fit=cover` is required for `env(safe-area-inset-*)` to be non-zero. Without it the browser letterboxes. In landscape the left and right insets matter (notch/Dynamic Island side), plus the bottom home-indicator inset. Wrap as `max(8px, env(safe-area-inset-left))`. Cover without inset handling hides content behind the notch. https://webkit.org/?p=7929 , https://sizzy.co/blog/safe-area-insets
- In a Godot canvas the insets must be applied to a wrapper element around the canvas (shell CSS), or passed into the engine as margins. Whether `DisplayServer.get_display_safe_area()` reports anything on web is unconfirmed (my search found nothing).
- Chrome collapsing: Android Chrome hides its bar on scroll and iOS Safari collapses on scroll. A non-scrolling full-viewport canvas never triggers it, so landscape iPhone shows a thin top bar plus the home indicator and Android can enter fullscreen by button.

## 3. Touch ergonomics

- Minimums: Apple HIG 44x44 pt, Material 48x48 dp, WCAG 2.2 SC 2.5.8 AA 24x24 CSS px (or spacing so 24 px circles don't overlap), SC 2.5.5 AAA 44x44. https://allaccessible.org/blog/wcag-258-target-size-minimum-implementation-guide , https://frontendchecklist.io/rules/accessibility/touch-targets . Use 48 px for primary controls, 44 px floor for secondary, with gaps of at least 8 px.
- Landscape holding: two thumbs rest at the left and right edges, so put continuous controls (sliders, throttle, joystick-like) and frequent buttons in the two side rails. The bottom centre is the iOS home-indicator swipe area and the Android gesture-nav area, so keep nothing tappable in the bottom ~16-24 px strip (inset-bottom). The middle is the glance area for read-only information. Thumb-zone specifics came from general knowledge, not from a fetched source (unverified).
- Text: keep body text at 14-16 CSS px or more on a phone, and nothing below about 12 px. Dense numerals for a held-at-arm's-length device need more.

## 4. Dense control UI on short landscape screens (360-430 px tall)

- Usable height after chrome and insets is often 300-380 px. Plan for a 300 px design height.
- Patterns: left and right rails with the primary controls, a central read-out, a top strip of 32-40 px for status (not interactive), collapsible secondary panels (drawers opened from a rail button), and tabs inside a rail for secondary groups. Prefer tabs or pages to vertical scrolling on a control surface, because scroll steals touches from sliders and drags. Where scrolling is unavoidable, scroll one panel only.
- Overlays: a modal should use the full height as a sheet, never stack a second overlay (keyboard + dialog + toast). Reserve one toast lane at the top centre. The soft keyboard halves the height, so text entry uses an HTML input outside the canvas (the repo already does this, D196).

## 5. Performance, battery, keep-awake

- Cap the render scale on phones: devicePixelRatio of 3 means about 9x pixels of a 1x canvas. Cap the effective DPR at 2 (or 1.5 on weak devices) with the canvas resize policy or the engine's scaling, since fill rate is the main battery cost in landscape at 2400x1080 native. This is general practice, not from a fetched source (unverified).
- Screen Wake Lock: supported on iOS Safari 16.4 and later, Chrome and Edge 84, Firefox 126. It needs a secure context (HTTPS) and must be re-requested after `visibilitychange`. A 2023 WebKit bug reports it failing in home-screen apps. https://developer.chrome.com/docs/capabilities/web-apis/wake-lock , https://caniuse.com/wake-lock , https://bugs.webkit.org/show_bug.cgi?id=254545
- Consequence for Full Theta: plain HTTP over the LAN (D207) is not a secure context, so wake lock, and any fullscreen or service-worker help, are unavailable there. Tailscale serve HTTPS would provide them. A fallback is a tiny looping hidden video (NoSleep.js style, unverified).

## 6. Accessibility (WCAG 1.3.4)

- SC 1.3.4 (AA, WCAG 2.1): content must not restrict its view and operation to a single orientation unless a specific orientation is essential. W3C examples of essential cases are bank cheque, piano app, projector slides, VR. Games are not listed. https://www.w3.org/WAI/WCAG22/Understanding/orientation
- Games usually claim "essential" for landscape-only, but it is a judgement per game. A defensible reading needs the justification written down. The safest design: the layout still works in portrait (possibly reflowed, scrollable or with fewer panels visible at once) and the rotate prompt is a dismissible suggestion, not a block. Users with devices mounted in a fixed orientation (wheelchair mounts) are the people this protects.

## Comparison with the repo

- D195 (2026-10-24): menu, join, lobby, Captain, Viewer, Engineering, Relay get phone layouts; Helm, Weapons, Science stay tablet-sized, cramped on a phone. No orientation rule is stated.
- D196: join without typing, HTML input overlay for text. Consistent with section 4.
- D216: lobby grid 3x2 in landscape, 2x3 in portrait, same on every device. This is a responsive approach and meets 1.3.4. Consistent with the recommendation to keep portrait usable.
- D218: theme touch targets at least 44 px, 16 px base font. Meets Apple and WCAG AAA, 4 px short of Material 48.
- D223: layout chosen by physical size and pointer kind, independent of UI scale. Sound. Add orientation as a second input: a phone in landscape is about 360-430 px tall, which is the case that needs the side-rail layout.
- D207: plain HTTP, no service worker. Rules out wake lock and secure-context APIs on LAN.
- Spec FT-STN-005 / item 109: "phone layouts for the menu, lobby, Captain, Viewer, Engineering and Relay". No safe-area, orientation or wake-lock requirement exists in decisions or spec (grep for orientation, safe.area, fullscreen, wake returned nothing relevant).

Disagreements with best practice:
1. Helm, Weapons and Science left "cramped" on phones. These are likely the most touch-intensive stations, and a cramped control surface fails the 44-48 px target rule.
2. No stated handling of notch/home-indicator insets or `viewport-fit=cover`.
3. No decision on orientation (prompt, lock, or both) and no 1.3.4 position.
4. No keep-awake: a phone crew station will dim and lock mid-mission, and the grace period (D188, 15 s) then disconnects it.

## Recommendations

1. Landscape-first phone layouts for all seven stations, with a dismissible "rotate for the best layout" banner in portrait (CSS media query in the web shell). Trade-off: more layout work than portrait reflow, but the control surface fits; the banner keeps 1.3.4 satisfied only if portrait remains operable.
2. Keep portrait operable but reduced: stack rails into a bottom tab bar or a single scrolling column. Trade-off: extra layout per station; alternative is to claim the "essential" exception for Helm/Weapons/Science and document it (cheaper, riskier). Owner choice below.
3. Add `viewport-fit=cover` to the custom shell, size the root with `100dvh`, and pad with `max(8px, env(safe-area-inset-*))` on all sides. Trade-off: needs a wrapper element outside the Godot canvas, so the canvas shrinks by the inset.
4. Side-rail controls: sliders, throttle and fire buttons in the left and right 20-25% of the width, status read-outs in the middle, nothing tappable in the bottom 24 px. Targets 48 px primary, 44 px floor, gap 8 px. Trade-off: fewer controls visible at once, so secondary groups go to tabs or a drawer.
5. Optional "Fullscreen" button (Android and iPad), calling `orientation.lock('landscape')` in try/catch after `requestFullscreen()`. Skip on iPhone. Trade-off: small shell code, no effect on iPhone.
6. Cap DPR at 2 on phones and expose a quality setting. Trade-off: slightly softer text on 3x screens.
7. Keep-awake: request Wake Lock on station join and re-request on `visibilitychange` (needs HTTPS), else fall back to the hidden-video trick. Trade-off: HTTPS on the LAN needs a cert, or use Tailscale serve.
8. Test the shell on a real iPhone in landscape (insets, bottom bar, rotate overlay) and on Android Chrome; emulators don't reproduce Safari chrome behaviour.

## Owner choices

- A: portrait on Helm, Weapons and Science: operable reflow (recommended, meets 1.3.4) versus landscape-only with a documented "essential" claim.
- B: serve over HTTPS (Tailscale serve) so wake lock works, versus keep plain HTTP and use the video fallback.
