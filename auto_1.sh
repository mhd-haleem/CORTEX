#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -eo pipefail

# Terminal colors for log status messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
# --- Pipeline Stopwatch ---
START_TIME=$SECONDS

# --- Banner Function ---
show_banner() {
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
  ██████╗  ██████╗ ██████╗ ████████╗███████╗██╗  ██╗
 ██╔════╝ ██╔═══██╗██╔══██╗╚══██╔══╝██╔════╝╚██╗██╔╝
 ██║      ██║   ██║██████╔╝   ██║   █████╗   ╚███╔╝ 
 ██║      ██║   ██║██╔══██╗   ██║   ██╔══╝   ██╔██╗ 
 ╚██████╗ ╚██████╔╝██║  ██║   ██║   ███████╗██╔╝ ██╗
  ╚═════╝  ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
EOF
    echo -e "${BLUE}${BOLD} Closed-loop Optimizer for RTL Timing and EXploration${NC}"
    echo -e "${CYAN}================================================================${NC}\n"
}


show_banner

# --- Configuration & Defaults ---
CORTEX_ROOT="$(pwd)"
OPENLANE_DIR="$CORTEX_ROOT/OpenLane"
FV_DIR="$OPENLANE_DIR/Formal_Verification"

PYTHON_SCRIPT="RTL_Optimize/modify_rtl.py"
PROMPT_FILE="RTL_Optimize/prompt.txt"
JSON_FILE="RTL_Optimize/llm_payload.json"
MAX_ITERATIONS="3"

# Make sure this matches your actual design folder name
DESIGN="my_design"
PARSER_SCRIPT="$OPENLANE_DIR/rtl_parser.py"

# --- Target RTL Files Array (Dynamically populated later from parser output) ---
RTL_FILES=()

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
    echo -e "${RED}[ERROR] PDK_ROOT not found at $USER_PDK_ROOT.${NC}"
    echo "If your PDK is located elsewhere, run: export PDK_ROOT=/path/to/your/pdk"
    exit 1
fi

# --- 1. Run OpenLane Synthesis Non-Interactively ---
read -p "Do you want to run Initial OpenLane Synthesis now? (Type 'n' to use existing logs) [Y/n]: " run_synth

if [[ -z "$run_synth" || "$run_synth" == [yY]* ]]; then
    echo "Executing OpenLane non-interactively..."
    echo "Running in: $OPENLANE_DIR"
    echo "Using PDK: $USER_PDK_ROOT"

    # Temporarily disable 'set -e' so the script doesn't die when OpenLane fails
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

    OPENLANE_EXIT=$?
    set -e

    if [ $OPENLANE_EXIT -eq 0 ]; then
        echo -e "${GREEN}[SUCCESS] Flow completed successfully. No optimization required.${NC}"
        exit 0
    fi

else
    echo "[INFO] Skipping initial synthesis. Using existing run logs..."
fi

echo "========================================"
echo " Flow failed. Finding latest run logs..."
echo "========================================"

# 2. Safely find the LATEST run directory to avoid Bash wildcard errors
LATEST_RUN=$(ls -td "$OPENLANE_DIR/designs/$DESIGN/runs/RUN_"* 2>/dev/null | head -1 || true)

if [ -z "$LATEST_RUN" ]; then
    echo -e "${RED}[ERROR] Could not find any OpenLane run directories for $DESIGN.${NC}"
    exit 1
fi

echo "Using latest run directory: $LATEST_RUN"

# Standard OpenLane paths for the needed files
SYNTH_REPORT="$LATEST_RUN/reports/synthesis/2-syn_sta.max.rpt"
YOSYS_MAP=$(ls "$LATEST_RUN/results/synthesis/"*.json 2>/dev/null | head -1 || true)
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

