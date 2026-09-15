import json
import os
import re
import sys
import argparse
import glob

def parse_openlane_config(ol_config_path):
    print(f"[EXTRACT] Reading OpenLane config for design name: {ol_config_path}")
    with open(ol_config_path, 'r') as f:
        ol_cfg = json.load(f)
    
    design_name = ol_cfg.get("DESIGN_NAME")
    if not design_name:
        print(f"[EXTRACT][ERROR] DESIGN_NAME not found in {ol_config_path}")
        sys.exit(1)
    return design_name

def extract_ports(design_name, v_files):
    port_pattern = re.compile(
        r'\b(input|output)\b\s+'                 
        r'(?:(?:wire|reg|logic)\b\s+)?'          
        r'(?:\[(.*?)\]\s*)?'                     
        r'([a-zA-Z0-9_]+)\b'                     
    )
    
    # Regex to find parameters like: parameter WIDTH = 64; or #(parameter int WIDTH=64)
    param_pattern = re.compile(r'\bparameter\s+(?:[a-zA-Z0-9_]+\s+)?([a-zA-Z0-9_]+)\s*=\s*(\d+)')
    
    ports = []
    found_module = False
    
    print(f"[EXTRACT] Searching for module '{design_name}' in {len(v_files)} files...")
    
    for v_file in v_files:
        if not os.path.exists(v_file):
            continue
        with open(v_file, 'r') as f:
            content = f.read()
            
        mod_match = re.search(rf'\bmodule\s+{design_name}\b(.*?);', content, re.DOTALL)
        if mod_match:
            print(f"[EXTRACT] Found module '{design_name}' in {v_file}")
            found_module = True
            
            # 1. Extract all parameter definitions from the file
            params = dict(param_pattern.findall(content))
            print(f"[EXTRACT] Extracted Parameters: {params}")
            
            port_block = mod_match.group(1)
            matches = port_pattern.findall(port_block)
            
            for direction, width_str, name in matches:
                width = 1
                if width_str:
                    parts = width_str.split(':')
                    if len(parts) == 2:
                        high_str, low_str = parts[0], parts[1]
                        
                        # 2. Substitute parameters (e.g., "WIDTH-1" -> "64-1")
                        for p_name, p_val in params.items():
                            high_str = re.sub(rf'\b{p_name}\b', p_val, high_str)
                            low_str = re.sub(rf'\b{p_name}\b', p_val, low_str)
                        
                        # 3. Safely evaluate the math
                        try:
                            # Evaluate simple math expressions without builtin functions
                            high = eval(high_str, {"__builtins__": None}, {})
                            low = eval(low_str, {"__builtins__": None}, {})
                            width = abs(int(high) - int(low)) + 1
                        except Exception as e:
                            print(f"[EXTRACT][WARNING] Could not parse width '{width_str}'. Defaulting to 64.")
                            width = 64
                            
                ports.append({"direction": direction, "name": name, "width": width})
            break 
            
    if not found_module:
        print(f"[EXTRACT][ERROR] Could not find 'module {design_name}' in provided Verilog files.")
        sys.exit(1)
        
    return ports

def build_base_config(design_name, ports):
    cfg = {
        "golden_top": "gold",
        "revised_top": "revised",
        "common_inputs": [],
        "common_internal_outputs": [],
        "formal_initialization": {
            "reference_clock": "",
            "resets_to_assert": []
        },
        "interfaces": {}
    }
    
    clocks = []
    resets = []
    outputs = []
    
    # 1. Categorize Ports
    for p in ports:
        name = p["name"]
        if p["direction"] == "input":
            cfg["common_inputs"].append({"name": name, "width": p["width"]})
            if "clk" in name.lower() or "clock" in name.lower():
                clocks.append(name)
            if "rst" in name.lower() or "reset" in name.lower():
                resets.append(name)
        elif p["direction"] == "output":
            outputs.append(p)
            
    # 2. Setup Formal Initialization
    if clocks:
        out_clocks = [c for c in clocks if "out" in c.lower()]
        cfg["formal_initialization"]["reference_clock"] = out_clocks[0] if out_clocks else clocks[0]
    cfg["formal_initialization"]["resets_to_assert"] = resets

    # 3. Group Outputs into Interfaces
    interface_groups = {}
    for out in outputs:
        name = out["name"]
        prefix_match = re.match(r'^([a-zA-Z0-9]+)_', name)
        
        if "data" in name.lower() and prefix_match:
            prefix = prefix_match.group(1)
            if prefix not in interface_groups: interface_groups[prefix] = {}
            interface_groups[prefix]["data"] = out
        elif "valid" in name.lower() and prefix_match:
            prefix = prefix_match.group(1)
            if prefix not in interface_groups: interface_groups[prefix] = {}
            interface_groups[prefix]["valid"] = out
        else:
            cfg["common_internal_outputs"].append({"name": name, "width": out["width"]})
            
    # 4. Map Interfaces
    for prefix, sigs in interface_groups.items():
        if "data" in sigs and "valid" in sigs:
            idx = ''.join(filter(str.isdigit, prefix))
            if not idx: idx = "0"
            
            best_clk = next((c for c in clocks if idx in c and "out" in c), clocks[0] if clocks else "")
            best_rst = next((r for r in resets if idx in r and "out" in r), resets[0] if resets else "")
            
            cfg["interfaces"][prefix] = {
                "clock": best_clk,
                "reset": best_rst,
                "data": {
                    "golden": sigs["data"]["name"],
                    "revised": sigs["data"]["name"],
                    "width": sigs["data"]["width"]
                },
                "valid": {
                    "golden": sigs["valid"]["name"],
                    "revised": sigs["valid"]["name"]
                },
                "latency_diff": 0 
            }
            
    return cfg

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ol_config", required=True, help="Path to OpenLane config.json")
    parser.add_argument("--src_dir", default="OpenLane/Formal_Verification/src", help="Directory containing Golden RTL files")
    parser.add_argument("--output", default="OpenLane/Formal_Verification/config/base_config.json", help="Path to save output JSON")
    args = parser.parse_args()
    
    design_name = parse_openlane_config(args.ol_config)
    
    v_files = glob.glob(os.path.join(args.src_dir, "*.v")) + glob.glob(os.path.join(args.src_dir, "*.sv"))
    
    if not v_files:
        print(f"[EXTRACT][ERROR] No .v or .sv files found in {args.src_dir}")
        sys.exit(1)
        
    ports = extract_ports(design_name, v_files)
    base_cfg = build_base_config(design_name, ports)
    
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, 'w') as f:
        json.dump(base_cfg, f, indent=4)
        
    print(f"[EXTRACT] Successfully generated Base Config: {args.output}")
    print(f"          Found {len(base_cfg['interfaces'])} observable interfaces and {len(base_cfg['common_internal_outputs'])} common outputs.")