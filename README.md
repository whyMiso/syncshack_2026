# SayHi — Hand Gesture Control for macOS

SayHi watches your MacBook's camera and triggers configurable actions when it
recognises hand gestures: make a fist to take a screenshot, show an open palm
to launch Chrome, and so on. All recognition happens on-device using Apple's
Vision framework — no video ever leaves your Mac.

## How it works

```
Camera (AVFoundation)          ~24 fps, 640×480, mirrored
        │
HandPoseDetector (Vision)      VNDetectHumanHandPoseRequest, 1 hand,
        │                      21 joint landmarks + confidences
GestureClassifier              geometry rules on landmark positions,
        │                      normalized by hand size → gesture + confidence
GestureStateMachine            hold-to-trigger, dropout grace, cooldown,
        │                      rearm (gesture must disappear before refiring)
ActionExecutor                 screenshot / launch app / hide app /
                               minimise window / media control / open URL /
                               run Shortcut / keystroke / macro
```

Classification is rule-based, not ML-trained. Each finger gets a continuous
"extension score" — how far its tip reaches beyond its PIP joint, measured
from the wrist and divided by hand size (wrist → middle-MCP distance), so the
rules work at any distance from the camera. Gestures are combinations of
those scores plus direction checks (e.g. thumbs-up requires the thumb tip to
rise above its base joint). All thresholds live in one struct,
`GestureConfig`, for easy tuning.

### Recognised gestures

| Gesture | Shape | Distinguishing geometry |
|---|---|---|
| ✊ Closed Fist | all fingers curled, thumb tucked | four fingers folded + thumb close to palm |
| 🖐️ Open Palm | all fingers straight | four fingers extended (thumb ignored — splay varies) |
| 👍 Thumbs Up | fist with thumb up | four folded + thumb spread from palm + tip above its base |
| 👎 Thumbs Down | fist with thumb down | same, but thumb tip below its base joint |
| ✌️ Peace | index + middle up | index/middle extended, ring/little folded |
| ☝️ Point Up | index only, upward | index extended, others folded, tip above its PIP |
| 👌 OK Sign | thumb-index ring, others up | thumb and index **tips touching** + middle/ring/little extended |
| 🤘 Rock | index + little up | index/little extended, middle/ring folded |
| 🤙 Call Me | thumb + little out | little extended + thumb spread, middle three folded |
| 3️⃣ Three Fingers | index + middle + ring up | those three extended, little folded |
| 👇 Point Down | index only, downward | index extended, others folded, tip below its PIP |
| 👈 Point Left | index only, leftward | index extended, tip clearly left of its PIP |
| 👉 Point Right | index only, rightward | index extended, tip clearly right of its PIP |

The four pointing directions share one rule: whichever axis the index tip
favours relative to its PIP joint decides the direction, and a diagonal that
favours neither is rejected rather than assigned one at random. Because a
finger's extension score is its distance from the *wrist*, it is unaffected by
how the hand is rotated — so pointing sideways or down still reads as an
extended finger.

Note "three" here is index-middle-ring; the thumb-index-middle version reads as
a peace sign, since peace deliberately ignores the thumb.

Adding another gesture is a `Gesture` case plus one rule in
`GestureClassifier` — the mapping UI, persistence, HUD and debug panel all
pick it up automatically.

### Left and right hands are separate

Every action is bound to a **`GestureBinding` = gesture + hand**, so the same
thirteen shapes give you **26 slots**: a left fist and a right fist can do
completely different things. Two details make this work in practice:

- **Mirroring is undone.** The analysis frames are mirrored to match the
  selfie-style preview, so Vision sees your real right hand as a left one.
  `HandPose.userHandSide` flips the reported chirality back, so "Left" in the
  UI always means *your* left hand.
- **Chirality is smoothed.** Vision's per-frame handedness flickers on
  ambiguous poses (a fist head-on looks similar either way). Because the hand
  is half the binding key, one flickered frame would look like a different
  gesture and restart the hold timer — so `ChiralitySmoother` takes a majority
  vote over a ~0.75 s rolling window, with ties keeping the current decision.

