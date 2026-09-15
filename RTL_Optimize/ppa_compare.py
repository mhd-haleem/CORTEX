#!/usr/bin/env python3
import argparse
import os
import re
import glob

def extract_metric(run_dir, metric_type):
    """Parses standard OpenLane/OpenSTA .rpt files based on the requested metric."""
    synth_dir = os.path.join(run_dir, "reports", "synthesis")
    if not os.path.exists(synth_dir):
        return None

    try:
        # Extract WNS (Setup) from the summary file
        if metric_type == "WNS_SETUP":
            rpt_path = os.path.join(synth_dir, "2-syn_sta.summary.rpt")
            if os.path.exists(rpt_path):
                with open(rpt_path, 'r') as f:
                    content = f.read()
                    # Uses re.DOTALL to read across newlines to find the slack value
                    match = re.search(r'report_worst_slack -max \(Setup\).*?worst slack\s+([-\d\.]+)', content, re.DOTALL)
                    if match: return float(match.group(1))

        # Extract WNS (Hold) from the summary file
        elif metric_type == "WNS_HOLD":
            rpt_path = os.path.join(synth_dir, "2-syn_sta.summary.rpt")
            if os.path.exists(rpt_path):
                with open(rpt_path, 'r') as f:
                    content = f.read()
                    match = re.search(r'report_worst_slack -min \(Hold\).*?worst slack\s+([-\d\.]+)', content, re.DOTALL)
                    if match: return float(match.group(1))

        # Extract Power
        elif metric_type == "POWER":
            rpt_path = os.path.join(synth_dir, "2-syn_sta.power.rpt")
            if os.path.exists(rpt_path):
                with open(rpt_path, 'r') as f:
                    lines = f.readlines()
                    # Scan backwards to find the "Total" row at the bottom of the table
                    for line in reversed(lines):
                        if line.strip().startswith("Total"):
                            parts = line.split()
                            if len(parts) >= 5:
                                return float(parts[-2]) # Second to last item before the % sign

        # Extract Area
        elif metric_type == "AREA":
            stat_files = glob.glob(os.path.join(synth_dir, "1-synthesis*.stat.rpt")) + glob.glob(os.path.join(synth_dir, "1-synthesis*.stat"))
            if stat_files:
                with open(stat_files[0], 'r') as f:
                    content = f.read()
                    match = re.search(r'Chip area for module.*?:\s*([\d\.]+)', content)
                    if match: return float(match.group(1))

    except Exception as e:
        pass # Return None if parsing fails

    return None

def calc_delta(baseline, optimized, is_wns=False):
    """Calculates difference/percentage and formats ANSI colors."""
    if baseline is None or optimized is None:
        return "N/A", ""
    
    diff = optimized - baseline
    
    if is_wns:
        # For WNS, positive difference is good (Slack improved/moved towards 0 or positive)
        if diff > 0: return f"+{diff:.2f} ns", "\033[92m" # Green
        if diff < 0: return f"{diff:.2f} ns", "\033[91m"  # Red
        return "0.00 ns", "\033[93m"                      # Yellow
    else:
        # For Power/Area, negative percentage is good (Reduction)
        if baseline == 0: return "N/A", ""
        pct = (diff / baseline) * 100
        if pct < 0: return f"{pct:.2f}%", "\033[92m"      # Green (Reduced)
        if pct > 0: return f"+{pct:.2f}%", "\033[91m"     # Red (Increased)
        return "0.00%", "\033[93m"                        # Yellow (No change)

def main():
    parser = argparse.ArgumentParser(description="PPA Comparison Generator")
    parser.add_argument("--baseline", required=True, help="Path to original run directory")
    parser.add_argument("--optimized", required=True, help="Path to optimized run directory")
    args = parser.parse_args()

    # Extract all 4 metrics
    base_wns_s = extract_metric(args.baseline, "WNS_SETUP")
    opt_wns_s  = extract_metric(args.optimized, "WNS_SETUP")
    
    base_wns_h = extract_metric(args.baseline, "WNS_HOLD")
    opt_wns_h  = extract_metric(args.optimized, "WNS_HOLD")

    base_pwr   = extract_metric(args.baseline, "POWER")
    opt_pwr    = extract_metric(args.optimized, "POWER")
    
    base_area  = extract_metric(args.baseline, "AREA")
    opt_area   = extract_metric(args.optimized, "AREA")

    # Format values into strings safely
    str_b_wns_s = f"{base_wns_s:.2f} ns" if base_wns_s is not None else "N/A"
    str_o_wns_s = f"{opt_wns_s:.2f} ns"  if opt_wns_s is not None else "N/A"
    
    str_b_wns_h = f"{base_wns_h:.2f} ns" if base_wns_h is not None else "N/A"
    str_o_wns_h = f"{opt_wns_h:.2f} ns"  if opt_wns_h is not None else "N/A"

    str_b_pwr = f"{base_pwr:.2e} W" if base_pwr is not None else "N/A"
    str_o_pwr = f"{opt_pwr:.2e} W"  if opt_pwr is not None else "N/A"
    
    str_b_area = f"{base_area:.2f} um²" if base_area is not None else "N/A"
    str_o_area = f"{opt_area:.2f} um²"  if opt_area is not None else "N/A"

    # Calculate Deltas & Colors
    delta_wns_s, col_wns_s = calc_delta(base_wns_s, opt_wns_s, is_wns=True)
    delta_wns_h, col_wns_h = calc_delta(base_wns_h, opt_wns_h, is_wns=True)
    delta_pwr, col_pwr     = calc_delta(base_pwr, opt_pwr)
    delta_area, col_area   = calc_delta(base_area, opt_area)
    
    RESET = "\033[0m"

    # Print Expanded Table
    print("\n" + "="*75)
    print(f"{'POST-OPTIMIZATION PPA COMPARISON':^75}")
    print("="*75)
    print(f"{'Metric':<18} | {'Baseline (Original)':<20} | {'Optimized (LLM)':<17} | {'Delta':<10}")
    print("-" * 75)
    print(f"{'WNS (Setup)':<18} | {str_b_wns_s:<20} | {str_o_wns_s:<17} | {col_wns_s}{delta_wns_s}{RESET}")
    print(f"{'WNS (Hold)':<18} | {str_b_wns_h:<20} | {str_o_wns_h:<17} | {col_wns_h}{delta_wns_h}{RESET}")
    print(f"{'Total Power':<18} | {str_b_pwr:<20} | {str_o_pwr:<17} | {col_pwr}{delta_pwr}{RESET}")
    print(f"{'Cell Area':<18} | {str_b_area:<20} | {str_o_area:<17} | {col_area}{delta_area}{RESET}")
    print("="*75 + "\n")

if __name__ == "__main__":
    main()
