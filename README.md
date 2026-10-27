# Issue Talk

A SwiftUI iPhone app for a hands-free GitHub Issue inbox. The initial build
contains an empty inbox, settings navigation, and an independent Swift package.
GitHub login, issue registration, posting, persistence, local inference, and voice
are tracked in [the implementation epic](https://github.com/formforth/issue-talk/issues/1).

## Development

Use Apple Silicon macOS, Xcode 16 or newer with an iOS 17+ Simulator, and Nix
with flakes enabled. Xcode supplies the compiler, Apple SDK, simulators, and
signing. Nix supplies linting and development tools.

```sh
nix develop
open IssueTalk.xcodeproj
```

Select the shared `IssueTalk` scheme and an iPhone Simulator, then run or test.
For a personal iPhone, select your own development team and a unique bundle
identifier in Xcode locally. Never commit signing materials or user settings.

```sh
nix fmt
nix flake check --print-build-logs
nix develop .#ci --command swiftlint lint --strict
cd Packages/IssueTalkCore
swift test
```

`Packages/IssueTalkCore` is the local SwiftPM library shared by the app and tests.
It has no remote dependencies yet, so SwiftPM does not generate `Package.resolved`.
Commit generated resolution files when adding the first remote dependency.
The flake inputs start from the exact lock graph used by the referenced
`i9wa4/tmux-a2a-postman` project; update them with `nix flake update`.
All Nix configuration lives in `flake.nix` and `flake.lock`.

## Continuous integration

`ci.yml` runs formatting, Nix checks, SwiftLint, Actions security linters, a full
history secret scan, shared package tests, and iOS Simulator build/tests. The
aggregate `ci` status requires both jobs to succeed, including when a job is
skipped or cancelled. Dependabot checks Actions, Nix, and Swift dependencies
daily with a seven-day cooldown.

The only additional planned workflow is `llm-eval.yml`, scheduled or manual
when issues #11 and #13 introduce inference and evaluation. It must not download
models on ordinary pull requests. There is no evaluation workflow until then.

Physical-device launch, locked-screen audio, background execution, inference
latency, and battery behavior require an iPhone; see issue #3. Simulator success
does not establish those capabilities. No OAuth secrets or private issue content
belong in this public repository.
