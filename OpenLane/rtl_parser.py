import os
import re
import json
import argparse


def parse_opensta_violations(sta_report_path):
    with open(sta_report_path, 'r') as f:
        content = f.read()
    
    violated_paths = []
    blocks = re.split(r'(?=Startpoint:\s+)', content)
    
    for block in blocks:
        if "slack (VIOLATED)" not in block:
            continue
            
        path_data = {
            "slack": None,
            "path_type": None,
            "startpoint": None,
            "endpoint": None,
            "path_gates": []
        }
        
        sp_match = re.search(r'Startpoint:\s+([^\s\(]+)', block)
        ep_match = re.search(r'Endpoint:\s+([^\s\(]+)', block)
        pt_match = re.search(r'Path Type:\s+(\w+)', block)
        
        # Look for the float value before the slack text
        slack_match = re.search(r'([\-\d\.]+)\s+slack\s+\(VIOLATED\)', block)
        
        if sp_match:
            path_data["startpoint"] = sp_match.group(1).replace("\\", "")
        if ep_match:
            path_data["endpoint"] = ep_match.group(1).replace("\\", "")
        if pt_match:
            path_data["path_type"] = pt_match.group(1)
        if slack_match:
            path_data["slack"] = float(slack_match.group(1))
        
        # Robust regex that ignores the preceding float columns entirely
        stage_pattern = re.compile(
            r'([v\^])?\s+([a-zA-Z0-9_/\.\[\]\\]+)\s*\(([\w_]+)\)'
        )
        
        for stage in stage_pattern.finditer(block):
            edge, pin_full, cell_type = stage.groups()
            
            # Ignore clock network and ideal descriptions
            if (
                "edge" in cell_type.lower()
                or "ideal" in cell_type.lower()
                or "pessimism" in cell_type.lower()
            ):
                continue
                
            # Strip the pin (e.g., /X) to get just the instance name
            gate_name = (
                pin_full.rsplit('/', 1)[0]
                if "/" in pin_full
                else pin_full
            )
            
            if gate_name not in [
                path_data["startpoint"],
                path_data["endpoint"]
            ]:
                if not any(
                    g["gate"] == gate_name
                    for g in path_data["path_gates"]
                ):
                    path_data["path_gates"].append({
                        "gate": gate_name.replace("\\", ""), 
                        "cell_type": cell_type
                    })
                    
        violated_paths.append(path_data)
        
    return violated_paths


def build_rtl_map_from_yosys(json_netlist_path):
    rtl_map = {}

    with open(json_netlist_path, 'r') as f:
        yosys_data = json.load(f)
        
    for mod_name, mod_data in yosys_data.get("modules", {}).items():
        for cell_name, cell_data in mod_data.get("cells", {}).items():
            attributes = cell_data.get("attributes", {})

            if "src" in attributes:
                clean_cell = cell_name.replace("\\", "")
                rtl_map[clean_cell] = attributes["src"]
                
    return rtl_map


