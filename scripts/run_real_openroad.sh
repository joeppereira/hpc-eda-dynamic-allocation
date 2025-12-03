#!/bin/bash
# Run real OpenROAD with monitoring

DESIGN=${1:-gcd}
FREQ=${2:-100}
UTIL=${3:-0.6}

JOB_NAME="${DESIGN}_${FREQ}mhz_${UTIL}util"
LOG_FILE="/tmp/openroad_${JOB_NAME}.log"

echo "Running OpenROAD: $JOB_NAME"

# Start Fluent Bit in background
fluent-bit -c fluent-bit-openroad.conf &
FB_PID=$!

# Run OpenROAD in Docker with monitoring (use Rosetta on ARM Mac)
docker run --rm --platform linux/amd64 \
    -v $(pwd)/data:/data \
    openroad/orfs \
    bash -c "cd /OpenROAD-flow-scripts/flow && make DESIGN_CONFIG=designs/sky130hd/$DESIGN/config.mk synth" \
    2>&1 | tee $LOG_FILE

# Stop Fluent Bit
kill $FB_PID

echo "Complete. Log: $LOG_FILE"
