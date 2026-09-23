#!/bin/sh
set -eu
# Compile before the measured test process. No build-process memory is subtracted.
FRISKET_EDITOR_MEMORY_RUN=0 sh "$(dirname "$0")/test-core.sh" -c release --filter tallSyntheticEditStaysUnderTwoGigabytes
export FRISKET_EDITOR_MEMORY_RUN=1
exec sh "$(dirname "$0")/test-core.sh" -c release --skip-build --filter tallSyntheticEditStaysUnderTwoGigabytes
