# Physical-Device Feasibility

## 1. Status

Tracking: #3. The debug audio probe and this protocol prepare the experiment;
**no physical iPhone results have been collected in the cloud environment**.
The app must remain usable manually if locked-screen or inference experiments
fail. Do not close #3 based on an unsigned Simulator build or CI tests.

## 2. Preparation

Install a Debug build using [CONTRIBUTING.md](../CONTRIBUTING.md). Use only
synthetic speech and public test Issues. Note the commit, phone model, iOS and
Xcode versions, battery level, Low Power Mode, network type, and audio route. Do
not include a device serial number, Apple Account, token, or actual Issue text.

Open Settings > Diagnostics > Audio feasibility. The screen can record up to
60 seconds, play the recording, speak a fixed sentence, and show lifecycle,
route, and interruption events. Recordings stay in the app's temporary directory
and are deleted by Clear or when leaving this screen. They are not uploaded.
Do not count a backgrounded view as an actual screen-lock test.

## 3. Test Matrix

| Experiment            | Procedure                                                                                     | Required evidence                                                           | Current result                        |
| --------------------- | --------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- | ------------------------------------- |
| Foreground capture    | Record synthetic speech, stop, play it back.                                                  | Audible complete recording, permission/route events.                        | Not tested                            |
| Locked capture        | Start recording, lock for 20 seconds while speaking, unlock, stop, play.                      | Speech spoken while locked is present; duration and interruptions.          | Not tested                            |
| Locked TTS            | Start the fixed sentence, immediately lock the phone.                                         | Whether the entire sentence remains audible.                                | Not tested                            |
| Interruption          | During capture/playback, trigger a call or another audio app.                                 | Probe stops, shows an event, and requires an explicit restart.              | Not tested                            |
| Route change          | Repeat on speaker, wired route if available, and Bluetooth.                                   | Route, missing audio, restart behavior, microphone used.                    | Not tested                            |
| Background/suspension | Start/stop audio, switch apps, lock, then return.                                             | Actual lifecycle events; no assumption that polling continued.              | Not tested                            |
| Termination           | Stop audio, force-quit, relaunch.                                                             | Manual UI recovers; no claim of continuing work after termination.          | Not tested                            |
| Local inference       | Once #11 supplies an engine/model, run a fixed synthetic prompt corpus foreground and locked. | Model hash, context length, TTFT, latency, peak memory, failures.           | Blocked on #11 and a device           |
| GitHub polling        | Once authenticated polling exists, update a public fixture Issue from another device.         | Observed foreground/locked fetch times, rate limits, resume reconciliation. | Blocked on orchestration and a device |
| Power/thermal         | Compare a ten-minute idle baseline and active audio/inference session.                        | Battery delta, thermal state, route, Low Power Mode; repeat trials.         | Not tested                            |

## 4. Interpretation and Fallback

An active audio session with the audio background mode can continue in some
locked/background states. iOS still controls interruptions, suspension, thermal
limits, and termination. This capability does not schedule arbitrary background
network requests or guarantee that an on-device model can finish while locked.
Battery and memory behavior depend on the actual phone and model.

The probe intentionally stops on audio interruption. Production orchestration
must likewise present an explicit recovery state and preserve unsent drafts.
On resume, reconcile registered Issues in the foreground. Interrupted summaries
must remain unread; never mark read merely because speech was queued. Inference
failure falls back to manual text, with explicit Issue/reply selection. No
unsolicited spoken update is permitted.

## 5. Recording Results

For each row, record pass/fail/partial, test duration, repeats, and the observed
limit. Separate measurement from interpretation and include the commit tested.
Attach only synthetic observations to a PR updating this document. A failed
result is useful evidence; an unperformed test stays **Not tested**. Keep raw
recordings and logs with private content out of git and CI artifacts.
