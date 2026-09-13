#!/bin/bash

echo "[+] Booting OpenLane container and starting Formal Verification..."

# Define the sequence of commands to run INSIDE the Docker container
CONTAINER_CMDS=$(cat << 'EOF'
# 1. Silently download and extract OSS CAD Suite to /tmp
echo "[1/3] Installing OSS CAD Suite..."
cd /tmp
curl -s -L -O https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2023-10-18/oss-cad-suite-linux-x64-20231018.tgz
tar -xzf oss-cad-suite-linux-x64-20231018.tgz
export PATH="/tmp/oss-cad-suite/bin:$PATH"

# 2. Navigate to the verification directory
echo "[2/3] Moving to /openlane/Formal_Verification..."
cd /openlane/Formal_Verification

# 3. Run the formal proof
echo "[3/3] Running SymbiYosys..."
sby -f fec.sby

# 4. Check the result and exit appropriately
if [ $? -eq 0 ]; then
    echo -e "\n========================================="
    echo "[PASS] Logic Equivalent! 12-Cycle Pipeline Verified."
    echo "========================================="
    exit 0
else
    echo -e "\n========================================="
    echo "[FAIL] Formal Verification Failed. Check constraints."
    echo "========================================="
    exit 1
fi
EOF
)

# Pipe the commands directly into the raw Docker command (with -i instead of -ti)
docker run --rm -v /home/rageshcb/OpenLane:/openlane -v /home/rageshcb/OpenLane/designs:/openlane/install -v /home/rageshcb:/home/rageshcb -v /home/rageshcb/.ciel:/home/rageshcb/.ciel -e PDK_ROOT=/home/rageshcb/.ciel -e PDK=sky130A --user 1000:1000 -e DISPLAY=:0 -v /tmp/.X11-unix:/tmp/.X11-unix --network host --security-opt seccomp=unconfined -i ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69-amd64 bash <<< "$CONTAINER_CMDS"
