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

# --- Define Target RTL Files Array ---
RTL_FILES=(
    "RTL_Optimize/DUT/xbar_3by3_bencmark_top.v"
    "RTL_Optimize/DUT/rptr_empty.v"
    "RTL_Optimize/DUT/top_fifo.v"
)

# --- 1. Array & File Verification ---
if [[ ${#RTL_FILES[@]} -eq 0 ]]; then
    echo -e "${RED}[ERROR] RTL_FILES array is empty. Define at least one RTL source file.${NC}"
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

PYTHON_CMD=$(command -v python)

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