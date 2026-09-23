#!/bin/sh
set -eu
# Compile before the measured test process. No build-process memory is subtracted.
FRISKET_MEMORY_RUN=0 sh "$(dirname "$0")/test.sh" -c release --filter fullSizeCaptureFitsPhysicalFootprintBudget
export FRISKET_MEMORY_RUN=1
exec sh "$(dirname "$0")/test.sh" -c release --skip-build --filter fullSizeCaptureFitsPhysicalFootprintBudget
