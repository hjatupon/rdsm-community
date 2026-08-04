# RDSM Community — Architecture & Technical Guide

Native macOS cockpit for ROS 2. SwiftUI + Metal 4, talking to robots over rosbridge
(WebSocket). This repository is the open-source **core**; the shell is shared as a
SwiftPM package (`AppShell`) so the paid edition can consume it directly.

---

## Doctrine (technical)

- **Native Mac only.** SwiftUI + Metal 4. No Electron, webviews, or cross-platform
  abstractions.
- **Cockpit, not engine.** The Mac observes/visualizes/commands over rosbridge. It never
  runs ROS nodes and never talks to hardware.
- **No IDE / no code editing.** This is a visualization & debugging cockpit.
- **Coordinate system is LOCKED.** `Metal(x,y,z) = (-ROS_y, ROS_z, ROS_x)`; quaternion
  `(-ROS_qy, ROS_qz, ROS_qx, ROS_qw)`. Nav goal reverse-swizzle: `ROS(x,y) = (hitZ, -hitX)`.
- **No unit tests.** Manual/visual verification against real robots and the Docker sim-bot.
- **Swift 6 strict concurrency.** All shared state behind actors or `@MainActor`.

## Build & run

```bash
cd app
xcodegen generate --spec project.yml
xcodebuild -project ROS2Studio.xcodeproj -scheme ROS2Studio build
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'ROS2Studio.app' -path '*/Debug/*' | head -1)"
```

Min macOS 15. Xcode 16+. `brew install xcodegen`.

## Testing environment

`testing/sim-bot` — Docker (TurtleBot3 + Nav2 + rosbridge). `docker compose up -d`, then
connect to `ws://localhost:9090`.

## Architecture

- **SwiftPM packages** under `app/Packages/`, each owning one capability. Composed by a
  thin app target (`app/ROS2Studio/`, `@main` → `AppShell.AppRootScene`).
- **`AppShell`** — the shared application shell: composition root (`AppServices`), main
  window, settings, onboarding, performance, and the plugin-registry seams
  (`ProUIRegistry`, `SessionLifecycleObserver`). Paid features are injected at launch via
  these seams; the Community build registers none, so they're absent by construction.
- **Rendering** — `MetalCore` (shared context), `PointCloudRenderer`, `RobotModelRenderer`,
  `Viewer3DUI` (the 3D viewport + layer system + 14 layer types).
- **Data** — `Transport` (rosbridge v2 WebSocket), `TopicStore` (subscription fan-out +
  ring buffer), `MessageRegistry`, `Serialization`, `TFTree`, `LogStore`.
- **UI** — `ConnectionUI`, `TopicBrowserUI`, `InspectorUI` (raw/JSON inspection +
  injectable `VisualizationRegistry`), `LogViewerUI`, `PublishUI`, `ServiceCallUI`.
- **Robot model** — `RobotModelLoader` (`package://` 3-step resolution), `URDFParser`,
  `MeshLoader`, `RobotModelCore`.

### Plugin seams (open-core)

The shell references advanced features only through abstractions, so the paid edition can
inject them without the shell depending on any paid package:

- `ProUIRegistry` (in `AppShell`) — right-panel tabs, publish sheet, replay bar, bag
  manager, recording toolbar, session-lifecycle observers.
- `VisualizationRegistry` (in `InspectorUI`) — inspector visualizations + the viz-picker
  bar. The Community build ships the raw JSON tree only.
- `ViewportModeRegistry` (in `Viewer3DUI`) — alternate 3D viewport modes (e.g. an
  immersive TF visualization). The Community build ships the Scene view + basic TF tree.

## Per-package notes

Each package has its own `CLAUDE.md` with module-specific conventions (wire protocol,
render order, coordinate swizzle, subscription lifecycle, etc.). Read the nearest one when
working inside a package.

## Dev workflow — shipping a change (read this before starting work)

**Pure trunk-based, Conventional Commits.** There is no version field to bump and no
separate "ship it now" step — the PR title you write **is** the release decision.

1. Branch off `main`, implement, build/test locally (see "Build & run" above).
2. Open a PR with a **Conventional Commits title**: `feat: ...` (new capability),
   `fix: ...` (bug fix), `chore:`/`docs:`/`ci:`/`refactor:`/... (anything that
   shouldn't itself trigger a release), or `feat!:`/`fix!:` plus a `BREAKING
   CHANGE:` footer for a breaking change. **This is required, not a suggestion** —
   `lint-pr-title.yml` is a required check that blocks merge on a malformed title
   (confirmed: a non-conventional title fails the check and GitHub refuses the
   merge). Since merges are squashed, this title becomes the one commit
   `release.yml` reads.
3. `ci.yml` (compile check) must also pass — `main` is protected, no direct pushes,
   both checks required.
4. Merge. `release.yml` computes the next version from every commit since the last
   tag: any `feat:` → minor bump, `fix:` (and no `feat:`) → patch bump, a `!`/
   `BREAKING CHANGE:` footer → major bump, anything else → **no release, silently
   correct, not a failure**. A qualifying merge builds, signs, notarizes, and
   publishes automatically — Community users get it immediately via the website's
   download link.
5. **From here, everything is automatic** — you do not need to do anything in the
   Pro repo. A real release fires a downstream notification; the Pro repo picks it
   up, re-pins its dependency to the new commit, rebuilds, and publishes its own
   signed release (a sync-only merge carries Pro's own version forward unchanged
   but still ships a new build — see Pro's `CLAUDE.md`). Non-releasing merges
   (`chore:`/`docs:`/...) don't notify Pro either, correctly — nothing shippable
   happened.

Batch as many `chore:`/`docs:`/non-releasing merges as you want with zero
consequence — nothing ships until a `feat:`/`fix:`/breaking-change title lands.
That title *is* the trigger; there's no separate step to remember.

**One real failure mode already hit and fixed, worth knowing:** the breaking-change
footer check must be anchored to a real `^BREAKING CHANGE:` line — an earlier
unanchored substring match false-positived on a commit body that merely
*mentioned* the words "BREAKING CHANGE" while explaining this mechanism, and
shipped a bogus major release (caught and deleted). If a release ever fires with
an unexpectedly major bump, check the gate step's `git log` output first.

## CI/CD

- **`.github/workflows/ci.yml`** — compile-check on every PR (macos-26 / Xcode 26.3).
  Required status check.
- **`.github/workflows/lint-pr-title.yml`** — Conventional Commits format check on
  every PR title. Required status check. Both this and `build` gate merges into the
  protected `main` (no direct pushes, even from Actions, without repo-admin bypass).
- **`.github/workflows/release.yml`** — on every push to `main`, computes the next
  version from Conventional Commits history since the last tag (see "Dev workflow"
  above for the exact rule) — the version is **not** read from `app/project.yml`,
  which only carries dev-placeholder `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`
  base settings. If a bump qualifies, archives, signs with Developer ID, notarizes +
  staples, and publishes it (the app's direct-download `.zip`, served via the
  website's `/releases/latest/download` link), with the real version injected only
  at archive time via `xcodebuild` command-line overrides.
- **Downstream notification (optional, generic by design):** after a successful
  release, a step fires a `repository_dispatch` if `secrets.DOWNSTREAM_REPO` and
  `secrets.DOWNSTREAM_DISPATCH_TOKEN` are configured — no-op otherwise. Deliberately
  contains no downstream repo name, product name, or edition anywhere in this file;
  this repo has no knowledge of, and must never be made to reference, anything
  downstream of it.
