#!/usr/bin/env bash
# S7 RTF runs: each voice in a fresh process, pinned to 1 core (CPU 4, 1 ONNX
# thread) and then 2 cores (CPUs 4,5, 2 threads). One JSON line per run.
set -euo pipefail
cd "$(dirname "$0")/../.."
run() { uv run --quiet --project tools/tts python spikes/s7/s7.py rtf "$@"; }
voices=(
  "en_GB-cori-high en" "en_GB-cori-medium en" "en_US-norman-medium en" "en_US-libritts-high en"
  "it_IT-serena-high it" "it_IT-serena-medium it" "it_IT-riccardo-x_low it" "it_IT-paola-medium it"
  "pt_PT-tugão-medium pt_PT" "pt_BR-faber-medium pt_PT"
)
for v in "${voices[@]}"; do
  read -r name lang <<<"$v"
  taskset -c 4 bash -c "$(declare -f run); run $name $lang 1"
  taskset -c 4,5 bash -c "$(declare -f run); run $name $lang 2"
done
