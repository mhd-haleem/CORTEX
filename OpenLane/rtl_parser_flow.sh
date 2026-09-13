#!/bin/bash

# ==========================================
# CONFIGURATION
# ==========================================
# Make sure this matches your actual design folder name
DESIGN="my_design" 

PARSER_SCRIPT="rtl_parser.py"


# Dynamically set paths so anyone can run this
OPENLANE_DIR=$(pwd)
# Use the user's PDK_ROOT if exported, otherwise default to ~/.ciel
USER_PDK_ROOT=${PDK_ROOT:-$HOME/.ciel}
USER_ID=$(id -u)
GROUP_ID=$(id -g)

echo "========================================"
echo " Setting Up Golden RTL Backup"
echo "========================================"

# Create a backup of the original RTL files before any LLM modification
BACKUP_DIR="$OPENLANE_DIR/RTL_Backup"

if [ ! -d "$BACKUP_DIR" ]; then
    echo "Creating backup of initial RTL files at $BACKUP_DIR..."
    mkdir -p "$BACKUP_DIR"
    cp -r "$OPENLANE_DIR/designs/$DESIGN/src" "$BACKUP_DIR/"
    echo "[SUCCESS] Golden RTL safely backed up."
else
    echo "[INFO] RTL backup already exists at $BACKUP_DIR."
    echo "       (Preserving original golden files.)"
fi

echo "========================================"
echo " Starting OpenLane Synthesis"
echo "========================================"

# Check if PDK directory actually exists to help new users
if [ ! -d "$USER_PDK_ROOT" ]; then
    echo "[ERROR] PDK_ROOT not found at $USER_PDK_ROOT."
    echo "If your PDK is located elsewhere, run: export PDK_ROOT=/path/to/your/pdk"
    exit 1
fi

# 1. Run OpenLane Synthesis Non-Interactively
echo "Executing OpenLane non-interactively..."
echo "Running in: $OPENLANE_DIR"
echo "Using PDK: $USER_PDK_ROOT"

docker run --rm \
    -v "$OPENLANE_DIR:/openlane" \
    -v "$OPENLANE_DIR/designs:/openlane/install" \
    -v "$HOME:$HOME" \
    -v "$USER_PDK_ROOT:$USER_PDK_ROOT" \
    -e PDK_ROOT="$USER_PDK_ROOT" \
    -e PDK=sky130A \
    --user $USER_ID:$GROUP_ID \
    --network host \
    ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69-amd64 \
    bash -c "./flow.tcl -design $DESIGN"

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

# Standard OpenLane paths for the needed files
SYNTH_REPORT="$LATEST_RUN/reports/synthesis/2-syn_sta.max.rpt"
YOSYS_MAP=$(ls "$LATEST_RUN/results/synthesis/"*.json | head -1)
SRC_DIR="$OPENLANE_DIR/designs/$DESIGN/src"

echo "========================================"
echo " Running Parser..."
echo "========================================"

# 3. Run the Parser to dump everything into the 'llm_context' folder
python3 "$PARSER_SCRIPT" \
    --sta "$SYNTH_REPORT" \
    --netlist "$YOSYS_MAP" \
    --src_dir "$SRC_DIR" \
    --out_dir "llm_context"
    


read -p "Proceed with sending this JSON and the required RTL files to the LLM? (y/n): " confirm
if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
    echo "Optimization aborted by user."
    exit 1
fi

echo "User confirmed! (The script stops here for now)"