If Vision genuinely can't tell (rare), the status bar shows "Hand side
unclear" and nothing fires, rather than guessing and running the wrong action.

### Anti-accidental-trigger design

A gesture fires only after being held steadily for **0.8 s** (progress bar
shows "Hold gesture…"). Sub-0.25 s detection dropouts don't reset the hold.
After firing there is a **1.5 s cooldown**, and the *same* gesture must then
leave the frame for 0.4 s before it can fire again — holding a fist forever
produces exactly one screenshot.

The hold bar is drawn directly from the hold's start time and redrawn at
display rate, rather than from the gesture samples or via `ProgressView`
(which is `NSProgressIndicator`-backed on macOS and animates toward values on
its own, leaving the fill trailing behind). It tracks in real time and
finishes full.

### Gesture cheat sheet

Press **⌥⌘G** (configurable in Settings, or via the menu bar) to pop up a panel
listing every gesture and the action bound to it for each hand, floating over
whatever app you're in. Press again — or click it — to dismiss.

The hotkey uses Carbon's `RegisterEventHotKey` rather than an `NSEvent` global
monitor: global monitors need Accessibility permission, Carbon hotkeys need
none. Settings shows whether the combination registered or is already taken by
another app.

### Pausing with a gesture

One gesture can be assigned **Pause / Resume Gestures**, which switches every
*other* gesture off so you can talk with your hands, type, or gesture at
someone without anything firing. Out of the box this is 🤙 **Call Me** on
either hand — deliberate enough not to happen by accident — and it can be
moved to any gesture in the Gestures tab.

Two details make it behave like a real switch rather than a trapdoor:

- It is handled **before** the actions-enabled gate, so it keeps working while
  everything is paused. Otherwise pausing would be one-way and need the
  keyboard to undo.
- While paused, the floating HUD stays silent for every gesture *except* this
  one. Popping the overlay up as you move your hands is exactly what pausing
  is meant to stop — but you still see the hold bar when switching back on.

The Camera tab still reports what would have run, so it stays useful for
practising. This is the same switch as the **Actions** toggle in the toolbar
and menu bar; all three drive one setting.

### Status indicator

A small pill sits in the top-right of the primary display, under the menu bar,
showing **Active** (green), **Paused** (orange) or **Off** (grey) — readable
from any app, across Spaces and full-screen. It is click-through, so it never
swallows a click meant for what's underneath, and can be switched off in
Settings → Feedback.

It observes only the two switches it reports, not `AppState`: that publishes on
every analysed frame, and an always-on-screen overlay bound to it would
re-render ~24×/s to draw a dot that rarely changes. It also anchors its *right*
edge, since "Paused" is wider than "Off" and SwiftUI relays out after the state
changes rather than during it — anchoring the left edge would let the longer
labels grow off the side of the screen.

### Camera overlay

Press **⌥⌘C** (configurable, or use the menu bar / Settings) for a small
always-on-top camera view with the hand skeleton drawn on it, plus the current
gesture and confidence underneath. Useful for checking you're framed and being
tracked while working in another app.

Unlike the HUD and cheat sheet it is **draggable** — park it anywhere and its
position is remembered across launches. A saved position on a display that is
no longer connected is discarded rather than stranding it off-screen. Three
size presets are available in Settings.

Borderless panels aren't movable by default, and `isMovableByWindowBackground`
is unreliable once an `NSHostingView` covers the window, because SwiftUI's view
claims the click. The overlay's container instead overrides `hitTest` to take
every mouse-down itself and calls `performDrag(with:)` — safe here precisely
because the overlay contains nothing clickable.

When SayHi's window isn't in view, a small floating HUD appears at the
top-center of the active screen (above all windows, across Spaces and
full-screen apps) showing the hold-progress bar and the trigger confirmation,
so you always see what's about to fire.

### Liquid Glass

