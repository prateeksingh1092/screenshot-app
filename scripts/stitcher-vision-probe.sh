#!/bin/sh
set -eu
export FRISKET_VISION_PROBE=1
exec sh "$(dirname "$0")/test-core.sh" --filter visionAssistedAlignmentProbe
