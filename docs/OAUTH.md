# GitHub OAuth Setup

## 1. Architecture

Issue Talk uses `ASWebAuthenticationSession`, a random state value, and PKCE
S256. It validates the complete callback origin/path and rejects duplicate
state/code parameters. Tokens are stored in device-only Keychain storage.
Expiring tokens use the refresh grant; failed/expired credentials require
signing in again. Logout removes the credential but preserves local Issue
history and drafts.

GitHub's OAuth App web flow requires a client secret at the token endpoint even
when PKCE is used. The app therefore sends the one-time code and verifier to
your HTTPS token broker. The broker adds its server-side client secret and
exchanges with GitHub. Repository contents and comments go directly between the
app and GitHub, not through this broker. No PAT or client secret belongs in the
app.

See
[GitHub's OAuth documentation](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps).
This implementation uses GitHub.com OAuth Apps, not GitHub Enterprise hosts or
GitHub Apps. The repository scope supports private Issue access and comment
posting; GitHub presents the requested permissions before authorization.

## 2. Register Your OAuth App

In GitHub Settings > Developer settings > OAuth Apps, register an application
owned by you or the organization that will operate the broker. Use your broker's
HTTPS website as the homepage and set the authorization callback URL exactly to:

```text
issuetalk://oauth/callback
```

Keep the client ID for local iPhone configuration. Store the generated client
secret only in the broker host's secret manager/environment. If your
organization requires OAuth App approval or SSO authorization, complete that
approval in GitHub. A 403/404 from a private repository may mean missing
authorization rather than a missing Issue.

## 3. Run the Token Broker

The broker is a small WSGI application with no database and no token
persistence. Its tests use synthetic responses; they do not contact GitHub.

```sh
python3 -m unittest discover -s broker -v
nix develop .#broker
# Set these using the host's secret manager, outside git and shell history:
# GITHUB_CLIENT_ID
# GITHUB_CLIENT_SECRET
# Then start the service:
gunicorn --bind 127.0.0.1:8080 --workers 2 --timeout 30 broker.oauth_broker:application
```

Deploy behind an HTTPS reverse proxy or a managed WSGI host. Forward `/token`
and `/health` at the root of the configured broker URL. Configure inbound rate
limits, request timeouts, trusted TLS certificates, and small request limits.
The application itself limits JSON input to 8 KiB and GitHub's token response to
16 KiB. It rejects unknown fields, weak PKCE verifiers, and upstream redirects.
Do not log request/response bodies, authorization codes, verifiers, or tokens.
Responses use `Cache-Control: no-store`. No CORS access is enabled.

The development service binds to loopback. A phone cannot use the Mac's
`localhost`; deploy a reachable HTTPS endpoint with a trusted certificate. The
app intentionally rejects plain HTTP and does not disable TLS/ATS validation.
Check `/health` without credentials before attempting sign-in. Live deployment
and OAuth application registration are operator setup; CI does not perform them
or pretend to verify a personal GitHub account.

## 4. Configure the iPhone Build

Copy `Configuration/Local.xcconfig.example` to `Configuration/Local.xcconfig`
and fill in your Team, bundle ID, and public OAuth configuration:

```text
DEVELOPMENT_TEAM = YOUR_TEAM_ID
ISSUE_TALK_BUNDLE_ID = com.yourname.issuetalk.personal
GITHUB_OAUTH_CLIENT_ID = YOUR_PUBLIC_CLIENT_ID
GITHUB_OAUTH_BROKER_URL = https:/$()/oauth.example.com
```

The `$()` keeps the double slash from becoming an xcconfig comment. The
resulting Info.plist value is `https://oauth.example.com`. Do not add a
client-secret key. Use the same OAuth application on the phone and broker.
Build/run as described in [CONTRIBUTING.md](../CONTRIBUTING.md), then tap
Connect GitHub. GitHub's browser session returns to the app; a bad callback or
cancelled login cannot authorize a request. Rebuilding after changing OAuth
configuration should be followed by signing out and signing in again.

## 5. Manual Workflow and Recovery

Paste a canonical `https://github.com/owner/repo/issues/number` URL and register
it. Pull to refresh its comments. Tap Reply on a comment to select its exact
URL, or explicitly choose Start a new topic. The composer names the destination
Issue and displays the reply source. Only Post comment sends a request to
GitHub. This workflow requires no LLM, speech recognition, or inference service.

Metadata, comments, reply selection, and unsent drafts are saved atomically in
protected application-support storage excluded from backups. Before a write,
the operation is saved as unresolved. If the connection, process, or decoding
fails after dispatch, it remains unresolved after restart and is not resent.
Open the Issue on GitHub and check whether the comment arrived. Discard the
unresolved draft only after checking; create a fresh draft if another send is
intended. GitHub does not provide general exactly-once comment creation, so the
app cannot safely retry an ambiguous POST on its own.

Logout removes the token from Keychain. It does not revoke the OAuth application
on GitHub or delete local Issue history. Revoke access separately in GitHub's
Authorized OAuth Apps settings when needed. Deleting the app removes its local
history, but iOS may retain Keychain items; sign out before uninstalling if you
want the stored credential removed. Share Extension registration, unified GFM/
Mermaid chat rendering, unread/voice orchestration, and model inference remain
separate Issues and are not claimed by this manual workflow.