Every surface in the app — the window's cards, the cheat sheet, the HUD, the
status pill, the camera overlay's status strip — is drawn on Apple's Liquid
Glass material rather than on flat materials.

The package still deploys to macOS 14, while the real API (`glassEffect`,
`Glass`, `GlassEffectContainer`, `.buttonStyle(.glass)`) is macOS 26+. Rather
than sprinkling `#available` through the view code, `UI/LiquidGlass.swift`
wraps each concept once — `glassCard`, `glassCapsule`, `glassSurface`,
`glassButton`, `GlassStack` — and each helper picks the genuine effect where it
exists, falling back to a material plus a top-lit hairline rim that reads the
same way on 14 and 15. Radii, rim gradients and shadow depths are decided in
that one file, so the panels stay a matched set.

Three details are load-bearing rather than decorative:

- **Interactive glass is opt-in, and used exactly once.** `Glass.interactive()`
  adds hover and press response, which is right for the mapping grid's action
  cells and wrong everywhere else: the status pill and the HUD are
  click-through panels, and the camera overlay's `DragToMoveView` claims every
  mouse event for dragging. Those surfaces would be animating in response to
  events they can never receive.
- **Regular and clear are a hierarchy, not a preference.** Nesting two regular
  layers reads as one muddy slab, so anything sitting *on* another glass
  surface — the debug panel under the status card, the status chip on the cheat
  sheet, the toolbar's switch cluster inside the (already glass) toolbar — uses
  the clear recipe instead.
- **The HUD's three states are one capsule.** Hold, triggered and the result
  banner share a `glassEffectID` inside a `GlassStack`, so the pill *morphs*
  between them instead of cross-fading. They are three stages of one event, and
  now they look like it.

The hold-progress bar is the one thing deliberately left un-glassed: it redraws
at display rate inside a `TimelineView`, and it is the single place in the app
where compositing a glass layer per frame would actually cost something. It
takes a gradient fill and a hairline rim instead.

Glass also needs something behind it to bend, so the window's tabs are backed
by `GlassBackdrop` — a static, three-stop colour wash. Static on purpose: the
app is already spending CPU on per-frame Vision work.

## Building and running

Requires macOS 14+ and Xcode command-line tools (built with Xcode 26 / Swift 6.3).

```bash
./build.sh --run
```

This runs `swift build -c release`, assembles `build/SayHi.app` with the
proper `Info.plist` (the bundle is required for the camera permission prompt
to work), codesigns it with a stable identity (see Permissions), and opens it. Use `./build.sh --debug` for a
debug build, or plain `swift build` to just compile.

## Using the app

1. Flip **Gesture Control: ON** in the toolbar (or the menu bar item — the
   hand icon). macOS will ask for camera permission the first time.

   There are two independent switches:

   | | Camera | Recognition | Runs actions |
   |---|---|---|---|
   | **Gesture Control: OFF** | stopped | — | — |
   | **Gesture Control ON, Actions OFF** | running | yes | **no** |
   | **Both ON** | running | yes | yes |

   **Actions: OFF** keeps everything visible — detected gesture, confidence,
   hold progress, and a grey banner naming the action that *would* have run —
   without launching apps or taking screenshots. It's the mode to use when
   practising a gesture or tuning thresholds.
2. The **Camera** tab shows the live preview, the detected hand skeleton, the
   current gesture with confidence, and hold/cooldown progress. A banner
   confirms every triggered action ("Closed Fist → Screenshot saved").
