# Version 3 : Check existing RTL for syntax errors -> Generate & Feedback

import argparse
import os
import re
import shutil
import subprocess
import time
from google import genai
from google.genai import types
from google.genai.errors import ServerError

# 1. Initialize Gemini Client
API_KEY = os.environ.get("GEMINI_API_KEY")
client = genai.Client(api_key=API_KEY)

def extract_code(llm_response: str) -> str:
    """Extracts raw Verilog/SystemVerilog code block from markdown fences safely."""
    if not llm_response:
        return ""
    pattern = r"```(?:verilog|systemverilog|vlog)?\s*\n(.*?)```"
    match = re.search(pattern, llm_response, re.DOTALL | re.IGNORECASE)
    if match:
        return match.group(1).strip()
    return llm_response.strip()

def run_eda_parser(filename: str) -> tuple[bool, str]:
    """Runs Icarus Verilog syntax and compilation check."""
    if not shutil.which("iverilog"):
        return False, "ERROR: iverilog not found in system PATH. Please install Icarus Verilog."
    
    output_dev = "nul" if os.name == "nt" else "/dev/null"
    cmd = ["iverilog", "-g2005", "-o", output_dev, filename]
    
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
                print(f"[503 Server Busy] High demand detected. Retrying in {sleep_time}s (Attempt {attempt}/{max_retries})...")
                time.sleep(sleep_time)
            else:
                raise e

def modify_and_fix_rtl(source_file: str, modification_prompt: str, max_iterations=3) -> bool:
    """
    Reads an existing Verilog file, applies modifications using Gemini based on a prompt,
    checks it with iverilog, and loops to fix any compilation bugs.
    Saves iteration files separately.
    """
    if not os.path.exists(source_file):
        print(f"[ERROR] Source file '{source_file}' not found.")
        return False
        
    with open(source_file, "r", encoding="utf-8") as f:
        existing_code = f.read()

    print(f"[*] Loaded existing RTL from {source_file} ({len(existing_code.splitlines())} lines)")
    print(f"[*] Initializing chat loop for model gemini-3.6-flash...")
    chat = client.chats.create(model="gemini-3.6-flash")
    
    system_instruction = (
        "You are an expert RTL hardware engineer. Your task is to modify the provided Verilog code "
        "according to the user's modification request. Ensure the code remains completely valid and synthesizable. "
        "Wrap your updated code cleanly inside ```verilog ... ``` markdown tags. Do not provide long textual explanations."
    )
    
    full_prompt = (
        f"{system_instruction}\n\n"
        f"--- Existing Verilog Code ---\n"
        f"```verilog\n{existing_code}\n```\n\n"
        f"--- Modification Request ---\n"
        f"{modification_prompt}"
    )
    
    file_base, file_ext = os.path.splitext(source_file)
    
    for iteration in range(1, max_iterations + 1):
        iter_filename = f"{file_base}_mod_iter{iteration}{file_ext}"
        
        print(f"\n[Iteration {iteration}/{max_iterations}] Querying Gemini for updates...")
        response = send_message_with_retry(chat, full_prompt)
        
        verilog_code = extract_code(response.text)
        with open(iter_filename, "w", encoding="utf-8") as f:
            f.write(verilog_code)
            
        print(f"[+] Modified code written to {iter_filename}. Running iverilog parser...")
        
        success, compiler_message = run_eda_parser(iter_filename)
        
        if success:
            print(f"\n[SUCCESS] Verification passed on iteration {iteration}!")
            print(compiler_message)
            print(f"[+] Final working code saved in: {iter_filename}")
            return True
        else:
            print(f"[!] Compilation failed. Feedback loop triggered.")
            print(f"Compiler Log Snippet:\n---\n{compiler_message}\n---")
            
            full_prompt = (
                f"The modified code generated in iteration {iteration} failed compilation with the following errors:\n"
                f"```\n{compiler_message}\n```\n"
                f"Please fix all syntax and structural errors reported above and return the entire, updated Verilog code."
            )
            
    print(f"\n[FAILURE] Reached maximum iterations ({max_iterations}) without resolving all syntax errors.")
    return False

def main():
    parser = argparse.ArgumentParser(
        description="Modify a Verilog file using Gemini based on a prompt file and verify syntax with Icarus Verilog."
    )
    parser.add_argument(
        "rtl_file", 
        type=str, 
        help="Path to the Verilog source file (.v or .sv)"
    )
    parser.add_argument(
        "prompt_file", 
        type=str, 
        help="Path to the text file containing modification instructions"
    )
    parser.add_argument(
        "--max-iterations", 
        type=int, 
        default=3, 
        help="Maximum syntax repair attempts (default: 3)"
    )
    
    args = parser.parse_args()

    if not os.path.exists(args.rtl_file):
        print(f"[ERROR] RTL source file not found: {args.rtl_file}")
        return

    if not os.path.exists(args.prompt_file):
        print(f"[ERROR] Prompt file not found: {args.prompt_file}")
        return

    with open(args.prompt_file, "r", encoding="utf-8") as f:
        modification_prompt = f.read().strip()

    if not modification_prompt:
        print(f"[ERROR] The prompt file '{args.prompt_file}' is empty.")
        return

    modify_and_fix_rtl(
        source_file=args.rtl_file,
        modification_prompt=modification_prompt,
        max_iterations=args.max_iterations
    )

if __name__ == "__main__":
    main()