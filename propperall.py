from __future__ import annotations

import os
import re
import shutil
import structlog
import subprocess
from pathlib import Path

from helper import run

LOGGER = structlog.get_logger()


def run_propper(
    propper_exe: Path,
    game_dir: Path,
    vmf_path: Path,
    vmf_log: Path,
    version_variable: str,
) -> None:
    with open(vmf_log, "w") as log_file:
        subprocess.run(
            [str(propper_exe), "-game", str(game_dir), str(vmf_path)],
            stdout=log_file,
            stderr=subprocess.STDOUT,
        )
        log_file.write(f'\n"mapversion" "{version_variable}"')
    #LOGGER.info("propper.executed", path=str(vmf_path))


def process_vmf_file(
    vmf_path: Path,
    vmf_log: Path,
    propper_exe: Path,
    game_dir: Path,
) -> bool:
    with open(vmf_path) as vmf_file:
        vmf_content = vmf_file.read()

    versioninfo_match = re.search(r"versioninfo\s+{([^}]+)}", vmf_content, re.DOTALL)
    if not versioninfo_match:
        LOGGER.warning("propper.no_versioninfo", path=str(vmf_path))
        return False

    versioninfo_block = versioninfo_match.group(1)
    version_match = re.search(r'"mapversion"\s+"([^"]+)"', versioninfo_block)
    if not version_match:
        LOGGER.warning("propper.no_mapversion", path=str(vmf_path))
        return False

    version_variable = version_match.group(1)
    LOGGER.debug("propper.found_version", path=str(vmf_path), version=version_variable)

    if vmf_log.exists():
        with open(vmf_log) as log_file:
            log_content = log_file.read()
        log_version_match = re.search(r'"mapversion"\s+"([^"]+)"', log_content)
        if log_version_match and log_version_match.group(1) == version_variable:
            LOGGER.info("propper.skipped", path=str(vmf_path), version=version_variable)
            return False

    LOGGER.info("propper.compiling", path=str(vmf_path), version=version_variable)
    run_propper(propper_exe, game_dir, vmf_path, vmf_log, version_variable)
    return True


def compile_with_propper(
    propper_dir: Path,
    game_dir: Path,
    mapdata_dir: Path,
) -> int:
    propper_storage = propper_dir / "propper"
    propper_exe = (
        Path(__file__).parent / "extras" / "propper" / "bin" / "vbsp_propper.exe"
    )

    if not propper_exe.exists():
        raise FileNotFoundError(f"vbsp_propper.exe not found at {propper_exe}")

    propper_storage.mkdir(parents=True, exist_ok=True)

    vmf_files = list(propper_storage.glob("*.vmf"))
    if not vmf_files:
        LOGGER.info("propper.no_files", path=str(propper_storage))
        return 0

    compiled = 0
    for vmf_path in vmf_files:
        vmf_log = vmf_path.with_suffix(".vmf.log")
        if process_vmf_file(vmf_path, vmf_log, propper_exe, game_dir):
            compiled += 1

    LOGGER.info("propper.summary", compiled=compiled, total=len(vmf_files))

    for src, dst in [
        (
            game_dir / "materials" / "models" / "mspropp",
            mapdata_dir / "materials" / "models" / "mspropp",
        ),
        (
            game_dir / "models" / "props" / "metastruct",
            mapdata_dir / "models" / "props" / "metastruct",
        ),
    ]:
        if src.exists():
            shutil.copytree(src, dst, dirs_exist_ok=True)
            LOGGER.info("propper.copied", src=str(src), dst=str(dst))

    return compiled


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Run Propper compiler")
    parser.add_argument(
        "--propper-dir", required=True, help="Propper directory containing .vmf files"
    )
    parser.add_argument("--game-dir", required=True, help="Game directory")
    parser.add_argument(
        "--mapdata-dir", required=True, help="Mapdata directory for output"
    )
    args = parser.parse_args()

    compile_with_propper(
        Path(args.propper_dir),
        Path(args.game_dir),
        Path(args.mapdata_dir),
    )
