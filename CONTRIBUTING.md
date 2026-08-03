# Contributing to RDSM Community

Thanks for your interest in improving RDSM! This repository is the open-source core
of Robotics Developer Studio for Mac.

## Ground rules

- **Native macOS only.** SwiftUI + Metal. No Electron, webviews, or cross-platform
  abstractions.
- **Cockpit, not engine.** The Mac observes, visualizes, and commands the robot over
  rosbridge. It never runs ROS nodes or talks to hardware directly.
- **The coordinate system is LOCKED.** See the coordinate notes in `CLAUDE.md` and the
  package docs before touching any rendering/transform code.
- **Match the surrounding code** — naming, comment density, and idioms.

## Getting started

1. `brew install xcodegen`
2. `cd app && xcodegen generate --spec project.yml`
3. Open `ROS2Studio.xcodeproj` in Xcode 16+, or build from the command line (see README).
4. Test against the Docker sim-bot in `testing/sim-bot` (`docker compose up -d`).

## Pull requests

- Keep changes focused; one concern per PR.
- Describe what you changed and how you verified it (manual testing against a real robot
  or the sim-bot — this project uses manual/visual verification, not unit tests).
- Public APIs should have doc comments.

## Developer Certificate of Origin (DCO)

By contributing, you certify that you wrote the code (or have the right to submit it)
and agree to license your contribution under the Apache License 2.0. Sign off your
commits with `git commit -s` (adds a `Signed-off-by:` line).

This allows RDSM Pro (the paid edition) to incorporate community contributions under
the same Apache-2.0 terms.

## License

All contributions are licensed under the Apache License 2.0.
