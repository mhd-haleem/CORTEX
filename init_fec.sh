#!/usr/bin/env bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

DESIGN_DIR=${1:-"my_design"}
OL_CONFIG="OpenLane/designs/$DESIGN_DIR/config.json"
SRC_DIR="OpenLane/Formal_Verification/src"
BASE_JSON="OpenLane/Formal_Verification/config/base_config.json"

echo -e "${BLUE}[*] Extracting base formal specification...${NC}"

if [ ! -f "$OL_CONFIG" ]; then
    echo "Error: OpenLane config not found at $OL_CONFIG"
    exit 1
fi

python3 OpenLane/Formal_Verification/scripts/extract_base.py \
    --ol_config "$OL_CONFIG" \
    --src_dir "$SRC_DIR" \
    --output "$BASE_JSON"

echo -e "${GREEN}[*] Initialization complete! The base specification is ready at $BASE_JSON${NC}"
