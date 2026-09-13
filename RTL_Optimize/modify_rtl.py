# Version 4 : Multi-RTL Syntax Optimization and Feedback Loop

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


def extract_single_code(llm_response: str) -> str:
    """Extracts raw Verilog/SystemVerilog code block from markdown fences safely."""
    if not llm_response:
        return ""
    pattern = r"```(?:verilog|systemverilog|vlog)?\s*\n(.*?)```"
    match = re.search(pattern, llm_response, re.DOTALL | re.IGNORECASE)
    if match:
        return match.group(1).strip()
    return llm_response.strip()


def extract_multiple_codes(llm_response: str, source_files: list[str]) -> dict[str, str]:
    """
    Extracts code blocks tagged by filename from LLM response.
    Falls back to single code block extraction if only one file is processed.
    """
    extracted = {}
    expected_basenames = [os.path.basename(f) for f in source_files]

    # Pattern matches: FILE: filename.v followed by code block
    pattern = r"FILE:\s*([^\n\r]+)\s*```(?:verilog|systemverilog|vlog)?\s*\n(.*?)```"
    matches = re.findall(pattern, llm_response, re.DOTALL | re.IGNORECASE)

    for fn_match, code_match in matches:
        clean_fn = os.path.basename(fn_match.strip())
        extracted[clean_fn] = code_match.strip()

    # Fallback if single file and header tag was omitted by LLM
    if len(expected_basenames) == 1 and expected_basenames[0] not in extracted:
        code = extract_single_code(llm_response)
        if code:
            extracted[expected_basenames[0]] = code

    return extracted


def run_eda_parser(filenames: list[str]) -> tuple[bool, str]:
    """Runs Icarus Verilog compilation check on all RTL files together."""
    if not shutil.which("iverilog"):
        return False, "ERROR: iverilog not found in system PATH. Please install Icarus Verilog."

    output_dev = "nul" if os.name == "nt" else "/dev/null"
    cmd = ["iverilog", "-g2012", "-o", output_dev] + filenames

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
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
    os.makedirs(iter_dir, exist_ok=True)
    os.makedirs(dut_dir, exist_ok=True)

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
    print(f"[*] Initializing chat loop with gemini-3.6-flash...")
    chat = client.chats.create(model="gemini-3.6-flash")

    system_instruction = (
        "You are an expert RTL hardware engineer. Your task is to modify the provided Verilog/SystemVerilog code "
        "according to the user's modification request and the specifications in the provided JSON file.\n\n"
        "IMPORTANT: You MUST return the updated code for EVERY file provided. Format each file explicitly as:\n"
        "FILE: <filename>\n"
        "```verilog\n"
        "<updated code for this file>\n"
        "```\n"
        "Do not provide long textual explanations."
    )

    full_prompt = (
        f"{system_instruction}\n\n"
        f"--- Existing Verilog/SystemVerilog Files ---\n"
        f"{combined_rtl_str}\n\n"
        f"--- JSON Context / Specifications ---\n"
        f"```json\n{json_str}\n```\n\n"
        f"--- Modification Request ---\n"
        f"{modification_prompt}"
    )

    for iteration in range(1, max_iterations + 1):
        print(f"\n[Iteration {iteration}/{max_iterations}] Querying Gemini for updates...")
        response = send_message_with_retry(chat, full_prompt)

        extracted_codes = extract_multiple_codes(response.text, source_files)

        for src_file in source_files:
            basename = os.path.basename(src_file)
            file_base, file_ext = os.path.splitext(basename)
            iter_filename = os.path.join(iter_dir, f"{file_base}_mod_iter{iteration}{file_ext}")
            dut_filename = os.path.join(dut_dir, basename)

            code_to_write = extracted_codes.get(basename, "")
            
            # Save iteration snapshot
            with open(iter_filename, "w", encoding="utf-8") as f:
                f.write(code_to_write)

            # Update working file directly in DUT folder
            with open(dut_filename, "w", encoding="utf-8") as f:
                f.write(code_to_write)

            print(f"[+] Saved iteration snapshot: {iter_filename}")

        # Gather ALL .v and .sv files currently in RTL_Optimize/DUT for syntax check
        dut_files = [
            os.path.join(dut_dir, f)
            for f in os.listdir(dut_dir)
            if f.endswith((".v", ".sv"))
        ]

        print(f"[*] Running iverilog parser on all DUT files ({len(dut_files)} total)...")
        success, compiler_message = run_eda_parser(dut_files)

        if success:
            print(f"\n[SUCCESS] Verification passed on iteration {iteration}!")
            print(compiler_message)
            print(f"[+] All updated RTL files verified successfully in: {dut_dir}")
            return True
        else:
            print(f"[!] Compilation failed. Feedback loop triggered.")
            print(f"Compiler Log Snippet:\n---\n{compiler_message}\n---")

            full_prompt = (
                f"The modified code generated in iteration {iteration} failed compilation with the following errors:\n"
                f"```\n{compiler_message}\n```\n"
                f"Please fix all syntax and structural errors reported above and return updated versions of ALL files using the exact format:\n"
                f"FILE: <filename>\n```verilog\n<code>\n```"
            )

    print(f"\n[FAILURE] Reached maximum iterations ({max_iterations}) without resolving all syntax errors.")
    return False

def main():
    parser = argparse.ArgumentParser(
        description="Modify multiple Verilog files using Gemini and verify syntax with Icarus Verilog."
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