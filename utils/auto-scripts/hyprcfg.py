import os
import re
import sys
import json

def get_credit_header():
    return """# --------------------------------------------------------------------------------------
#
#    ██╗██╗  ██╗   ██╗ █████╗ ███╗   ███╗██╗██████╗  ██████╗ 
#    ██║██║  ╚██╗ ██╔╝██╔══██╗████╗ ████║██║██╔══██╗██╔═══██╗
#    ██║██║   ╚████╔╝ ███████║██╔████╔██║██║██████╔╝██║   ██║
#    ██║██║    ╚██╔╝  ██╔══██║██║╚██╔╝██║██║██╔══██╗██║   ██║
#    ██║███████╗██║   ██║  ██║██║ ╚═╝ ██║██║██║  ██║╚██████╔╝
#    ╚═╝╚══════╝╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═╝ ╚═════╝ 
#
#    Created by ilyamiro
#    https://github.com/ilyamiro/nixos-configuration
#
# --------------------------------------------------------------------------------------
"""

def get_section_header(title):
    bar = "━" * 86
    return f"\n# {bar}\n#  ◈ {title.upper()}\n# {bar}\n"

def get_section_name(key):
    """Categorizes top-level Nix keys into clean Hyprland sections."""
    k = key.lower()
    if 'monitor' in k: return "Monitors"
    if 'exec' in k: return "Autostart"
    if 'bind' in k or 'gesture' in k: return "Keybindings"
    if 'rule' in k: return "Window & Layer Rules"
    return "Settings"