def generate_llm_payload(sta_report_path, yosys_json_path):
    violations = parse_opensta_violations(sta_report_path)
    rtl_map = build_rtl_map_from_yosys(yosys_json_path)
    
    llm_payload = []
    
    for v in violations:
        sp_base = v["startpoint"].rsplit('/', 1)[0] if v["startpoint"] else ""
        ep_base = v["endpoint"].rsplit('/', 1)[0] if v["endpoint"] else ""
        
        sp_src = rtl_map.get(sp_base, "Implicit/Unknown")
        ep_src = rtl_map.get(ep_base, "Implicit/Unknown")
        
        compact_logic_path = []
        
        for gate in v["path_gates"]:
            inst = gate["gate"]
            c_type = gate["cell_type"]
            
            # 1. Filter out physical wires and the regex 'slack' bug
            if c_type == "net" or "slack" in inst.lower() or "violated" in c_type.lower():
                continue
                
            # 2. Simplify vendor cell names (e.g., 'sky130_fd_sc_hd__mux4_2' -> 'MUX4')
            generic_cell = c_type.split('__')[-1].split('_')[0].upper() if '__' in c_type else c_type.upper()
            
            # 3. Extract the clean RTL hierarchy
            hierarchy_node = inst.split('_sky130')[0]
            rtl_source = rtl_map.get(inst, "Implicit/Unknown")
            
            # 4. Group the sequential gates under their respective module hierarchies
            if not compact_logic_path or compact_logic_path[-1]["hierarchy_node"] != hierarchy_node:
                compact_logic_path.append({
                    "hierarchy_node": hierarchy_node,
                    "rtl_source": rtl_source,
                    "logic_depth": 1,
                    "gate_chain": [generic_cell]
                })
            else:
                compact_logic_path[-1]["gate_chain"].append(generic_cell)
                compact_logic_path[-1]["logic_depth"] += 1
                # Upgrade source if found
                if compact_logic_path[-1]["rtl_source"] == "Implicit/Unknown" and rtl_source != "Implicit/Unknown":
                    compact_logic_path[-1]["rtl_source"] = rtl_source

        llm_payload.append({
            "violation_type": f"timing_{v['path_type']}",
            "slack": v["slack"],
            "startpoint": {"instance": v["startpoint"], "rtl_source": sp_src},
            "endpoint": {"instance": v["endpoint"], "rtl_source": ep_src},
            "total_combinational_depth": sum(node["logic_depth"] for node in compact_logic_path),
            "critical_logic_path": compact_logic_path
        })
        
    return json.dumps(llm_payload, indent=2)


# ============================================================
# RTL SNIPPET EXTRACTION (WITH PATH RESOLUTION)
# ============================================================

def parse_yosys_src_string(src_string):
    """Parses Yosys hierarchical source traces."""
    if src_string == "Implicit/Unknown" or not src_string:
        return []
        
    traces = src_string.split('|')
    parsed_traces = []
    
    # Matches format: filepath:start_line.col-end_line.col OR filepath:start_line
    pattern = re.compile(r'([^:]+):(\d+)(?:\.\d+)?(?:-(\d+)(?:\.\d+)?)?')
    
    for trace in traces:
        match = pattern.search(trace)
        if match:
            filepath = match.group(1)
            start_line = int(match.group(2))
            end_line = int(match.group(3)) if match.group(3) else start_line
            parsed_traces.append((filepath, start_line, end_line))
            
    return parsed_traces


def resolve_filepath(filepath, src_dir=None):
    """
    Resolves absolute Docker paths to local host paths.
    """
    if os.path.exists(filepath):
        return filepath
        
    filename = os.path.basename(filepath)
    
    # Check in user-provided source directory
    if src_dir:
        candidate = os.path.join(src_dir, filename)
        if os.path.exists(candidate):
            return candidate
            
        # Recursive search in src_dir
        for root, _, files in os.walk(src_dir):
            if filename in files:
                return os.path.join(root, filename)
                
    # Check standard local fallback 'src/' directory
    local_fallback = os.path.join(".", "src", filename)
    if os.path.exists(local_fallback):
        return local_fallback

    return None


def extract_file_lines(filepath, start_line, end_line, src_dir=None, context=3):
    """Reads specific lines from RTL with padding and path resolution."""
    actual_path = resolve_filepath(filepath, src_dir)
    
    if not actual_path:
        return (
            f"// WARNING: Could not resolve file: {filepath}\n"
            f"// Try passing --src_dir pointing to your local Verilog source folder."
        )
        
    with open(actual_path, 'r') as f:
        lines = f.readlines()
        
    start_idx = max(0, start_line - 1 - context)
    end_idx = min(len(lines), end_line + context)
    
    snippet_lines = lines[start_idx:end_idx]
    return "".join(snippet_lines)