3. The **Gestures** tab is a grid: one row per gesture, one column per hand.
   Click any cell to assign that hand's action — Screenshot, Launch
   Application (pick from /Applications), Open URL, Run macOS Shortcut
   (picked from `shortcuts list`), or a Keyboard Shortcut (key + ⌘⇧⌥⌃
   modifiers). Dashed cells are unassigned.
   **Media Control** gives Play/Pause, Next Track, Previous Track, Volume
   Up/Down and Mute. These are sent as media keys, which macOS routes to
   whatever is currently playing — Spotify, Music, video in a browser —
   without that app needing to be frontmost. Verified end-to-end against
   Spotify. Needs Accessibility permission, like the other synthetic-input
   actions.

   **Hide Application** hides an app's windows (the frontmost one, or a
   specific app you pick) — recoverable from the Dock, and it needs no extra
   permission. **Minimise Window** sends the frontmost window to the Dock like
   the yellow button; that drives another app's window controls through the
   Accessibility API, so it needs Accessibility permission.

   Assigning **Macro** instead gives an ordered list of steps — type text,
   press keys, wait, open an app, hide an app, minimise a window, send a media
   control, open a URL, run a Shortcut — run in
   sequence. A fist can open Mail, wait for it, type a whole reply and press
   ⌘Return. Text is typed as Unicode rather than mapped to key codes, so
   punctuation, accents and emoji all come out exactly as written, whatever
   your keyboard layout.

   Two things to know about macros: typed text goes to whichever app is
   **frontmost when the gesture fires**, and mappings are stored as plain
   text, so macros are not a safe place for passwords. Macros that type or
   press keys need Accessibility permission — the same grant the Keyboard
   Shortcut action uses — and are checked up front so a macro can't stop
   halfway through.

4. The **Settings** tab controls timing and sensitivity without touching code:

   - **Triggering** — hold-to-trigger duration, cooldown, re-arm delay and
     dropout tolerance, with a live readout of the fastest possible repeat.
   - **Recognition** — minimum confidence (raise it if actions fire by
     accident) and analysis frame rate. Detection costs only ~3 ms per
     frame, so the gap *between* frames is what sets input latency —
     lowering the rate saves little CPU but makes gestures feel sluggish.
   - **Advanced** (collapsed) — the finger/thumb/pinch thresholds the shape
     rules are built from.
   - **Camera overlay** — on/off, size preset, and its hotkey.
   - **Feedback** — HUD on/off and top/bottom placement, skeleton overlay.
   - **Startup** — turn gesture control on automatically at launch.
   - **Reset recognition settings** restores factory thresholds and leaves
     your gesture mappings untouched.

5. The **Debug** toggle on the Camera tab shows per-finger extension scores,
   thumb spread/rise, pinch distance, candidate gesture, consecutive frames,
   state-machine phase, and detected hand — pair it with Actions OFF to tune
   thresholds safely.

