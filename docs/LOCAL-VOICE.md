# Local Inference and Voice

## 1. Requirements and Fallbacks

Build with Xcode 26 or newer to include Foundation Models. The app still targets
iOS 17; manual workflows and deterministic read-next commands work without a
model. System-model suggestions require iOS 26, an Apple Intelligence-eligible
iPhone, Apple Intelligence enabled, and the system model available/downloaded.
Availability is checked before every request. There is no cloud LLM fallback,
API key, custom model download or bundled private model. Apple manages system
model updates; the weights cannot be pinned independently of OS/system updates.

Voice input uses Apple's Speech framework with on-device recognition required.
Unsupported devices/languages or missing permissions return to text input rather
than silently using server recognition. Enable microphone and speech permissions
when starting; the first permission prompt can stop the session, so start again
after granting access. Audio buffers are not written to disk. Conversation notes
and drafts persist using the protected local workspace.

## 2. Conversation

Open Voice conversation. Start listening enables a foreground, half-duplex loop:
recognition stops before speech or inference, only final transcripts are routed,
and successful speech completion resumes listening. Stop cancels the session and
clears pending suggestions/confirmations. Interruptions, route changes,
navigation and app inactivity stop it; resumption is explicit. A listening turn
times out at 60 seconds without executing partial text. Locked-screen
recognition and barge-in are deliberately not enabled before the physical-device
feasibility tests pass.

Type or say the exact commands shown in the view, in English or Japanese. Read
next speaks one captured unread revision; it does not advance to another Issue
without another request. The completion acknowledgment and remaining count reuse
the same deterministic read controller as the manual timeline.

Natural-language input uses a fresh system-model session with bounded local
context. Responses are chat or proposals to read, switch discussion, or draft.
Say Accept suggestion to apply a proposal. Unknown Issues, unobserved reply
URLs, empty/oversized drafts and unresolved deliveries are rejected.
Related-Issue filters are presentation only. The model has no posting intent,
tool or network capability; accepting a draft only saves editable text.

## 3. Explicit Posting

Select a discussion Issue by completing a reading or accepting an explicit
switch or draft proposal. Say Post draft to hear its exact destination,
reply-source URL (or new topic) and draft. Say Confirm post within one minute to
send. The second step binds the Issue, complete body/source and deadline;
changed drafts, unmonitored Issues and unresolved deliveries invalidate it.
Quoted or embedded command words do not count as whole-user commands. Model
output is never fed into this command parser. The microphone is off while any
speech is playing.

Posting uses the existing persisted operation IDs and uncertain-delivery guards.
After a send, inspect the delivery status and explicitly restart listening; no
write is retried or resumed by speech/model completion. GitHub content and model
responses cannot call the posting API. Manual Issue-detail posting remains
available independently of recognition or model availability.

## 4. Validation Boundary

CI builds with the iOS 26 SDK, runs full SwiftLint, core routing/security tests
and Simulator tests. It cannot establish model availability, accuracy,
recognition quality, audio routes, locked-screen behavior, battery or latency on
your iPhone. Use the physical-device protocol for those measurements. Foundation
Models is a practical first engine, not a claim that every iOS 17 phone supports
local LLMs.
