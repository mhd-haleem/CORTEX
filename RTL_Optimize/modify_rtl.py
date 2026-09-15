# Version 5: Multi-RTL Optimization with Combined FEC JSON Extraction & Syntax Feedback Loop
# (Includes Anti-Laziness Safeguard)

import argparse
import json
import os
import re
import shutil
import subprocess
import time
from google import genai
from google.genai import types
from google.genai.errors import ServerError

# Initialize Gemini Client
API_KEY = os.environ.get("GEMINI_API_KEY")
client = genai.Client(api_key=API_KEY)

def parse_combined_json_response(llm_response: str) -> tuple[dict[str, str], dict]:
    """
    Parses the raw JSON response from Gemini containing 'modified_rtl' and 'fec_config'.
    Strips Markdown code fences and guarantees dictionary return types.
    """
    if not llm_response:
        return {}, {}

    clean_text = llm_response.strip()

    # Strip triple backticks or markdown fences if present
    if clean_text.startswith("```"):
        clean_text = re.sub(r"^```(?:json)?\s*", "", clean_text, flags=re.IGNORECASE)
        clean_text = re.sub(r"\s*```$", "", clean_text).strip()

    try:
        data = json.loads(clean_text)
    except json.JSONDecodeError as e:
        match = re.search(r"(\{.*\})", clean_text, re.DOTALL)
        if match:
            try:
                data = json.loads(match.group(1))
            except json.JSONDecodeError:
                print(f"[ERROR] Failed to parse JSON response from LLM: {e}")
                return {}, {}
        else:
            print(f"[ERROR] Failed to parse JSON response from LLM: {e}")
            return {}, {}

    modified_rtl = data.get("modified_rtl", {})
    fec_config = data.get("fec_config", {})

    # Guard: If LLM returned modified_rtl as a string instead of a dictionary
    if isinstance(modified_rtl, str):
        modified_rtl = {"_raw_string_fallback": modified_rtl}
    elif not isinstance(modified_rtl, dict):
        modified_rtl = {}

    if not isinstance(fec_config, dict):
        fec_config = {}

    return modified_rtl, fec_config


def run_eda_parser(filenames: list[str]) -> tuple[bool, str]:
    """Runs Icarus Verilog compilation check on all RTL files together."""
    if not shutil.which("iverilog"):
        return False, "ERROR: iverilog not found in system PATH. Please install Icarus Verilog."

    output_dev = "nul" if os.name == "nt" else "/dev/null"
    cmd = ["iverilog", "-g2012", "-o", output_dev] + filenames

    try:
        subprocess.run(cmd, capture_output=True, text=True, check=True)
        return True, "Icarus Verilog compilation passed without syntax errors."
    except subprocess.CalledProcessError as e:
        error_log = e.stdout + "\n" + e.stderr
        return False, error_log.strip()


def send_message_with_retry(chat, prompt: str, max_retries=3, backoff_seconds=5):
    """Sends message to Gemini API with exponential backoff for 503 errors."""
    for attempt in range(1, max_retries + 1):
        try:
            return chat.send_message(prompt)
        except ServerError as e:
            if "503" in str(e) and attempt < max_retries:
                sleep_time = backoff_seconds * attempt
                print(f"[503 Server Busy] Retrying in {sleep_time}s (Attempt {attempt}/{max_retries})...")
                time.sleep(sleep_time)
            else:
                raise e


