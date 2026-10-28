# Inference Evaluation

## 1. Reproducible CPU Candidate

`eval/model.json` pins a public Qwen 0.5B GGUF candidate by model revision,
filename, SHA-256, prompt version, temperature, seed and output limit. This is a
CPU benchmark candidate, **not** the Apple system model used by the iPhone app.
Model weights stay outside git. The downloader verifies the checksum on cache
hits as well as downloads. Review the upstream Apache-2.0 model license before
redistributing weights; CI downloads from the pinned public source.

The dedicated `llm-eval.yml` runs weekly or manually, never on ordinary PRs. It
uses the locked Nix llama.cpp backend, caches the verified model and reports
structured-output validity, intent/Issue/reply-source accuracy, actual streamed
TTFT, total latency and Linux server peak RSS when available. Artifact retention
is 14 days. The harness has no GitHub client or posting capability and accepts
only its loopback server endpoint. All cases are public synthetic
English/Japanese examples, including quoted commands and ambiguous targets.

Run the same benchmark locally on Linux:

```sh
nix develop .#eval
python eval/download.py /tmp/issue-talk-candidate.gguf
bash eval/run-candidate.sh /tmp/issue-talk-candidate.gguf /tmp/issue-talk-result.json
```

`eval/results/local-cpu.json` records an actual local run using the same pinned
weights and llama-cpp-python 0.3.16 rather than the Nix server. The execution
path and machine differ, so its timings are not a CI or iPhone performance
prediction. The small candidate's accuracy is poor: do not promote it as the app
engine. Quality metrics remain visible reports, while invalid structured output
fails execution. A green workflow alone does not approve a model for
posting/routing. Change labels or thresholds through review, never to conceal a
failed benchmark.

## 2. Fast Safety Regressions

Ordinary CI runs the core package tests without a model download. The labeled
command fixture covers positive, negative, quoted, embedded and Japanese write
phrases. Additional tests reject unknown Issues/reply sources, changed or
expired confirmations, unresolved deliveries and repeated writes. Model outputs
cannot create posting authority. These checks, not a tiny classifier's
confidence, guard side effects. Parser/rendering, transport and persistence
regressions run alongside them through the existing Swift test jobs.

## 3. Apple System Model and Traces

`LocalPrompt.version` versions the app's instructions and structured-output
contract. Bump it when instructions, schema or context selection changes. Apple
manages Foundation Models weights and does not expose an independently pin-able
weight version. For device evaluation record OS version, model availability,
locale, hardware, warm/cold state and prompt/git versions. Run the same
synthetic cases on the actual eligible phone; CPU Qwen scores do not substitute
for that.

Settings > Record inference metadata is off by default. Enabling it keeps at
most 100 protected local records with timestamp, prompt/backend/OS version,
request duration, proposed intent and outcome. It never records prompts,
transcripts, Issue IDs/URLs, bodies, drafts, responses or tokens. Delete
inference metadata clears it independently of conversation history. Timing
covers the complete structured response; it is not labeled TTFT because the app
adapter is not streaming. There is no telemetry upload or automatic trace
publication.

Device memory, power, battery and locked-screen results remain unmeasured until
the feasibility protocol is performed. Publish only synthetic/non-identifying
results, with the environment and limitations stated.