def generate_rtl_snippets_file(llm_payload_json, output_filename="critical_rtl_snippets.md", src_dir=None):
    """Extracts unique Verilog blocks and formats them into Markdown."""
    if isinstance(llm_payload_json, str):
        payload = json.loads(llm_payload_json)
    else:
        payload = llm_payload_json
        
    unique_blocks = set()
    markdown_content = "# Critical RTL Snippets\n\n"
    markdown_content += "> *Note: Exact behavioral blocks extracted from timing bottleneck paths.*\n\n"
    
    for violation in payload:
        sources = []
        sources.append(violation["startpoint"].get("rtl_source", "Implicit/Unknown"))
        sources.append(violation["endpoint"].get("rtl_source", "Implicit/Unknown"))
        
        for gate in violation["critical_logic_path"]:
            sources.append(gate.get("rtl_source", "Implicit/Unknown"))
            
        for src in sources:
            traces = parse_yosys_src_string(src)
            for filepath, start_line, end_line in traces:
                block_key = f"{filepath}:{start_line}-{end_line}"
                
                if block_key not in unique_blocks:
                    unique_blocks.add(block_key)
                    
                    code = extract_file_lines(filepath, start_line, end_line, src_dir=src_dir, context=3)
                    markdown_content += f"### Location: `{block_key}`\n"
                    markdown_content += f"```verilog\n{code}```\n\n---\n\n"
                    
    with open(output_filename, 'w') as f:
        f.write(markdown_content)

def extract_required_source_files(llm_payload_json):
    """Parses the payload and returns a list of unique, full source files the LLM needs."""
    payload = json.loads(llm_payload_json) if isinstance(llm_payload_json, str) else llm_payload_json
    required_files = set()
    
    for violation in payload:
        for key in ["startpoint", "endpoint"]:
            src = violation[key].get("rtl_source", "")
            traces = parse_yosys_src_string(src)
            for filepath, _, _ in traces:
                required_files.add(filepath)
                
    return list(required_files)

# ============================================================
# COMMAND-LINE INTERFACE
# ============================================================

if __name__ == "__main__":

    parser = argparse.ArgumentParser(
        description="Parse OpenSTA violations, map them to RTL using Yosys JSON, and extract code snippets."
    )

    parser.add_argument(
        "--sta",
        required=True,
        help="Path to OpenSTA timing report"
    )

    parser.add_argument(
        "--netlist",
        required=True,
        help="Path to Yosys JSON netlist"
    )

    parser.add_argument(
        "--src_dir",
        default="./src",
        help="Path to local Verilog source files directory (default: ./src)"
    )

    parser.add_argument(
        "--out_json",
        default="llm_payload.json",
        help="Output JSON file (default: llm_payload.json)"
    )

    parser.add_argument(
        "--out_snippets",
        default="critical_rtl_snippets.md",
        help="Output Markdown file for RTL snippets (default: critical_rtl_snippets.md)"
    )

    args = parser.parse_args()

    try:
        # 1. Generate JSON Payload
        payload = generate_llm_payload(args.sta, args.netlist)

        with open(args.out_json, "w") as f:
            f.write(payload)

        # 2. Extract Verilog Snippets to Markdown using the local src directory path
        generate_rtl_snippets_file(payload, args.out_snippets, src_dir=args.src_dir)

        payload_data = json.loads(payload)

        print("\n[SUCCESS] Parsing and Extraction Complete!")
        print(f"  - STA Report       : {args.sta}")
        print(f"  - Yosys Netlist    : {args.netlist}")
        print(f"  - RTL Source Dir   : {args.src_dir}")
        print(f"  - Violating Paths  : {len(payload_data)}")
        print(f"  - Output JSON      : {args.out_json}")
        print(f"  - Output Snippets  : {args.out_snippets}\n")

    except FileNotFoundError as e:
        print(f"Error: File not found: {e}")

    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON netlist: {e}")

    except Exception as e:
        print(f"Error: {e}")
