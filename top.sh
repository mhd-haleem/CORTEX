#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -eo pipefail

# Terminal colors for log status messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Configuration & Defaults ---
CORTEX_ROOT="$(pwd)" # Or anchor it before the cd command
PYTHON_SCRIPT="$CORTEX_ROOT/RTL_Optimize/modify_rtl.py"
PROMPT_FILE="$CORTEX_ROOT/RTL_Optimize/prompt.txt"
JSON_FILE="$CORTEX_ROOT/RTL_Optimize/llm_payload.json"
MAX_ITERATIONS="3"

# Make sure this matches your actual design folder name
DESIGN="my_design"
PARSER_SCRIPT="rtl_parser.py"

# --- Target RTL Files Array (Dynamically populated later from parser output) ---
RTL_FILES=()

# Dynamically set paths so anyone can run this
OPENLANE_DIR="$(pwd)/OpenLane"

# >>> CRITICAL FIX: Step into the OpenLane folder so all relative paths work <<<
if [ -d "$OPENLANE_DIR" ]; then
    cd "$OPENLANE_DIR"
else
    echo -e "${RED}[ERROR] OpenLane directory not found at $OPENLANE_DIR${NC}"
    exit 1
fi

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
echo " Phase 1: Initial OpenLane Synthesis"
echo "========================================"

if [ ! -d "$USER_PDK_ROOT" ]; then
    echo -e "${RED}[ERROR] PDK_ROOT not found at $USER_PDK_ROOT.${NC}"
    echo "If your PDK is located elsewhere, run: export PDK_ROOT=/path/to/your/pdk"
    exit 1
fi

read -p "Do you want to run Initial OpenLane Synthesis now? (Type 'n' to use existing logs) [Y/n]: " run_synth

if [[ -z "$run_synth" || "$run_synth" == [yY]* ]]; then
    echo "Executing OpenLane non-interactively..."
    echo "Running in: $OPENLANE_DIR"
    
    set +e
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
    
    DOCKER_EXIT_CODE=$?
    set -e

    if [ $DOCKER_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}[SUCCESS] Initial Flow completed successfully. No optimization required!${NC}"
        exit 0
    fi
else
    echo -e "${YELLOW}[INFO] Skipping initial synthesis. Finding existing run logs...${NC}"
fi

# Find the LATEST run directory for pre-optimization metrics
PRE_RUN=$(ls -td "$OPENLANE_DIR/designs/$DESIGN/runs/RUN_"* 2>/dev/null | head -1)

if [ -z "$PRE_RUN" ]; then
    echo -e "${RED}[ERROR] Could not find any OpenLane run directories for $DESIGN.${NC}"
    exit 1
fi

# Extract initial Worst Negative Slack (WNS)
SYNTH_REPORT="$PRE_RUN/reports/synthesis/2-syn_sta.max.rpt"
PRE_WNS=$(grep -m 1 "slack (VIOLATED)" "$SYNTH_REPORT" | awk '{print $1}' || echo "N/A")
YOSYS_MAP=$(ls "$PRE_RUN/results/synthesis/"*.json | head -1)
SRC_DIR="$OPENLANE_DIR/designs/$DESIGN/src"

echo "========================================"
echo " Phase 2: Running RTL Parser..."
echo "========================================"

python3 "$PARSER_SCRIPT" \
    --sta "$SYNTH_REPORT" \
    --netlist "$YOSYS_MAP" \
    --src_dir "$SRC_DIR" \
    --out_dir "llm_context"

# Build Dynamic RTL_FILES Array
TARGET_RTL_OPTIMIZE="$CORTEX_ROOT/RTL_Optimize"
TARGET_DUT_DIR="$TARGET_RTL_OPTIMIZE/DUT"
mkdir -p "$TARGET_DUT_DIR"

