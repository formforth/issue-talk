# Issue Talk

A SwiftUI iPhone app for a hands-free GitHub Issue inbox. The initial build
contains an empty inbox, settings navigation, and an independent Swift package.
GitHub login, issue registration, posting, persistence, local inference, and voice
are tracked in [the implementation epic](https://github.com/formforth/issue-talk/issues/1).

## 1. Development

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
nix develop .#swiftlint --command swiftlint lint --strict
cd Packages/IssueTalkCore
swift test
```

`Packages/IssueTalkCore` is the local SwiftPM library shared by the app and tests.
It has no remote dependencies yet, so SwiftPM does not generate `Package.resolved`.
Commit generated resolution files when adding the first remote dependency.
The flake inputs start from the exact lock graph used by the referenced
`i9wa4/tmux-a2a-postman` project; update them with `nix flake update`.
All Nix configuration lives in `flake.nix` and `flake.lock`.

## 2. Continuous integration

`ci.yml` runs formatting and offline linters once via `nix flake check` on Linux.
The lean CI shell adds the full-history secret scan and online Actions advisory
check. SwiftLint runs once on macOS alongside shared package tests and iOS
Simulator build/tests. The aggregate `ci` status requires both jobs to succeed,
including when a job is skipped or cancelled. Dependabot checks Actions, Nix,
and Swift dependencies daily with a seven-day cooldown.

Following `i9wa4/dotfiles`, CI uses Nix Quick Install, lockfile-based store cache
keys, and bounded cache sizes (6 GiB on Linux; 2 GiB for macOS SwiftLint). Prefix
restores reuse dependencies after lock updates; source-only changes retain the
same Nix cache key. Tool-only shells use `mkShellNoCC` to avoid installing a C
compiler. Linux Nix checks omit SwiftLint; macOS CI and local Darwin hooks run it.

The iPhone Simulator starts before dependency setup and package tests. Simulator
test parallelism is disabled for the single test suite to avoid booting clones.
SwiftPM and Xcode build products are cached by toolchain, project/dependency
definitions, and commit, with prefix restores for incremental builds. Simulator
state is not cached, and all tests still run on cache hits. Cold and warm run
times depend on runner and cache availability; no speedup is assumed without
measuring the completed workflow.

The only additional planned workflow is `llm-eval.yml`, scheduled or manual
when issues #11 and #13 introduce inference and evaluation. It must not download
models on ordinary pull requests. There is no evaluation workflow until then.

Physical-device launch, locked-screen audio, background execution, inference
latency, and battery behavior require an iPhone; see issue #3. Simulator success
does not establish those capabilities. No OAuth secrets or private issue content
belong in this public repository.
