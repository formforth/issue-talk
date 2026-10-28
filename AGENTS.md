# Repository Conventions

- Work through the implementation Issues in dependency order. Keep
  physical-device experiments and model availability checks explicit; do not
  claim unperformed tests.
- Use English commit messages, PR titles, descriptions, and repository
  documentation.
- Follow the lint/formatting conventions in `i9wa4/dotfiles` and
  `i9wa4/tmux-a2a-postman`. Definitions belong in pre-commit hooks in
  `flake.nix`; GitHub Actions invokes those definitions rather than maintaining
  its own rules.
- Keep all Nix logic inline in exactly `flake.nix` and `flake.lock`.
- Read `CONTRIBUTING.md` for local checks, personal iPhone installation, and PR
  rules.
- Stage new files before Nix checks. Use Xcode for authoritative Apple builds
  and signing; use injected transports and public synthetic fixtures in
  automated tests.
- Do not commit OAuth secrets, signing materials, tokens, recordings, or private
  conversations. Keep source text and unsent drafts local. Never post
  automatically.
- Distinguish a visible Issue filter from the posting target. GitHub writes
  require explicit user intent and deterministic target validation, independent
  of the LLM.
