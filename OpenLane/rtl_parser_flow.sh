#!/bin/bash

# ==========================================
# CONFIGURATION
# ==========================================
# Make sure this matches your actual design folder name
DESIGN="my_design" 

PARSER_SCRIPT="rtl_parser.py"
PARSER_JSON_OUT="llm_payload.json"
RTL_FILES_OUT="critical_rtl_snippets.md"

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
echo " Flow failed. Finding latest run logs..."
echo "========================================"

# 2. Safely find the LATEST run directory to avoid Bash wildcard errors
LATEST_RUN=$(ls -td designs/$DESIGN/runs/RUN_* 2>/dev/null | head -1)

if [ -z "$LATEST_RUN" ]; then
    echo "[ERROR] Could not find any OpenLane run directories for $DESIGN."
    exit 1
fi

echo "Using latest run directory: $LATEST_RUN"

# Standard OpenLane paths for the needed files (Verify these match your OpenLane version)
SYNTH_REPORT="$LATEST_RUN/reports/synthesis/2-syn_sta.max.rpt"
YOSYS_MAP=$(ls $LATEST_RUN/results/synthesis/*.json | head -1)
SRC_DIR="designs/$DESIGN/src"

echo "========================================"
echo " Running Parser..."
echo "========================================"

# 3. Run the Parser with EXACT arguments matching the Python script
python3 $PARSER_SCRIPT \
    --sta "$SYNTH_REPORT" \
    --netlist "$YOSYS_MAP" \
    --src_dir "$SRC_DIR" \
    --out_json "$PARSER_JSON_OUT" \
    --out_snippets "$RTL_FILES_OUT"

# 4. Display Output and Confirm
echo "========================================"
echo " 📄 PARSER JSON OUTPUT ($PARSER_JSON_OUT):"
echo "========================================"
cat $PARSER_JSON_OUT
echo ""
echo "========================================"
echo " 📄 RTL SNIPPETS EXTRACTED:"
echo "========================================"
cat $RTL_FILES_OUT
echo ""
echo "========================================"

read -p "Proceed with sending this JSON and the required RTL files to the LLM? (y/n): " confirm
if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
    echo "Optimization aborted by user."
    exit 1
fi

echo "User confirmed! (The script stops here for now)"
