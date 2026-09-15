# CORTEX: Closed-loop Optimizer for RTL Timing and EXploration

![CORTEX Banner](https://img.shields.io/badge/Status-Active-brightgreen) ![Python 3](https://img.shields.io/badge/Python-3.x-blue) ![Bash](https://img.shields.io/badge/Shell-Bash-darkgray) ![License](https://img.shields.io/badge/License-MIT-green)

**CORTEX** is an automated, AI-driven Hardware Design pipeline that integrates Generative AI (Google Gemini) with standard Open-Source EDA tools (OpenLane, Yosys, SymbiYosys) to automatically identify, optimize, and formally verify timing bottlenecks in RTL designs.

By creating a closed-loop system, CORTEX not only rewrites RTL to fix negative slack (e.g., through automated pipelining or retiming) but mathematically proves the functional equivalence of the LLM-generated code against the golden reference before committing it to silicon.

---

## Key Features

*   **Automated OpenLane Profiling:** Runs initial synthesis to extract setup/hold timing violations and power metrics.
*   **Context-Aware GenAI Optimization:** Parses synthesis logs and netlists to feed targeted bottlenecks to the Gemini API (`modify_rtl.py`).
*   **Closed-Loop Formal Verification:** Automatically generates Sequential Equivalence Checking (SEC) wrappers and runs Bounded Model Checking (BMC) via SymbiYosys.
*   **Self-Healing AI Loop:** If Formal Verification fails, the tool automatically feeds the SMT solver error logs back to the LLM to iteratively fix syntax or logical assertion errors (up to 2 iterations).
*   **PPA Comparison:** Generates a side-by-side Power, Performance, and Area (PPA) report comparing the baseline RTL against the optimized RTL.

---

## Prerequisites & Dependencies

To run CORTEX, ensure your Linux environment has the following installed:

1.  **Docker:** Required for running the OpenLane container (`ghcr.io/the-openroad-project/openlane`).
2.  **Python 3.x:** Required for the LLM interaction and parsing scripts.
3.  **Icarus Verilog (`iverilog`):** Required for local syntax checking.
4.  **OSS CAD Suite / SymbiYosys:** Required for the Formal Equivalence Checking framework.
5.  **Sky130 PDK:** Open-source Process Design Kit. By default, CORTEX looks in `~/.ciel` or the path defined by the `$PDK_ROOT` environment variable.

---

## Installation & Setup


### 1. Repository Setup & Virtual Environment

Clone the repository and set up an isolated Python virtual environment:

```bash
# Clone the repository
git clone [https://github.com/yourusername/CORTEX.git](https://github.com/yourusername/CORTEX.git)
cd CORTEX

# Create and activate a Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install required Python dependencies
pip install -r requirements.txt
```
### 2. Configure Gemini API Key
Export your Google Gemini API key as an environment variable so modify_rtl.py can authenticate:

```bash

export GEMINI_API_KEY='your_gemini_api_key_here'
```
### 3. Place Target Design Source Files
Copy your unoptimized Verilog/SystemVerilog source files into the default OpenLane design directory:

```bash
cp /path/to/your/unoptimized_rtl/*.v CORTEX/OpenLane/designs/my_design/src/
```
### 4. Run the CORTEX Pipeline
Execute the main automation script to initiate profiling, GenAI timing optimization, syntax verification, and formal equivalence checking:

```bash

chmod +x auto_1.sh
./auto_1.sh
```
