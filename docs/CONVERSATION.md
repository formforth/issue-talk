# Conversation and Inbox

## 1. Local History and Context

Open Conversation from the inbox. One chronological timeline combines cached
GitHub Issue bodies, comments, completed readings and local notes. All and Issue
chips only filter presentation; they never change a posting target or the
discussion anchor. Related Issues for a new local note are explicitly selected,
independently of the visible chip. Long-press a local turn to correct zero, one
or multiple associations. GitHub source entries link back to their original
Issue/comment. Raw text remains local and selectable. Posting still requires the
explicit Issue-detail composer.

Swipe an Issue to stop monitoring. This excludes it from polling and the unread
queue without deleting cached content, drafts or conversation. Registering that
URL again resumes monitoring. Colors use a deterministic hash of the canonical
URL.

The protected workspace restores older manual-workflow data with default fields;
unresolved writes retain their operation IDs and remain blocked across
migration. The context builder selects a recent contiguous suffix within a
character budget, preceded by the saved context summary when space permits.
Older turns remain on disk. Use Context summary to edit a synopsis of older
discussion. Automatic model-generated summarization is deferred to the inference
integration.

## 2. Polling and Reading

The app polls monitored Issues while its scene is active, at most once per
minute. Reads are serialized with manual network operations. A failed polling
batch backs off for five minutes; pull to refresh retries explicitly. No update
starts speech or advances the discussion. iOS does not guarantee polling while
locked/suspended.

Unread counts count Issues, not comments. Opening a detail or changing a filter
never marks content read. Read next unread explicitly selects the first unread
monitored Issue in registration order and speaks a bounded extractive summary of
new/edited comments (up to five excerpts of 600 characters), or the Issue body.
This is a deterministic preview, not an LLM-generated semantic summary.
Remaining unread counts stay visible at the reading/reply boundary.

Only the speech completion callback acknowledges the captured revision. Stop,
interruption, route change, cancellation or leaving the view keeps it unread.
Content arriving while speech is running remains unread after that reading ends.
The next Issue is selected only on another explicit request. Read receipts and
completed-reading turns are saved atomically. Physical-device speech/lifecycle
behavior remains subject to the feasibility protocol.
