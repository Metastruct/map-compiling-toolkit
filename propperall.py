import os
import subprocess
import re
import shutil
from concurrent.futures import ThreadPoolExecutor

def process_vmf_file(vmf_path, vmf_log, propper_exe, game_dir):
    with open(vmf_path, 'r') as vmf_file:
        vmf_content = vmf_file.read()
    versioninfo_match = re.search(r'versioninfo\s+{([^}]+)}', vmf_content, re.DOTALL)
    
    if not versioninfo_match:
        print(f"No versioninfo block found in '{os.path.basename(vmf_path)}'?.")
        return
    
    versioninfo_block = versioninfo_match.group(1)
    version_match = re.search(r'"mapversion"\s+"([^"]+)"', versioninfo_block)

    if not version_match:
        print(f"No mapversion variable found in '{os.path.basename(vmf_path)}'?.")
        return

    version_variable = version_match.group(1)
    print(f"Found mapversion: {version_variable}")

    if not os.path.exists(vmf_log):
        print(f"No log file found for '{os.path.basename(vmf_path)}'. Running Propper for the first time.")
        run_propper(propper_exe, game_dir, vmf_path, vmf_log, version_variable)
        return

    with open(vmf_log, 'r') as log_file:
        log_content = log_file.read()

    log_version_match = re.search(r'"mapversion"\s+"([^"]+)"', log_content)
    
    if log_version_match and log_version_match.group(1) == version_variable:
        print(f"'{version_variable}', Skipping Propper execution.")
        return

    print(f"Running Propper for '{os.path.basename(vmf_path)}' due to version mismatch or missing log version.")
    run_propper(propper_exe, game_dir, vmf_path, vmf_log, version_variable)

def run_propper(propper_exe, game_dir, vmf_path, vmf_log, version_variable):
    with open(vmf_log, 'w') as log_file:
        subprocess.run([propper_exe, '-game', game_dir, vmf_path], stdout=log_file, stderr=subprocess.STDOUT)
        log_file.write(f'\n"mapversion" "{version_variable}"')
    print(f"Propper executed for '{os.path.basename(vmf_path)}'.")

def compile_with_propper(map_folder, map_name, game_dir):
    script_dir = os.path.dirname(__file__)
    propper_dir = os.path.join(script_dir, 'extras', 'propper', 'bin')
    propper_exe = os.path.join(propper_dir, 'vbsp_propper.exe')
    propper_storage = os.path.join(map_folder, 'propper')
    propper_target = map_folder

    os.makedirs(propper_storage, exist_ok=True)
    os.chdir(propper_storage)

    vmf_files = []
    for root, dirs, files in os.walk(propper_storage):
        for file in files:
            if file.endswith('.vmf'):
                vmf_path = os.path.join(root, file)
                vmf_log = os.path.join(root, f'{file}.log')
                vmf_files.append((vmf_path, vmf_log, propper_exe, game_dir))

    with ThreadPoolExecutor() as executor:
        executor.map(lambda args: process_vmf_file(*args), vmf_files)

    print("====== Copying files also for hammer usage =======")
    materials_src = os.path.join(game_dir, 'materials', 'models', 'mspropp')
    materials_dest = os.path.join(propper_target, 'materials', 'models', 'mspropp')
    models_src = os.path.join(game_dir, 'models', 'props', 'metastruct')
    models_dest = os.path.join(propper_target, 'models', 'props', 'metastruct')

    shutil.move(materials_src, materials_dest)
    shutil.move(models_src, models_dest)

    print("=======================")
    print("======= FINISHED =======")
    print("=======================")
    input("Press ENTER to continue.")

def read_user_config():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    user_config_file = os.path.join(script_dir, 'user_config.cmd')

    if not os.path.isfile(user_config_file):
        print("ERROR: user_config.cmd file not found.")
        return None, None, None

    with open(user_config_file, 'r') as file:
        content = file.read()

    map_folder_match = re.search(r'@set mapfolder=(.*)', content, re.IGNORECASE)
    map_name_match = re.search(r'@set mapname=(.*)', content, re.IGNORECASE)
    game_dir_match = re.search(r'@set GameDir=(.*)', content, re.IGNORECASE)

    if not (map_folder_match and map_name_match and game_dir_match):
        print("ERROR: Invalid user_config.cmd file.")
        return None, None, None

    map_folder = map_folder_match.group(1).strip()
    map_name = map_name_match.group(1).strip()
    game_dir = game_dir_match.group(1).strip()

    return map_folder, map_name, game_dir

# Read values from user_config.cmd
map_folder, map_name, game_dir = read_user_config()

# Ensure all values are valid
if map_folder and map_name and game_dir:
    compile_with_propper(map_folder, map_name, game_dir)
else:
    print("Unable to retrieve required values from user_config.cmd.")