def modify_and_fix_rtl(source_files: list[str], modification_prompt: str, json_data: dict, max_iterations=3) -> bool:
    base_opt_dir = "RTL_Optimize"
    iter_dir = os.path.join(base_opt_dir, "iter")
    dut_dir = os.path.join(base_opt_dir, "DUT")
    fv_dir = os.path.join("OpenLane", "Formal_Verification","config")

    os.makedirs(iter_dir, exist_ok=True)
    os.makedirs(dut_dir, exist_ok=True)
    os.makedirs(fv_dir, exist_ok=True)

    rtl_sections = []
    for filepath in source_files:
        if not os.path.exists(filepath):
            print(f"[ERROR] Source file '{filepath}' not found.")
            return False

        with open(filepath, "r", encoding="utf-8") as f:
            code = f.read()

        basename = os.path.basename(filepath)
        rtl_sections.append(f"--- File: {basename} ---\n```verilog\n{code}\n```")

    combined_rtl_str = "\n\n".join(rtl_sections)
    json_str = json.dumps(json_data, indent=2)

    print(f"[*] Loaded {len(source_files)} RTL file(s) into {dut_dir}.")
    print(f"[*] Initializing chat session with Gemini...")
    chat = client.chats.create(model="gemini-3.6-flash") # Using pro or flash based on your previous config

    system_instruction = (
        "You are an expert RTL hardware engineer. Your task is to modify the provided Verilog code "
        "according to the user's modification request and the specifications in the provided JSON file.\n\n"
        "IMPORTANT: You MUST return a single, raw valid JSON object with top-level keys 'modified_rtl' "
        "and 'fec_config'. Do NOT wrap the output in Markdown code blocks (no ```json). "
        "Do NOT provide any conversational explanations before or after the JSON."
    )

    full_prompt = (
        f"{system_instruction}\n\n"
        f"--- Existing Verilog Files ---\n"
        f"{combined_rtl_str}\n\n"
        f"--- Timing JSON Context / Specifications ---\n"
        f"```json\n{json_str}\n```\n\n"
        f"--- Modification Request ---\n"
        f"{modification_prompt}"
    )

    for iteration in range(1, max_iterations + 1):
        print(f"\n[Iteration {iteration}/{max_iterations}] Querying Gemini for RTL updates and FEC config...")
        response = send_message_with_retry(chat, full_prompt)

        modified_rtl_dict, fec_config_dict = parse_combined_json_response(response.text)

        if not modified_rtl_dict:
            print(f"[!] Warning: No RTL code extracted on iteration {iteration}.")

        # Write RTL files to DUT and iter directories
        for src_file in source_files:
            basename = os.path.basename(src_file)
            file_base, file_ext = os.path.splitext(basename)
            iter_filename = os.path.join(iter_dir, f"{file_base}_mod_iter{iteration}{file_ext}")
            dut_filename = os.path.join(dut_dir, basename)

            code_to_write = modified_rtl_dict.get(basename, "").strip()

            # --- ANTI-LAZINESS SAFEGUARD ---
            if len(code_to_write) < 50:
                print(f"[-] LLM skipped '{basename}' (returned empty). Preserving original file.")
                # Read the current intact file so we don't wipe it out
                with open(src_file, "r", encoding="utf-8") as orig_f:
                    code_to_write = orig_f.read()
            else:
                print(f"[+] Saved updated RTL snapshot: {iter_filename}")
            # -------------------------------

            # Save iteration snapshot
            with open(iter_filename, "w", encoding="utf-8") as f:
                f.write(code_to_write)

            # Update working file directly in DUT folder
            with open(dut_filename, "w", encoding="utf-8") as f:
                f.write(code_to_write)

        # Save fec_config.json for Python formal wrapper generator
        if fec_config_dict:
            fec_dest_primary = os.path.join(fv_dir, "llm_delta.json")
            fec_dest_backup = os.path.join(base_opt_dir, "llm_delta.json")

            with open(fec_dest_primary, "w", encoding="utf-8") as f:
                json.dump(fec_config_dict, f, indent=2)
            with open(fec_dest_backup, "w", encoding="utf-8") as f:
                json.dump(fec_config_dict, f, indent=2)

            print(f"[+] Successfully extracted and saved 'llm_delta.json' -> {fec_dest_primary}")

        # Gather ALL .v and .sv files currently in RTL_Optimize/DUT for syntax check
        dut_files = [
            os.path.join(dut_dir, f)
            for f in os.listdir(dut_dir)
            if f.endswith((".v", ".sv"))
        ]

        print(f"[*] Running iverilog parser on DUT files ({len(dut_files)} total)...")
        success, compiler_message = run_eda_parser(dut_files)

        if success:
            print(f"\n[SUCCESS] Syntax verification passed on iteration {iteration}!")
            print(compiler_message)
            print(f"[+] Verified RTL available in: {dut_dir}")
            return True
        else:
            print(f"[!] Compilation failed. Triggering Gemini feedback loop...")
            print(f"Compiler Log Snippet:\n---\n{compiler_message}\n---")

            full_prompt = (
                f"The modified code generated in iteration {iteration} failed compilation with the following errors:\n"
                f"```\n{compiler_message}\n```\n"
                f"Please fix all syntax and structural errors reported above and return a single valid JSON object "
                f"containing 'modified_rtl' and 'fec_config'. You MUST return the code for ALL files, do not skip any."
            )

    print(f"\n[FAILURE] Reached maximum iterations ({max_iterations}) without resolving all syntax errors.")
    return False


def main():
    parser = argparse.ArgumentParser(
        description="Modify Verilog files using Gemini and extract FEC JSON config."
    )
    parser.add_argument(
        "rtl_files",
        nargs="+",
        help="One or more Verilog/SystemVerilog source files (.v or .sv)"
    )
    parser.add_argument(
        "--prompt_file", "-p",
        type=str,
        required=True,
        help="Path to the text file containing modification instructions"
    )
    parser.add_argument(
        "--json_file", "-j",
        type=str,
        required=True,
        help="Path to the JSON file containing specs/configurations"
    )
    parser.add_argument(
        "--max-iterations",
        type=int,
        default=3,
        help="Maximum syntax repair attempts (default: 3)"
    )

    args = parser.parse_args()

    if not os.path.exists(args.prompt_file):
        print(f"[ERROR] Prompt file not found: {args.prompt_file}")
        return

    if not os.path.exists(args.json_file):
        print(f"[ERROR] JSON file not found: {args.json_file}")
        return

    try:
        with open(args.json_file, "r", encoding="utf-8") as f:
            json_data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"[ERROR] Failed to parse JSON file '{args.json_file}': {e}")
        return

    with open(args.prompt_file, "r", encoding="utf-8") as f:
        modification_prompt = f.read().strip()

    if not modification_prompt:
        print(f"[ERROR] The prompt file '{args.prompt_file}' is empty.")
        return

    modify_and_fix_rtl(
        source_files=args.rtl_files,
        modification_prompt=modification_prompt,
        json_data=json_data,
        max_iterations=args.max_iterations
    )


if __name__ == "__main__":
    main()
