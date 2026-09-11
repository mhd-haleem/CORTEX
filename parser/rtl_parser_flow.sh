#!/bin/bash

# ==========================================
# CONFIGURATION
# ==========================================
DESIGN="crossbar_switch"

# Update these paths to match your actual parser and OpenLane output structure
SYNTH_REPORT="designs/$DESIGN/runs/RUN_*/reports/synthesis/1-synthesis.rpt"
YOSYS_MAP="designs/$DESIGN/runs/RUN_*/reports/synthesis/1-synthesis.json"
PARSER_SCRIPT="parser.py"
PARSER_JSON_OUT="parsed_output.json"
RTL_FILES_OUT="req_rtl_files.txt"

echo "========================================"
echo " Starting OpenLane Synthesis"
echo "========================================"

# 1. Run OpenLane Synthesis
# Using a Here-String (<<<) to pass the command into the interactive docker container
make mount <<< "./flow.tcl -design $DESIGN"

# Capture the exit status
if [ $? -eq 0 ]; then
    echo "[SUCCESS] Flow completed successfully. No optimization required."
    exit 0
fi

echo "========================================"
echo " Flow failed. Running Parser..."
echo "========================================"

# 2. Run the Parser
# Adjust the flags below to match whatever arguments your parser actually expects
python3 $PARSER_SCRIPT \
    --report $SYNTH_REPORT \
    --map $YOSYS_MAP \
    --out_json $PARSER_JSON_OUT \
    --out_rtl $RTL_FILES_OUT

# 3. Display Output and Confirm
echo "========================================"
echo " 📄 PARSER OUTPUT ($PARSER_JSON_OUT):"
echo "========================================"
cat $PARSER_JSON_OUT
echo ""
echo "========================================"

read -p "Proceed with sending this JSON and the required RTL files to the LLM? (y/n): " confirm
if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
    echo "Optimization aborted by user."
    exit 1
fi

echo "User confirmed! (The script stops here for now)"