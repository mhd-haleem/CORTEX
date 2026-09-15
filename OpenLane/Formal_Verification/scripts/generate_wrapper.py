import json
import os
import sys

def load_config(config_path):
    print(f"[FEC] Loading configuration from {config_path}...")
    with open(config_path, 'r') as f:
        return json.load(f)

def merge_configs(base_cfg, llm_delta):
    print("[FEC] Merging LLM delta with static base configuration...")
    merged = base_cfg.copy()
    
    # 1. Update modified modules
    if "modified_modules" in llm_delta:
        merged["modified_modules"] = llm_delta["modified_modules"]
        
    # 2. Safely merge common_internal_outputs (Don't let the LLM delete the base ones!)
    if "common_internal_outputs" in llm_delta and llm_delta["common_internal_outputs"]:
        # Only add new ones if they don't already exist in the base config
        existing_names = {sig["name"] for sig in merged.get("common_internal_outputs", [])}
        for sig in llm_delta["common_internal_outputs"]:
            if sig["name"] not in existing_names:
                merged["common_internal_outputs"].append(sig)
    
    # 3. Safely update the interface latency differences
    if "interfaces" in llm_delta:
        for iface, delta_data in llm_delta["interfaces"].items():
            if iface in merged["interfaces"]:
                if "latency_diff" in delta_data:
                    merged["interfaces"][iface]["latency_diff"] = delta_data["latency_diff"]
                    
                # We can also let the LLM correct the data width if it knows better (like the 64-bit fix)
                if "data" in delta_data and "width" in delta_data["data"]:
                    merged["interfaces"][iface]["data"]["width"] = delta_data["data"]["width"]
                    
            else:
                print(f"[FEC][WARNING] LLM provided data for unknown interface '{iface}'.")
                
    return merged

def validate_config(cfg):
    # Added "formal_initialization" to the required list since the generator explicitly expects it
    required = ["golden_top", "revised_top", "interfaces", "common_inputs", "formal_initialization"]
    for req in required:
        if req not in cfg:
            print(f"[FEC][ERROR] Missing required key: {req}")
            sys.exit(1)
    
    for iface, data in cfg["interfaces"].items():
        if "clock" not in data:
            print(f"[FEC][ERROR] Interface {iface} has no clock defined.")
            sys.exit(1)
        if "data" not in data or "width" not in data["data"]:
            print(f"[FEC][ERROR] Interface {iface} data width is undefined.")
            sys.exit(1)
        if data["data"]["width"] <= 0:
            print(f"[FEC][ERROR] Interface {iface} has invalid width.")
            sys.exit(1)
        if "latency_diff" not in data:
            print(f"[FEC][ERROR] Interface {iface} missing 'latency_diff'.")
            sys.exit(1)

def format_wire(name, width, prefix=""):
    width_str = f"[{width-1}:0] " if width > 1 else ""
    return f"    wire {width_str}{prefix}{name};"