def parse_nix_configs(nix_dir, output_dir):
    # Dictionaries to aggregate categorized configurations across ALL files
    hyprland_sections = {
        "Monitors": [],
        "Environment Variables": [],
        "Autostart": [],
        "Core Variables": [],
        "Settings": [],
        "Window & Layer Rules": [],
        "Keybindings": [],
        "Misc": []
    }
    hypridle_lines = []

    # Regex definitions for parsing Nix syntax
    re_env = re.compile(r'home\.sessionVariables\.([A-Z_]+)\s*=\s*"([^"]+)";')
    re_list_start_quote = re.compile(r'"([^"]+)"\s*=\s*\[')
    re_list_start = re.compile(r'([a-zA-Z0-9_]+)\s*=\s*\[')
    re_dict_start = re.compile(r'([a-zA-Z0-9_]+)\s*=\s*\{')
    
    # Matching specific key-value pairs
    re_var_str = re.compile(r'"(\$[a-zA-Z0-9_]+)"\s*=\s*"([^"]+)";')
    re_key_str = re.compile(r'([a-zA-Z0-9_]+)\s*=\s*"([^"]+)";')
    re_key_val = re.compile(r'([a-zA-Z0-9_]+)\s*=\s*([^;]+);')

    if not os.path.isdir(nix_dir):
        print(f"Error: Input directory '{nix_dir}' not found.")
        sys.exit(1)

    files_to_parse = [f for f in os.listdir(nix_dir) if f.endswith('.nix')]

    for filename in files_to_parse:
        filepath = os.path.join(nix_dir, filename)
        with open(filepath, 'r') as f:
            lines = f.readlines()

        # State machine variables per file
        in_hyprland = False
        in_hypridle = False
        in_hypridle_listener = False
        list_key = None
        dict_depth = 0
        skip_packages = False
        current_section = "Settings"

        for raw_line in lines:
            line = raw_line.strip()
            indent = "    " * dict_depth

            # Skip empty lines but keep comments if inside settings
            if not line:
                continue
            
            # Global Environment Variables (Can be defined anywhere in Home Manager)
            match_env = re_env.search(line)
            if match_env:
                hyprland_sections["Environment Variables"].append(f"env = {match_env.group(1)},{match_env.group(2)}")
                continue
                
            if line.startswith('#'):
                if in_hyprland:
                    hyprland_sections[current_section].append(indent + line)
                elif in_hypridle:
                    hypridle_lines.append(indent + line)
                continue

            # Skip the package block in default.nix
            if 'home.packages = with pkgs;' in line:
                skip_packages = True
                continue
            if skip_packages:
                if line == '];':
                    skip_packages = False
                continue

            # -----------------------------
            # Hypridle Parsing Logic
            # -----------------------------
            if 'services.hypridle' in line:
                in_hypridle = True
                continue

            if in_hypridle:
                if 'settings = {' in line or 'enable = true;' in line:
                    continue

                if 'listener = [' in line:
                    in_hypridle_listener = True
                    continue

                if in_hypridle_listener:
                    if line == '];':
                        in_hypridle_listener = False
                        continue
                    if line == '{':
                        hypridle_lines.append("listener {")
                        dict_depth += 1
                        continue
                    elif line == '}' or line == '};':
                        dict_depth -= 1
                        hypridle_lines.append("}")
                        hypridle_lines.append("") # Add spacing
                        continue
                    
                    match_str = re_key_str.search(line)
                    if match_str:
                        hypridle_lines.append(f"    {match_str.group(1)} = {match_str.group(2)}")
                        continue
                    match_val = re_key_val.search(line)
                    if match_val:
                        hypridle_lines.append(f"    {match_val.group(1)} = {match_val.group(2)}")
                        continue
                    continue

                if 'general = {' in line:
                    hypridle_lines.append("general {")
                    dict_depth += 1
                    continue

                if line == '};' or line == '}':
                    if dict_depth > 0:
                        dict_depth -= 1
                        hypridle_lines.append(indent[:-4] + "}")
                        hypridle_lines.append("") # Add spacing
                    else:
                        in_hypridle = False
                    continue

                match_str = re_key_str.search(line)
                if match_str:
                    hypridle_lines.append(f"{indent}{match_str.group(1)} = {match_str.group(2)}")
                    continue
                match_val = re_key_val.search(line)
                if match_val:
                    hypridle_lines.append(f"{indent}{match_val.group(1)} = {match_val.group(2)}")
                    continue

            # -----------------------------
            # Hyprland Parsing Logic
            # -----------------------------
            if 'wayland.windowManager.hyprland.settings' in line:
                in_hyprland = True
                continue

            if in_hyprland:
                # Handle scope closures
                if line == '};':
                    if dict_depth > 0:
                        dict_depth -= 1
                        hyprland_sections[current_section].append(indent[:-4] + "}")
                        if dict_depth == 0:
                             hyprland_sections[current_section].append("") # Spacing after blocks
                    else:
                        in_hyprland = False
                    continue

                if line == '];':
                    list_key = None
                    hyprland_sections[current_section].append("") 
                    continue

                # Dictionary start (e.g., general = { )
                match_dict = re_dict_start.search(line)
                if match_dict:
                    key = match_dict.group(1)
                    if dict_depth == 0:
                        current_section = get_section_name(key)
                    hyprland_sections[current_section].append(f"{indent}{key} {{")
                    dict_depth += 1
                    continue

                # List start (e.g., bind = [ or "exec-once" = [ )
                match_list_q = re_list_start_quote.search(line)
                if match_list_q:
                    key = match_list_q.group(1)
                    if dict_depth == 0:
                        current_section = get_section_name(key)
                    list_key = key
                    continue
                    
                match_list = re_list_start.search(line)
                if match_list:
                    key = match_list.group(1)
                    if dict_depth == 0:
                        current_section = get_section_name(key)
                    list_key = key
                    continue

                # Inside List parsing
                if list_key:
                    val = line
                    # Strip Nix quotes around strings
                    if val.startswith('"') and val.endswith('"'):
                        val = val[1:-1]
                        val = val.replace('\\"', '"') # Restore internal quotes
                    
                    # Convert Nix file reference variables to static paths
                    val = val.replace('${./scripts/volume_listener.sh}', '~/.config/hypr/scripts/volume_listener.sh')
                    hyprland_sections[current_section].append(f"{indent}{list_key} = {val}")
                    continue

                # Core Variables ($mainMod)
                match_var = re_var_str.search(line)
                if match_var:
                    hyprland_sections["Core Variables"].append(f"{indent}{match_var.group(1)} = {match_var.group(2)}")
                    continue

                match_str = re_key_str.search(line)
                if match_str:
                    hyprland_sections[current_section].append(f"{indent}{match_str.group(1)} = {match_str.group(2)}")
                    continue

                match_val = re_key_val.search(line)
                if match_val:
                    hyprland_sections[current_section].append(f"{indent}{match_val.group(1)} = {match_val.group(2)}")
                    continue

    # ==========================================
    # File Construction & Writing
    # ==========================================
    os.makedirs(output_dir, exist_ok=True)
    
    # 1. Build Hyprland Conf
    hyprland_out_content = [get_credit_header()]
    
    # Define the professional ordering of sections
    section_order = [
        "Monitors",
        "Environment Variables",
        "Autostart",
        "Core Variables",
        "Settings",
        "Window & Layer Rules",
        "Keybindings",
        "Misc"
    ]

    for sec in section_order:
        if hyprland_sections.get(sec):
            hyprland_out_content.append(get_section_header(sec))
            hyprland_out_content.extend(hyprland_sections[sec])
            
    hyprland_out_path = os.path.join(output_dir, "hyprland.conf")
    with open(hyprland_out_path, "w") as f:
        f.write("\n".join(hyprland_out_content) + "\n")
        
    # 2. Build Hypridle Conf
    if hypridle_lines:
        hypridle_out_content = [get_credit_header()]
        hypridle_out_content.append(get_section_header("Hypridle Configuration"))
        hypridle_out_content.extend(hypridle_lines)
        
        hypridle_out_path = os.path.join(output_dir, "hypridle.conf")
        with open(hypridle_out_path, "w") as f:
            f.write("\n".join(hypridle_out_content) + "\n")

    print(f"✅ Successfully generated structured configs in: {output_dir}")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Convert Nix Hyprland configs to native .conf files")
    parser.add_argument("--config", "-c", default="config.json", help="Path to the JSON configuration file")
    
    args = parser.parse_args()
    
    try:
        with open(args.config, 'r') as f:
            config_data = json.load(f)
            
        script_vars = config_data.get("generate_conf", {})
        raw_input_dir = script_vars.get("input_dir")
        raw_output_dir = script_vars.get("output_dir")
        
        if not raw_input_dir or not raw_output_dir:
             print(f"Error: 'input_dir' or 'output_dir' missing from 'generate_conf' section in {args.config}")
             sys.exit(1)
             
        input_dir = os.path.expanduser(raw_input_dir)
        output_dir = os.path.expanduser(raw_output_dir)
        
        print(f"Reading configs from: {input_dir}")
        parse_nix_configs(input_dir, output_dir)
        
    except FileNotFoundError:
        print(f"Error: Configuration file '{args.config}' not found.")
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"Error: '{args.config}' is not a valid JSON file.")
        sys.exit(1)
