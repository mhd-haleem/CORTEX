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
PYTHON_SCRIPT="RTL_Optimize/modify_rtl.py"
PROMPT_FILE="RTL_Optimize/prompt.txt"
JSON_FILE="RTL_Optimize/llm_payload.json"
MAX_ITERATIONS="3"

# Make sure this matches your actual design folder name
DESIGN="my_design"
PARSER_SCRIPT="rtl_parser.py"

# --- Target RTL Files Array (Dynamically populated later from parser output) ---
RTL_FILES=()

# Dynamically set paths so anyone can run this
OPENLANE_DIR="$(pwd)/OpenLane"
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
    
# ========================================
# 4. Build Dynamic RTL_FILES Array & Sync to DUT
# ========================================
mkdir -p RTL_Optimize/DUT

RTL_FILES=()
for file in llm_context/*.v llm_context/*.sv 2>/dev/null; do
    if [ -f "$file" ]; then
        basename_file=$(basename "$file")
        
        # Copy file into RTL_Optimize/DUT/ folder for the workflow script
        cp "$file" "RTL_Optimize/DUT/$basename_file"
        
        # Format path into RTL_FILES array
        RTL_FILES+=("RTL_Optimize/DUT/$basename_file")
    fi
done

echo ""
echo "========================================"
echo " Dynamic array 'RTL_FILES' configured!"
echo " Target bottleneck files (${#RTL_FILES[@]} total):"
for f in "${RTL_FILES[@]}"; do
    echo "  -> $f"
done
echo "========================================"
echo ""

read -p "Proceed with sending this JSON and the required RTL files to the LLM? (y/n): " confirm
if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
    echo "Optimization aborted by user."
    exit 1
fi

echo -e "${GREEN}[*] User confirmed! Copying JSON file to RTL_Optimize directory...${NC}"

# Create destination folder if it doesn't exist
mkdir -p RTL_Optimize

# Locate generated JSON in llm_context and copy to RTL_Optimize/llm_payload.json
GENERATED_JSON=$(ls llm_context/*.json 2>/dev/null | head -1)

if [[ -n "$GENERATED_JSON" && -f "$GENERATED_JSON" ]]; then
    cp "$GENERATED_JSON" "$JSON_FILE"
    echo -e "${GREEN}[+] Successfully copied '${GENERATED_JSON}' -> '${JSON_FILE}'${NC}"
else
    echo -e "${RED}[ERROR] No JSON file found in 'llm_context/' to copy!${NC}"
    exit 1
fi

# --- 1. Array & File Verification ---
if [[ ${#RTL_FILES[@]} -eq 0 ]]; then
    echo -e "${RED}[ERROR] RTL_FILES array is empty. No bottleneck files found in 'llm_context/'.${NC}"
    exit 1
fi

# Validate existence of every file in the array
for rtl_file in "${RTL_FILES[@]}"; do
    if [[ ! -f "$rtl_file" ]]; then
        echo -e "${RED}[ERROR] Target RTL file not found: '${rtl_file}'${NC}"
        exit 1
    fi
done

if [[ ! -f "$JSON_FILE" ]]; then
    echo -e "${RED}[ERROR] Target JSON file not found: '${JSON_FILE}'${NC}"
    exit 1
fi

if [[ ! -f "$PROMPT_FILE" ]]; then
    echo -e "${RED}[ERROR] Modification prompt file not found: '${PROMPT_FILE}'${NC}"
    exit 1
fi

if [[ ! -f "$PYTHON_SCRIPT" ]]; then
    echo -e "${RED}[ERROR] Python workflow script '${PYTHON_SCRIPT}' not found.${NC}"
    exit 1
fi

# --- 2. Dependency Verification ---
echo -e "${BLUE}[*] Validating system dependencies...${NC}"

if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
    echo -e "${RED}[ERROR] Python interpreter not found. Please install Python.${NC}"
    exit 1
fi

PYTHON_CMD=$(command -v python3 || command -v python)

if ! command -v iverilog &> /dev/null; then
    echo -e "${RED}[ERROR] 'iverilog' command could not be found. Please install Icarus Verilog.${NC}"
    exit 1
fi

# --- 3. Environment & API Key Check ---
if [[ -f ".env" ]]; then
    echo -e "${BLUE}[*] Loading environment variables from .env file...${NC}"
    export $(grep -v '^#' .env | xargs)
fi

if [[ -z "${GEMINI_API_KEY:-}" ]]; then
    echo -e "${RED}[ERROR] GEMINI_API_KEY is not set.${NC}"
    echo -e "${YELLOW}Set it in your terminal or inside a .env file:${NC}"
    echo -e "  export GEMINI_API_KEY='your_actual_api_key'"
    exit 1
fi

# --- 4. Execution Phase ---
echo -e "${GREEN}[*] Starting RTL Optimization Flow...${NC}"
echo -e "  - RTL Sources         : ${RTL_FILES[*]}"
echo -e "  - Modification Prompt : ${PROMPT_FILE}"
echo -e "  - JSON File           : ${JSON_FILE}"
echo -e "  - Max Iterations      : ${MAX_ITERATIONS}"
echo -e "--------------------------------------------------------"

"$PYTHON_CMD" "$PYTHON_SCRIPT" "${RTL_FILES[@]}" \
    --prompt_file "$PROMPT_FILE" \
    --json_file "$JSON_FILE" \
    --max-iterations "$MAX_ITERATIONS"

EXIT_CODE=$?

# --- 5. Status Output ---
echo -e "--------------------------------------------------------"
if [[ $EXIT_CODE -eq 0 ]]; then
    echo -e "${GREEN}[SUCCESS] RTL modification and verification flow completed successfully.${NC}"
else
    echo -e "${RED}[FAILURE] RTL modification flow failed or max retries reached.${NC}"
    exit $EXIT_CODE
fi