from __future__ import annotations

import argparse
import os
from pathlib import Path

import colorama
import structlog

from helper import (
    BuildError,
    copy_optional,
    copy_required,
    configure_logging,
    copy_tree,
    ensure_directory,
    expand_value,
    get_logger,
    load_config,
    remove_path,
    run,
)

colorama.init(autoreset=True)
LOGGER = get_logger()


def load_publish_env(root: Path, config_file: Path) -> dict[str, str]:
    raw = load_config(config_file)
    return {key: expand_value(value, raw) for key, value in raw.items()}


def validate_env(env: dict[str, str]) -> None:
    required = [
        "mapfolder",
        "mapfile",
        "mapname",
        "GameDir",
        "GameExeDir",
        "mapwsid",
    ]
    missing = [name for name in required if name not in env or not env[name].strip()]
    if missing:
        raise BuildError("Missing required config values", {"missing": missing})


def publish_map(root: Path, env: dict[str, str]) -> None:
    target_tmp = Path(env["mapfolder"]) / f"{env['mapfile']}.temp.delme"
    sourcepath = Path(env["mapfolder"]) / env["mapfile"]
    bspzip_gma_path = Path(env["GameDir"]) / "maps" / env["mapname"]
    gma_path = Path(env["mapfolder"]) / f"{env['mapfile']}.gma"
    game_bsp = Path(env["GameDir"]) / "maps" / f"{env['mapname']}.bsp"

    LOGGER.info("publish.start", mapname=env["mapname"], target=str(target_tmp))
    remove_path(target_tmp)
    ensure_directory(target_tmp)

    LOGGER.info("publish.copy_tree", source=str(bspzip_gma_path), destination=str(target_tmp))
    copy_tree(bspzip_gma_path, target_tmp)
    LOGGER.info("publish.copy_tree", source=str(sourcepath), destination=str(target_tmp))
    copy_tree(sourcepath, target_tmp)

    ensure_directory(target_tmp / "maps")
    copy_required(game_bsp, target_tmp / "maps" / game_bsp.name)

    if int(env.get("TRIGGER_STRIPPING_HACK_ENABLE", "0")) == 1:
        for suffix in ("_triggers.lmp", "_trigmesh.lmp"):
            source_file = Path(env["GameDir"]) / "maps" / f"{env['mapname']}{suffix}"
            copy_required(source_file, target_tmp / "maps" / source_file.name)

    graphs_source = Path(env["GameDir"]) / "maps" / "graphs" / f"{env['mapname']}.ain"
    if graphs_source.exists():
        ensure_directory(target_tmp / "maps" / "graphs")
        copy_required(graphs_source, target_tmp / "maps" / "graphs" / graphs_source.name)

    if int(env.get("DONT_PUBLISH_NAV", "0")) != 1:
        nav_source = Path(env["GameDir"]) / "maps" / f"{env['mapname']}.nav"
        copy_optional(nav_source, target_tmp / "maps" / nav_source.name)

    remove_path(gma_path)
    LOGGER.info("publish.create_gma", target=str(gma_path))
    run(
        [
            str(Path(env["GameExeDir"]) / "bin" / "gmad"),
            "create",
            "-folder",
            str(target_tmp),
            "-out",
            str(gma_path),
            "-warninvalid",
        ],
        cwd=root,
        env=os.environ.copy(),
        check=True,
    )

    if not gma_path.exists():
        raise BuildError("gma file was not created", {"path": str(gma_path)})

    source_jpg = Path(env["mapfolder"]) / f"{env['mapfile']}.jpg"
    if not source_jpg.exists():
        raise BuildError("missing source JPG", {"path": str(source_jpg)})

    if int(env.get("mapwsid", "0")) == 0:
        LOGGER.warning("publish.skipped", reason="mapwsid=0")
        return

    run(
        [
            str(Path(env["GameExeDir"]) / "bin" / "gmpublish"),
            "update",
            "-addon",
            str(gma_path),
            "-id",
            env["mapwsid"],
            "-changes",
            f"Publishing {env['mapname']}.bsp",
        ],
        cwd=root,
        env=os.environ.copy(),
        check=True,
    )
    LOGGER.info("publish.finished", gma=str(gma_path))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Publish a Garry's Mod map using project config")
    parser.add_argument("--root", default=Path(__file__).resolve().parent, help="project root directory")
    parser.add_argument("--config", default="config.toml", help="config.toml path relative to root")
    return parser.parse_args()


def main() -> int:
    configure_logging()
    args = parse_args()
    root = Path(args.root)
    config_path = root / args.config
    try:
        env = load_publish_env(root, config_path)
        validate_env(env)
        publish_map(root, env)
        return 0
    except BuildError as error:
        LOGGER.error("publish.failed", exc_info=True, details=getattr(error, "details", None))
        return 1
    except Exception:
        LOGGER.error("publish.unexpected", exc_info=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