def generate_latency_alignment(iface_name: str, iface_meta: dict) -> str:
    """
    Reusable helper to generate the latency alignment blocks dynamically.
    Ensures that only one driver is generated for the aligned signals.
    """
    latency_diff = iface_meta.get("latency_diff", 0)
    
    # 6. Validate latency_diff is an integer
    if not isinstance(latency_diff, int):
        print(f"[FEC][ERROR] latency_diff for interface '{iface_name}' must be an integer. Got '{latency_diff}'.")
        sys.exit(1)
        
    # Extract interface variables
    clock = iface_meta["clock"]
    reset = iface_meta["reset"]
    d_width = iface_meta["data"]["width"]
    
    # Map the golden/revised signal names
    g_data_in = f"g_{iface_meta['data']['golden']}"
    g_valid_in = f"g_{iface_meta['valid']['golden']}"
    r_data_in = f"r_{iface_meta['data']['revised']}"
    r_valid_in = f"r_{iface_meta['valid']['revised']}"

    sv_lines = [
        f"    // --------------------------------------------------------",
        f"    // Latency Alignment: Interface {iface_name} (diff: {latency_diff})",
        f"    // --------------------------------------------------------"
    ]
    
    if latency_diff > 0:
        # Revised is slower -> Delay Golden, Revised is direct
        sv_lines.extend([
            f"    fec_delay #(",
            f"        .WIDTH({d_width}),",
            f"        .LATENCY({latency_diff})",
            f"    ) {iface_name}_gold_delay (",
            f"        .clk({clock}),",
            f"        .rst_n({reset}),",
            f"        .data_in({g_data_in}),",
            f"        .valid_in({g_valid_in}),",
            f"        .data_out(g_{iface_name}_aligned_data),",
            f"        .valid_out(g_{iface_name}_aligned_valid)",
            f"    );",
            f"",
            f"    assign r_{iface_name}_aligned_data = {r_data_in};",
            f"    assign r_{iface_name}_aligned_valid = {r_valid_in};"
        ])
        
    elif latency_diff < 0:
        # Golden is slower -> Delay Revised, Golden is direct
        abs_latency = abs(latency_diff)
        sv_lines.extend([
            f"    assign g_{iface_name}_aligned_data = {g_data_in};",
            f"    assign g_{iface_name}_aligned_valid = {g_valid_in};",
            f"",
            f"    fec_delay #(",
            f"        .WIDTH({d_width}),",
            f"        .LATENCY({abs_latency})",
            f"    ) {iface_name}_revised_delay (",
            f"        .clk({clock}),",
            f"        .rst_n({reset}),",
            f"        .data_in({r_data_in}),",
            f"        .valid_in({r_valid_in}),",
            f"        .data_out(r_{iface_name}_aligned_data),",
            f"        .valid_out(r_{iface_name}_aligned_valid)",
            f"    );"
        ])
        
    else:
        # No latency difference -> Both direct, no module instantiated
        sv_lines.extend([
            f"    assign g_{iface_name}_aligned_data = {g_data_in};",
            f"    assign g_{iface_name}_aligned_valid = {g_valid_in};",
            f"    assign r_{iface_name}_aligned_data = {r_data_in};",
            f"    assign r_{iface_name}_aligned_valid = {r_valid_in};"
        ])
        
    sv_lines.append("")
    return "\n".join(sv_lines)

