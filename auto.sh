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
PYTHON_SCRIPT="RTL_Optmize/modify_rtl.py" # Update this to your Python script name
RTL_FILE="RTL_Optmize/axi_lite_slave.v"
PROMPT_FILE="RTL_Optmize/prompt.txt"
JSON_FILE="RTL_Optmize/config.json"
MAX_ITERATIONS="3"

# --- 1. Usage Validation ---
if [[ -z "$RTL_FILE" || -z "$PROMPT_FILE" ]]; then
    echo -e "${RED}[ERROR] Missing required arguments.${NC}"
    echo -e "${YELLOW}Usage:${NC} $0 <path_to_rtl.v> <path_to_prompt.txt> [max_iterations]"
    echo -e "${YELLOW}Example:${NC} $0 axi_lite_slave.v prompt.txt 5"
    exit 1
fi

# --- 2. File Verification ---
if [[ ! -f "$RTL_FILE" ]]; then
    echo -e "${RED}[ERROR] Target RTL file not found: '${RTL_FILE}'${NC}"
    exit 1
fi

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

# --- 3. Dependency Verification ---
echo -e "${BLUE}[*] Validating system dependencies...${NC}"

if ! command -v python &> /dev/null; then
    echo -e "${RED}[ERROR] 'python3' command could not be found. Please install Python.${NC}"
    exit 1
fi

if ! command -v iverilog &> /dev/null; then
    echo -e "${RED}[ERROR] 'iverilog' command could not be found. Please install Icarus Verilog.${NC}"
    exit 1
fi

# --- 4. Environment & API Key Check ---
# Check if a .env file exists and load it automatically
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

# --- 5. Execution Phase ---
echo -e "${GREEN}[*] Starting RTL Optimization Flow...${NC}"
echo -e "  - RTL Source      : ${RTL_FILE}"
echo -e "  - Modification Prompt : ${PROMPT_FILE}"
echo -e "  - JSON File : ${JSON_FILE}"
echo -e "  - Max Iterations   : ${MAX_ITERATIONS}"
echo -e "--------------------------------------------------------"

python "$PYTHON_SCRIPT" "$RTL_FILE" "$PROMPT_FILE" "$JSON_FILE" --max-iterations "$MAX_ITERATIONS"
EXIT_CODE=$?

# --- 6. Status Output ---
echo -e "--------------------------------------------------------"
if [[ $EXIT_CODE -eq 0 ]]; then
    echo -e "${GREEN}[SUCCESS] RTL modification and verification flow completed successfully.${NC}"
else
    echo -e "${RED}[FAILURE] RTL modification flow failed or max retries reached.${NC}"
    exit $EXIT_CODE
fi