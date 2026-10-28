# Issue Talk

A SwiftUI iPhone app for a hands-free GitHub Issue inbox. The initial build
contains an empty inbox, settings navigation, and an independent Swift package.
GitHub login, issue registration, posting, persistence, local inference, and
voice are tracked in
[the implementation epic](https://github.com/formforth/issue-talk/issues/1).

For setup, checks, PR conventions, and installing on a personal iPhone, see
[CONTRIBUTING.md](CONTRIBUTING.md).

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
nix develop --command pre-commit run --all-files
# Run a single hook using the same generated configuration:
nix develop --command pre-commit run --all-files swiftlint
cd Packages/IssueTalkCore
swift test
```

`Packages/IssueTalkCore` is the local SwiftPM library shared by the app and
tests. It has no remote dependencies yet, so SwiftPM does not generate
`Package.resolved`. Commit generated resolution files when adding the first
remote dependency. The flake inputs start from the exact lock graph used by the
referenced `i9wa4/tmux-a2a-postman` project; update them with
`nix flake update`. All Nix configuration lives in `flake.nix` and `flake.lock`.

## 2. Continuous integration

Lint and formatting rules live in `pre-commit.settings.hooks` in `flake.nix`,
following `i9wa4/dotfiles` and `i9wa4/tmux-a2a-postman`. `nix develop` installs
those hooks for commits, including treefmt, the Markdown formatter, rumdl,
SwiftLint, Actions linters, secret detection, and general file checks.
`nix develop --command pre-commit run --all-files` runs the same generated
configuration on all files; append a hook ID to run just that hook.

`ci.yml` runs `nix flake check` on Linux to execute the hooks and treefmt's
formatting check. As in the reference repositories, the full-history gitleaks
scan runs separately. SwiftLint needs Xcode SourceKit, so macOS CI invokes the
same pre-commit hook outside the sandbox, alongside package and Simulator tests.
The workflow contains no separate lint rule definitions or duplicate Actions
linter commands. Darwin Nix sandbox checks use syntax-only SwiftLint; local
hooks and macOS CI use full SourceKit checks. Pinact uses offline verification
inside the sandbox and its normal behavior locally.

The aggregate `ci` status requires both jobs to succeed, including when a job is
skipped or cancelled. Dependabot checks Actions, Nix, and Swift dependencies
daily with a seven-day cooldown. All Nix logic remains inline in `flake.nix`.

Linux CI uses Nix Quick Install and lockfile-based Nix store caches, capped at
6 GiB on each platform. Prefix restores reuse dependencies after lock updates;
source-only changes retain the same Nix cache key. Tool-only shells use
`mkShellNoCC`. Cache restores are best-effort with two-minute limits; cache
availability does not decide whether the required checks pass.

macOS uses the standard Nix installer to avoid slow APFS initialization observed
with Quick Install. The iPhone Simulator starts in the background before
dependency setup and package tests. Simulator
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
