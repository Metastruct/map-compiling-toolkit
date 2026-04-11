from __future__ import annotations

import os
from functools import wraps
from pathlib import Path

import colorama

from helper import BuildError, read_version_file, set_readonly, write_version_file


colorama.init(autoreset=True)


def stage(name: str):
    def decorator(function):
        @wraps(function)
        def wrapper(*args, **kwargs):
            print()
            print(
                colorama.Style.BRIGHT
                + colorama.Fore.YELLOW
                + "======== stage: "
                + colorama.Style.BRIGHT
                + colorama.Fore.CYAN
                + name
                + colorama.Style.BRIGHT
                + colorama.Fore.YELLOW
                + " ========="
            )
            return function(*args, **kwargs)

        return wrapper

    return decorator


def check_paths(env: dict[str, str]) -> None:
    essentials = [
        env["sourcesdk"],
        env["GameExeDir"],
        os.path.join(env["GameExeDir"], "bin"),
        os.path.join(env["GameDir"], "addons"),
        os.path.join(env["GameDir"], "maps"),
        env["mapdata"],
        os.path.join(env["sourcesdk"], "bin"),
        os.path.join(env["sourcesdk"], "bin", "hammer.exe"),
        os.path.join(env["VProject"], "gameinfo.txt"),
        env["VProject"],
        env["version_file"],
        env["SteamPath"],
    ]
    for path in essentials:
        if not Path(path).exists():
            raise BuildError("missing path", {"path": path})


def next_build_version(version_file: Path, delta: int) -> int:
    version = read_version_file(version_file)
    next_version = version + delta
    set_readonly(version_file, False)
    write_version_file(version_file, next_version)
    set_readonly(version_file, True)
    return next_version