Mappings persist in `~/Library/Application Support/SayHi/mappings.json`,
keyed `"gesture.hand"` (e.g. `"fist.left"`). First-run defaults: fist →
screenshot and open palm → Chrome (Safari if Chrome isn't installed), applied
to **both** hands so handedness is opt-in; the rest are unassigned. Mapping
files written before handedness existed are migrated automatically by giving
both hands whatever you had already configured.

## Permissions

The **Settings tab shows live permission status** for all three, with a button
straight to the relevant System Settings pane. macOS only applies a newly
granted permission when the app next launches, so quit and reopen SayHi if one
still reads as missing after granting it.

> **Signing matters here.** An ad-hoc signature has no stable identity, so
> macOS keys permission grants to the binary's hash — which changes on every
> build, silently invalidating every grant and re-prompting. `build.sh` now
> signs with a real code-signing identity if one is present in your keychain
> (override with `SAYHI_SIGN_IDENTITY`), which keeps the app's identity stable
> across rebuilds so permissions stick. It falls back to ad-hoc with a warning
> if no identity is found.


| Permission | Why | When asked |
|---|---|---|
| **Camera** | Reading frames for hand-pose detection. | First time you enable gesture control. |
| **Screen Recording** | The Screenshot action uses `screencapture`; without this it captures only the wallpaper. | First screenshot. Grant in System Settings → Privacy & Security → Screen Recording. |
| **Accessibility** | The Keyboard Shortcut action posts synthetic key events via `CGEvent`. | When you configure/trigger a keystroke action, with a prompt directing you to System Settings → Privacy & Security → Accessibility. |

Launch App, Open URL, and Shortcuts need no special permissions.

**Privacy:** frames are handed to Vision and immediately discarded — nothing
is stored, uploaded, or transmitted. There is no network code in the app.

## Architecture / source layout

```
Sources/SayHi/
  App/         SayHiApp (scenes), AppState (pipeline coordinator, UI state)
  Camera/      CameraManager (session, frame throttling)
  Recognition/ Gesture, GestureConfig (all thresholds), HandPoseDetector
               (+ChiralitySmoother), GestureClassifier, GestureStateMachine
  Actions/     GestureAction (+KeyCombo, Codable), ActionExecutor
  Persistence/ GestureMappingStore (JSON in Application Support),
               SettingsStore (UserDefaults, writes through to GestureConfig)
  UI/          LiquidGlass (glass design layer: helpers, metrics, backdrop),
               ContentView, RecognitionView (+DebugPanelView),
               CameraPreviewView (landmark overlay), MappingsView
               (+ActionEditorView), MacroEditor, SettingsView,
               HoldProgressBar, GestureHUD, CheatSheet, CameraOverlay,
               StatusIndicator, MenuBarView
  System/      GlobalHotKey (Carbon RegisterEventHotKey wrapper)
Support/Info.plist   bundle template (camera usage description)
build.sh             builds + assembles build/SayHi.app
```

Extension points are deliberate: new gestures are a `Gesture` case plus a
rule in `GestureClassifier`; new action types are a `GestureAction` case plus
a branch in `ActionExecutor` and a section in the editor sheet. The mapping
UI and persistence pick both up automatically. New UI surfaces should reach
for the helpers in `LiquidGlass` rather than for materials directly, so the
macOS 14 fallback keeps working without a second `#available` check.

## Known limitations / MVP compromises

- **Rule-based classification** can confuse borderline hand shapes; tilted or
  edge-on hands read as "unknown". Thresholds are tuned for a hand facing the
  camera. (Debug panel exists precisely to retune `GestureConfig`.)
- **One hand at a time.** Left/right are distinguished and bound separately,
  but only the most confident hand in frame is analysed — two-hand gestures
  aren't supported yet.
- **Handedness on symmetric poses is the weakest signal** in the app. A fist
  or an OK sign viewed straight on carries little left/right information; the
  smoother hides most flicker, but if a hand-specific action misfires, watch
  the debug panel's `Hand` cell (it shows `smoothed (raw)`) and prefer
  assigning symmetric gestures the same action on both hands.
- **Screenshot** shells out to `screencapture` rather than using
  ScreenCaptureKit, and saves to a fixed Desktop location.
- **Keyboard shortcut editor** offers a curated key list rather than a true
  "press keys to record" recorder.
- **No launch-at-login / background-only mode** — the menu bar item exists
  but the app still shows a Dock icon.
- Built as a Swift Package + bundle-assembly script rather than an `.xcodeproj`
  (no Xcode project generator was available); `swift build` + `build.sh` is
  the supported workflow. Opening `Package.swift` in Xcode also works.
- The app is not sandboxed (needed for `screencapture`, `shortcuts`, and
  CGEvent posting) and signed with a local development identity — fine for
  personal use, not for distribution.

## Next highest-value improvements

1. **A "press to record" keyboard-shortcut recorder** (NSEvent local monitor)
   and a menu-bar-only background mode with launch-at-login — turns it into a
   real daily-driver utility.
2. **Temporal smoothing of landmarks** (e.g. 3-frame median filter) before
   classification — the single biggest recognition-quality win, removing
   most flicker between gesture and unknown.
3. **More action types**: media/volume keys, AppleScript, shell commands —
   each is one `GestureAction` case + executor branch away.
4. **Custom gesture training**: capture landmark snapshots of a user-performed
   pose and match with nearest-neighbour distance — no ML model needed and it
   fits the existing classifier interface.
5. **Per-app gesture profiles** — switch mapping sets based on the frontmost
   application, so the same gesture can mean different things in Keynote and
   in a browser.
