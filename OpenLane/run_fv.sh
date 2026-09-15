#!/bin/bash

# Dynamically find paths so this works on any computer
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORTEX_ROOT="$(dirname "$SCRIPT_DIR")"
FV_DIR="$SCRIPT_DIR/Formal_Verification"
USER_ID=$(id -u)
GROUP_ID=$(id -g)

echo "[+] Booting HDLC Formal Verification container..."
echo "[1/2] Mounting $FV_DIR into container..."
echo "[2/2] Running SymbiYosys..."

# Use the correct formal verification image which guarantees sby and solvers are installed
docker run --rm \
  -v "$CORTEX_ROOT:$CORTEX_ROOT" \
  -w "$FV_DIR" \
  --user $USER_ID:$GROUP_ID \
  hdlc/formal:all \
  bash -c "sby -f fec.sby"

# Capture exit code and report status
if [ $? -eq 0 ]; then
    echo -e "\n========================================="
    echo -e "[PASS] Logic Equivalent!"
    echo -e "========================================="
    exit 0
else
    echo -e "\n========================================="
    echo -e "[FAIL] Formal Verification Failed."
    echo -e "========================================="
    exit 1
fi
