#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
import structlog
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
EXTRAS_ROOT = Path(__file__).resolve().parent

from helper import BuildError, expand_value, load_config, run

LOGGER = structlog.get_logger()

COPY_MAP = {
    "build_cubemaps.lua": "lua/autorun/client/build_cubemaps.lua",
    "trigger_extract.lua": "lua/autorun/server/trigger_extract.lua",
    "gmodcommander.cfg": "cfg/gmodcommander.cfg",
    "mapcomp_write_missing.lua": "lua/autorun/client/mapcomp_write_missing.lua",
    "navmesh.lua": "lua/autorun/server/navmesh.lua",
    "landmark.lua": "lua/includes/modules/landmark.lua",
    "map_manipulation_tool_api.lua": "lua/includes/modules/map_manipulation_tool_api.lua",
    "bsprezip.lua": "lua/autorun/client/bsprezip.lua",
    "gmodcommander_launch.lua": "lua/autorun/client/gmodcommander_launch.lua",
}

TASKS = {
    "missing": {
        "name": "writemissing",
        "extra_args": [],
    },
    "trigger_extract": {
        "name": "trigger_extract",
        "extra_args": [],
    },
    "bsprezip": {
        "name": "bsprezip",
        "extra_args": [],
    },
    "cubemaps_ldr": {
        "name": "cubemaps",
        "extra_args": ["+sv_cheats", "1", "+mat_hdr_level", "0", "+mat_specular", "0"],
    },
    "cubemaps_hdr": {
        "name": "cubemaps",
        "extra_args": ["+sv_cheats", "1", "+mat_hdr_level", "2", "+mat_specular", "0"],
    },
    "navmesh": {
        "name": "navmesh",
        "extra_args": [],
    },
    "launch": {
        "name": "launch",
        "extra_args": [
            "+sv_noclipspeed",
            "25",
            "+mat_hdr_level",
            "2",
            "+mat_specular",
            "1",
            "+sv_cheats",
            "1",
            "-dev",
            "2",
            "+developer",
            "2",
        ],
    },
}


def configure_logging() -> None:
    structlog.configure(
        processors=[
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.KeyValueRenderer(
                key_order=["timestamp", "level", "event"]
            ),
        ],
        logger_factory=structlog.PrintLoggerFactory(),
    )


def ensure_destination(dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)


def copy_files_to_game(game_dir: Path) -> None:
    for filename, relative_dest in COPY_MAP.items():
        source = EXTRAS_ROOT / filename
        if not source.exists():
            raise BuildError(
                f"missing source file for gmodcommander: {filename}",
                {"path": str(source)},
            )
        destination = game_dir / relative_dest
        ensure_destination(destination)
        shutil.copy2(source, destination)
        LOGGER.debug("copied", source=str(source), destination=str(destination))


def find_game_exe(game_exe_dir: Path) -> Path:
    candidate = game_exe_dir / "bin" / "win64" / "gmod.exe"
    if candidate.exists():
        return candidate
    candidate = game_exe_dir / "gmod.exe"
    if candidate.exists():
        return candidate
    raise BuildError(
        "Could not locate gmod.exe",
        {
            "searched": [
                str(game_exe_dir / "bin" / "win64" / "gmod.exe"),
                str(game_exe_dir / "gmod.exe"),
            ]
        },
    )


def build_gmod_command(
    game_exe: Path, game_dir: Path, task: str, mapname: str
) -> list[str]:
    task_spec = TASKS.get(task)
    if task_spec is None:
        raise BuildError("Unknown gmodcommander task", {"task": task})

    args = [
        str(game_exe),
        "-game",
        str(game_dir),
        "-multirun",
        "-console",
        "-disableluarefresh",
        "-w",
        "1024",
        "-h",
        "1024",
        "-noworkshop",
        "-nosound",
        "-nojoy",
        "-nop4",
        "-windowed",
        "-insecure",
        "-nohltv",
        "-condebug",
        "-toconsole",
        "+map",
        mapname,
    ]

    if task_spec["extra_args"]:
        args.extend(task_spec["extra_args"])

    args.extend(
        [
            "+exec",
            "gmodcommander",
            "+con_nprint_bgalpha",
            str(task_spec["name"]),
        ]
    )
    return args


def run_task(task: str, mapname: str, env: dict[str, str]) -> None:
    game_dir = Path(expand_value(env["GameDir"], env))
    game_exe_dir = Path(expand_value(env["GameExeDir"], env))
    if not game_dir.exists() or not game_dir.is_dir():
        raise BuildError(
            "GameDir does not exist or is not a directory", {"path": str(game_dir)}
        )
    copy_files_to_game(game_dir)
    game_exe = find_game_exe(game_exe_dir)
    LOGGER.info(
        "gmodcommander:RUN",
        task=task,
        mapname=mapname,
        game_exe=str(game_exe),
        game_dir=str(game_dir),
    )
    run(
        build_gmod_command(game_exe, game_dir, task, mapname),
        cwd=game_exe.parent,
        env=env,
        check=True,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Python replacement for extras/gmodcommander.cmd"
    )
    parser.add_argument("task", choices=sorted(TASKS), help="gmodcommander task to run")
    parser.add_argument("mapname", help="map name to operate on")
    parser.add_argument(
        "--config",
        default=str(PROJECT_ROOT / "config.toml"),
        help="path to config.toml",
    )
    return parser.parse_args()


def main() -> int:
    configure_logging()
    args = parse_args()
    config = load_config(Path(args.config))
    process_env = os.environ.copy()
    process_env.update(config)
    try:
        run_task(args.task, args.mapname, process_env)
        LOGGER.info("task.complete", task=args.task, mapname=args.mapname)
        return 0
    except BuildError as exc:
        LOGGER.error(
            "task.failed",
            task=args.task,
            mapname=args.mapname,
            error=str(exc),
            details=exc.details,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
