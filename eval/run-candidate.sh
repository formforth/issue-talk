#!/usr/bin/env bash
set -euo pipefail
model_path=$1
result_path=$2
llama-server --model "$model_path" --host 127.0.0.1 --port 8080 \
  --threads 2 --ctx-size 4096 --parallel 1 >"$result_path.server.log" 2>&1 &
candidate_pid=$!
trap 'kill "$candidate_pid" 2>/dev/null || true' EXIT
python - <<'PY'
import time
import urllib.request
for attempt in range(120):
    try:
        with urllib.request.urlopen("http://127.0.0.1:8080/health", timeout=1) as response:
            if response.status == 200:
                break
    except OSError:
        time.sleep(1)
else:
    raise SystemExit("Candidate server did not become healthy")
PY
python eval/run.py --output "$result_path" --server-pid "$candidate_pid" --backend-version "$(llama-server --version 2>&1)"