def generate_wrapper(cfg, template_path, output_path):
    with open(template_path, 'r') as f:
        template = f.read()

    # 1. Port Declarations
    ports = []
    for inp in cfg["common_inputs"]:
        w_str = f"[{inp['width']-1}:0] " if inp['width'] > 1 else ""
        ports.append(f"    input wire {w_str}{inp['name']}")
    port_decl = ",\n".join(ports)

    # 2. Internal Signals
    signals = []
    for out in cfg.get("common_internal_outputs", []):
        signals.append(format_wire(out["name"], out["width"], "g_"))
        signals.append(format_wire(out["name"], out["width"], "r_"))
    
    for iface, data in cfg["interfaces"].items():
        d_width = data["data"]["width"]
        signals.append(format_wire(data["data"]["golden"], d_width, "g_"))
        signals.append(format_wire(data["data"]["revised"], d_width, "r_"))
        signals.append(format_wire(data["valid"]["golden"], 1, "g_"))
        signals.append(format_wire(data["valid"]["revised"], 1, "r_"))
        signals.append(format_wire(f"{iface}_aligned_data", d_width, "g_"))
        signals.append(format_wire(f"{iface}_aligned_valid", 1, "g_"))
        signals.append(format_wire(f"{iface}_aligned_data", d_width, "r_"))
        signals.append(format_wire(f"{iface}_aligned_valid", 1, "r_"))
    
    internal_sigs = "\n".join(signals)

    # 3. Formal Initialization (Resets)
    init_cfg = cfg.get("formal_initialization", {})
    if not init_cfg:
        print("[FEC][ERROR] Missing 'formal_initialization' block in JSON.")
        sys.exit(1)
        
    ref_clock = init_cfg["reference_clock"]
    resets = init_cfg["resets_to_assert"]

    init_logic = (
        f"    reg [3:0] f_rst_cnt = 0;\n"
        f"    always @(posedge {ref_clock}) begin\n"
        f"        f_past_valid <= 1;\n"
        f"        if (f_rst_cnt < 10) begin\n"
        f"            f_rst_cnt <= f_rst_cnt + 1;\n"
    )
    for r in resets:
        init_logic += f"            assume(!{r});\n"
    init_logic += "        end\n    end"

    # 4 & 5. Golden / Revised Instances
    g_inst = f"    {cfg['golden_top']} u_gold (\n"
    r_inst = f"    {cfg['revised_top']} u_revised (\n"
    
    g_ports = [f"        .{inp['name']}({inp['name']})" for inp in cfg["common_inputs"]]
    r_ports = list(g_ports)

    for out in cfg.get("common_internal_outputs", []):
        g_ports.append(f"        .{out['name']}(g_{out['name']})")
        r_ports.append(f"        .{out['name']}(r_{out['name']})")

    for iface, data in cfg["interfaces"].items():
        g_ports.append(f"        .{data['data']['golden']}(g_{data['data']['golden']})")
        g_ports.append(f"        .{data['valid']['golden']}(g_{data['valid']['golden']})")
        r_ports.append(f"        .{data['data']['revised']}(r_{data['data']['revised']})")
        r_ports.append(f"        .{data['valid']['revised']}(r_{data['valid']['revised']})")

    g_inst += ",\n".join(g_ports) + "\n    );"
    r_inst += ",\n".join(r_ports) + "\n    );"

    # 6. Latency Alignment
    alignments = []
    for iface, data in cfg["interfaces"].items():
        alignments.append(generate_latency_alignment(iface, data))

    latency_logic = "\n".join(alignments)

    # 7. Assertions
    assertions = []
    for iface, data in cfg["interfaces"].items():
        clk = data["clock"]
        rst = data["reset"]
        assertions.append(f"    always @(posedge {clk}) begin")
        assertions.append(f"        if (f_past_valid && {rst}) begin")
        assertions.append(f"            assert(g_{iface}_aligned_valid == r_{iface}_aligned_valid);")
        assertions.append(f"            if (g_{iface}_aligned_valid) assert(g_{iface}_aligned_data == r_{iface}_aligned_data);")
        assertions.append(f"        end")
        assertions.append(f"    end\n")
    
    assert_logic = "\n".join(assertions)

    # Replace tags
    template = template.replace("{{PORT_DECLARATIONS}}", port_decl)
    template = template.replace("{{INTERNAL_SIGNAL_DECLARATIONS}}", internal_sigs)
    template = template.replace("{{FORMAL_INITIALIZATION}}", init_logic)
    template = template.replace("{{GOLDEN_INSTANCE}}", g_inst)
    template = template.replace("{{REVISED_INSTANCE}}", r_inst)
    template = template.replace("{{LATENCY_ALIGNMENT}}", latency_logic)
    template = template.replace("{{ASSERTIONS}}", assert_logic)

    with open(output_path, 'w') as f:
        f.write(template)
    
    print(f"[FEC] Golden top: {cfg['golden_top']}")
    print(f"[FEC] Revised top: {cfg['revised_top']}")
    print(f"[FEC] Interfaces: {len(cfg['interfaces'])}")
    for i, d in cfg['interfaces'].items():
        print(f"[FEC] Interface {i} latency diff: {d['latency_diff']}")
    print(f"[FEC] Generated: {output_path}")

if __name__ == "__main__":
    # Define file paths
    base_config_path = "config/base_config.json"
    llm_delta_path = "config/llm_delta.json"
    template_path = "template/top_sec_wrapper.sv.template"
    output_path = "generated/top_sec_wrapper.sv"

    # Ensure directories exist
    os.makedirs("generated", exist_ok=True)

    # Load the two configuration files
    base_cfg = load_config(base_config_path)
    llm_delta = load_config(llm_delta_path)

    # Merge them into a single configuration
    final_cfg = merge_configs(base_cfg, llm_delta)

    # Validate and Generate
    validate_config(final_cfg)
    generate_wrapper(final_cfg, template_path, output_path)