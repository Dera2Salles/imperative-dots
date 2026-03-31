import os
import sys
import json
import shutil
import argparse

def sync_matugen(input_dir, output_dir):
    if not os.path.isdir(input_dir):
        print(f"Error: Input directory '{input_dir}' not found.")
        sys.exit(1)

    os.makedirs(output_dir, exist_ok=True)

    for item in os.listdir(input_dir):
        # Ignore the NixOS specific files like default.nix
        if item.endswith(".nix"):
            continue

        src_path = os.path.join(input_dir, item)
        dst_path = os.path.join(output_dir, item)

        if os.path.isdir(src_path):
            shutil.copytree(src_path, dst_path, dirs_exist_ok=True)
        else:
            shutil.copy2(src_path, dst_path)

    print(f"✅ Successfully copied Matugen configs to: {output_dir}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Copy Matugen configs ignoring nix files")
    parser.add_argument("--config", "-c", default="config.json", help="Path to the JSON configuration file")
    
    args = parser.parse_args()
    
    try:
        with open(args.config, 'r') as f:
            config_data = json.load(f)
            
        script_vars = config_data.get("matugen_conf", {})
        raw_input_dir = script_vars.get("input_dir")
        raw_output_dir = script_vars.get("output_dir")
        
        if not raw_input_dir or not raw_output_dir:
             print(f"Error: 'input_dir' or 'output_dir' missing from 'matugen_conf' section in {args.config}")
             sys.exit(1)
             
        input_dir = os.path.expanduser(raw_input_dir)
        output_dir = os.path.expanduser(raw_output_dir)
        
        print(f"Copying Matugen configs from: {input_dir}")
        sync_matugen(input_dir, output_dir)
        
    except FileNotFoundError:
        print(f"Error: Configuration file '{args.config}' not found.")
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"Error: '{args.config}' is not a valid JSON file.")
        sys.exit(1)