# Enable nullglob so unmatched wildcards safely return empty
shopt -s nullglob 
for file in llm_context/*.v llm_context/*.sv; do
    if [ -f "$file" ]; then
        basename_file=$(basename "$file")
        
        # Copy file into RTL_Optimize/DUT/ folder for the workflow script
        cp "$file" "RTL_Optimize/DUT/$basename_file"
        
        # Format path into RTL_FILES array
        RTL_FILES+=("RTL_Optimize/DUT/$basename_file")
    fi
done
# Disable nullglob to return the script to normal behavior
shopt -u nullglob 

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
GENERATED_JSON=$(ls llm_context/*.json 2>/dev/null | head -1 || true)

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

# --- 4. Execution & Formal Verification Feedback Loop ---
MAX_FV_ITERATIONS=2
CURRENT_PROMPT="RTL_Optimize/current_prompt.txt"
LOG_FILE="$CORTEX_ROOT/OpenLane/Formal_Verification/fec_bmc/logfile.txt"

# Start with the original prompt
cp "$PROMPT_FILE" "$CURRENT_PROMPT"

echo -e "${GREEN}[*] Starting Automated RTL & Verification Loop...${NC}"

FV_PASSED=false

for (( iter=1; iter<=MAX_FV_ITERATIONS; iter++ )); do

    echo -e "--------------------------------------------------------"
    echo -e "${BLUE}[*] Iteration ${iter}/${MAX_FV_ITERATIONS}: Generating RTL...${NC}"

    "$PYTHON_CMD" "$PYTHON_SCRIPT" "${RTL_FILES[@]}" \
        --prompt_file "$CURRENT_PROMPT" \
        --json_file "$JSON_FILE" \
        --max-iterations "$MAX_ITERATIONS"

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[ERROR] Python script failed during RTL generation.${NC}"
        rm -f "$CURRENT_PROMPT"
        exit 1
    fi

    # ---------------------------------------------------------
    # NEW: SEC Wrapper Generation & Environment Initialization
    # ---------------------------------------------------------
    echo -e "${BLUE}[*] Generating Formal Verification Wrapper...${NC}"
    
    # Change directory so the generator reads/writes the relative paths correctly
    cd "$FV_DIR"
    
    "$PYTHON_CMD" scripts/generate_wrapper.py
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[ERROR] generate_wrapper.py failed.${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}[*] Initializing Formal Equivalence Checking (init_fec.sh)...${NC}"
    
    # Return to CORTEX root to execute the init script
    cd "$CORTEX_ROOT"
    
    bash init_fec.sh
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[ERROR] init_fec.sh failed.${NC}"
        exit 1
    fi
    # ---------------------------------------------------------

    echo -e "${BLUE}[*] Triggering Formal Verification...${NC}"
    bash "$OPENLANE_DIR/run_fv.sh" 15
    FV_EXIT_CODE=$?

    if [[ $FV_EXIT_CODE -eq 0 ]]; then

        echo -e "${GREEN}[SUCCESS] Formal Verification Passed!${NC}"
        echo -e "${GREEN}[*] Verified RTL is ready for final OpenLane synthesis.${NC}"

        FV_PASSED=true
        rm -f "$CURRENT_PROMPT"
        break

    else

        echo -e "${RED}[WARNING] Formal Verification Failed on Iteration ${iter}.${NC}"

        if [[ $iter -lt $MAX_FV_ITERATIONS ]]; then

            echo -e "${YELLOW}[*] Feeding logfile back to the LLM for correction...${NC}"

            echo -e "The previous RTL generated failed Formal Verification. Here is the SymbiYosys log file indicating the syntax or assertion errors:\n" > "$CURRENT_PROMPT"
            echo -e "========== SBY LOG ==========" >> "$CURRENT_PROMPT"
            cat "$LOG_FILE" >> "$CURRENT_PROMPT"
            echo -e "\n=============================\nPlease rewrite the Verilog to fix the errors shown in the log above." >> "$CURRENT_PROMPT"

        fi
    fi

done


# ========================================
# Check FV result
# ========================================

if [[ "$FV_PASSED" != true ]]; then
    echo -e "${RED}[FAILURE] Max verification iterations reached. The FEC is consistently failing.${NC}"
    echo -e "${YELLOW}Please check the DUT folder and the FV logfile manually.${NC}"
    rm -f "$CURRENT_PROMPT"
    exit 1
fi


# ========================================
# Phase 5: Final OpenLane Synthesis
# ========================================

echo "========================================"
echo " Phase 5: Final OpenLane Synthesis"
echo "========================================"

echo -e "${BLUE}[*] Injecting formally verified RTL into OpenLane...${NC}"

for f in "${RTL_FILES[@]}"; do
    echo "  -> Copying $f"
    cp "$CORTEX_ROOT/$f" "$OPENLANE_DIR/designs/$DESIGN/src/"
done

echo -e "${GREEN}[SUCCESS] Verified RTL copied into OpenLane source directory.${NC}"

cd "$OPENLANE_DIR"

echo -e "${BLUE}[*] Running OpenLane synthesis on formally verified RTL...${NC}"

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

FINAL_OPENLANE_EXIT=$?

set -e

if [[ $FINAL_OPENLANE_EXIT -eq 0 ]]; then
    echo -e "${GREEN}[SUCCESS] Final OpenLane synthesis completed successfully!${NC}"
else
    echo -e "${RED}[FAILURE] Final OpenLane synthesis failed.${NC}"
    exit $FINAL_OPENLANE_EXIT
fi

echo "========================================"
echo " Phase 6: PPA Optimization Results"
echo "========================================"

# Grab the latest 2 runs (index 0 is the optimized run, index 1 is the baseline run)
# 'ls -td' sorts by time, newest first.
RUNS=($(ls -td "$OPENLANE_DIR/designs/$DESIGN/runs/RUN_"* 2>/dev/null | head -2))

if [ ${#RUNS[@]} -ge 2 ]; then
    OPTIMIZED_RUN="${RUNS[0]}"
    BASELINE_RUN="${RUNS[1]}"
    
    # Call our new python parser
    "$PYTHON_CMD" "$CORTEX_ROOT/RTL_Optimize/ppa_compare.py" \
        --baseline "$BASELINE_RUN" \
        --optimized "$OPTIMIZED_RUN"
else
    echo -e "${YELLOW}[WARNING] Need at least two successful OpenLane runs to generate a PPA comparison table.${NC}"
fi
