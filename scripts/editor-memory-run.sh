#!/bin/sh
set -eu
# Gate B (ticket 67): peak memory of an edited save. Argument: display (default) or cap.
# Compile before the measured test process. No build-process memory is subtracted.
run=${1:-display}
filter=editedSaveWithEveryEditKindStaysUnderTwoGigabytes
FRISKET_EDITOR_MEMORY_RUN=0 sh "$(dirname "$0")/test-core.sh" -c release --filter "$filter"
export FRISKET_EDITOR_MEMORY_RUN="$run"
exec sh "$(dirname "$0")/test-core.sh" -c release --skip-build --filter "$filter"