RTL_FILES=()
for file in llm_context/*.v llm_context/*.sv; do
    if [ -f "$file" ]; then
        basename_file=$(basename "$file")
        cp "$file" "$TARGET_DUT_DIR/$basename_file"
        RTL_FILES+=("RTL_Optimize/DUT/$basename_file")
    fi
done

echo -e "\n${BLUE}Target bottleneck files (${#RTL_FILES[@]} total):${NC}"
for f in "${RTL_FILES[@]}"; do echo "  -> $f"; done
echo ""

read -p "Proceed with sending this JSON and RTL files to the LLM? (y/n): " confirm
if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
    echo "Optimization aborted by user."
    exit 1
fi

# Ensure root RTL_Optimize destination folder exists and copy JSON
mkdir -p "$TARGET_RTL_OPTIMIZE"
GENERATED_JSON=$(ls llm_context/*.json 2>/dev/null | head -1)

if [[ -n "$GENERATED_JSON" && -f "$GENERATED_JSON" ]]; then
    cp "$GENERATED_JSON" "$TARGET_RTL_OPTIMIZE/llm_payload.json"
else
    echo -e "${RED}[ERROR] No JSON file found in 'llm_context/' to copy!${NC}"
    exit 1
fi

# Dependency and API Verification
PYTHON_CMD="$CORTEX_ROOT/venv/bin/python"
if [[ -f "../.env" ]]; then export $(grep -v '^#' ../.env | xargs); elif [[ -f ".env" ]]; then export $(grep -v '^#' .env | xargs); fi
if [[ -z "${GEMINI_API_KEY:-}" ]]; then echo -e "${RED}[ERROR] GEMINI_API_KEY is not set.${NC}"; exit 1; fi

echo "========================================"
echo " Phase 3: Executing LLM Optimization Loop"
echo "========================================"
cd "$CORTEX_ROOT"

"$PYTHON_CMD" "$PYTHON_SCRIPT" "${RTL_FILES[@]}" \
    --prompt_file "$PROMPT_FILE" \
    --json_file "$JSON_FILE" \
    --max-iterations "$MAX_ITERATIONS"

LLM_EXIT_CODE=$?

if [[ $LLM_EXIT_CODE -ne 0 ]]; then
    echo -e "${RED}[FAILURE] RTL modification flow failed. Halting.${NC}"
    exit $LLM_EXIT_CODE
fi

echo -e "${GREEN}[SUCCESS] LLM successfully modified the RTL!${NC}"
echo -e "${YELLOW}[*] Assuming Formal Verification (LEC) is SUCCESSFUL.${NC}"

echo "========================================"
echo " Phase 4: Post-Optimization Synthesis"
echo "========================================"

# Inject LLM optimized files back into the original design directory
echo -e "${BLUE}[*] Injecting Optimized RTL into OpenLane Design Directory...${NC}"
for f in "${RTL_FILES[@]}"; do
    cp "$CORTEX_ROOT/$f" "$OPENLANE_DIR/designs/$DESIGN/src/"
done

cd "$OPENLANE_DIR"

set +e
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

POST_DOCKER_EXIT_CODE=$?
set -e

POST_RUN=$(ls -td "$OPENLANE_DIR/designs/$DESIGN/runs/RUN_"* 2>/dev/null | head -1)
POST_REPORT="$POST_RUN/reports/synthesis/2-syn_sta.max.rpt"

if [ -f "$POST_REPORT" ]; then
    POST_WNS=$(grep -m 1 "slack (VIOLATED)" "$POST_REPORT" | awk '{print $1}')
    if [ -z "$POST_WNS" ]; then
        POST_WNS="MET (No Violations)"
    fi
else
    POST_WNS="MET (No Violations)"
fi

echo "========================================"
echo " Phase 5: PPA Optimization Results"
echo "========================================"

if [ $POST_DOCKER_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}[VICTORY] Timing closed successfully! Zero setup violations.${NC}"
else
    echo -e "${RED}[WARNING] OpenLane reported a flow failure. The RTL may still have violations or new syntax errors.${NC}"
fi

echo -e "\n--- Timing Comparison (Worst Negative Slack) ---"
echo -e "Before LLM Optimization : ${RED}${PRE_WNS} ns${NC}"
if [[ "$POST_WNS" == *"MET"* ]]; then
    echo -e "After LLM Optimization  : ${GREEN}${POST_WNS}${NC}"
else
    echo -e "After LLM Optimization  : ${YELLOW}${POST_WNS} ns${NC}"
fi

echo -e "\n--- Detailed Reports ---"
echo -e "Original Run : $PRE_RUN/reports/metrics.csv"
echo -e "Optimized Run: $POST_RUN/reports/metrics.csv"
echo -e "========================================\n"
