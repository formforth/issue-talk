# Markdown and Diagrams

## 1. Native GFM

Issue bodies/comments and conversation entries use Swift Markdown 0.6.0 (the
Swift 6.0-compatible package) and its cmark-gfm parser. Both SwiftPM resolution
files are committed. Headings, emphasis, strikethrough, inline/fenced code,
quotes, lists, task lists, tables and HTTP(S) links render as native SwiftUI.
Raw HTML is shown as source, remote images as alt-text placeholders. Neither
executes or automatically loads external content. Source view preserves the
complete original Markdown for selection/copy and manual replies.

Parsing runs away from the main actor, caps previews at 200,000 characters and
limits nesting. Long content remains accessible in source view. Parsing and
unsafe-link policies have synthetic regression fixtures. Relative links remain
plain text; absolute GitHub Issue/comment links open externally.

## 2. Offline Mermaid

The app bundles the unmodified Mermaid 12.2.0 UMD distribution and MIT license
from the exact npm archive recorded in `Resources/Renderer/vendor.json`. The
pre-commit integrity hook verifies the SHA-256 without contacting npm. The
large-file exception applies only to this pinned asset; new downloads are not
part of PR CI. Update version, license and checksum together after reviewing the
upstream release and rerunning the WebKit tests.

Diagrams render inside an ephemeral WKWebView that can read only the renderer
resource directory. It receives source through JavaScript arguments, never HTML
string interpolation. Strict Mermaid security, disabled HTML labels, rejected
configuration/frontmatter, bounded source/edge counts, a restrictive CSP and a
navigation delegate prevent arbitrary scripts, navigation and external asset
loads. Only the bundled scripts execute. Images/fonts/network connections are
blocked by CSP, except generated data images. Native Markdown does not share
this web view or its privileges.

Source/diagram toggle, copy and fullscreen provide recovery and zoom/pan.
Invalid syntax or a renderer error falls back to original source. Light/dark
themes follow the app. Simulator tests render a flowchart and sequence, retain
an image attachment, and reject configuration injection and malformed syntax.
Those attachments are visual review aids; parser/security assertions provide the
regression checks, rather than pixel equality across Xcode/font versions.
