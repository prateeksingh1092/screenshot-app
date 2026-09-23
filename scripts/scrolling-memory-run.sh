#!/bin/sh
set -eu
# Compile before the measured test process. No build-process memory is subtracted.
FRISKET_SCROLL_MEMORY=0 sh "$(dirname "$0")/test-core.sh" -c release --filter scrollingSessionFitsTheTrialMemoryGate
export FRISKET_SCROLL_MEMORY=1
exec sh "$(dirname "$0")/test-core.sh" -c release --skip-build --filter scrollingSessionFitsTheTrialMemoryGate
