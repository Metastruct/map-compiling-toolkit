from __future__ import annotations

import argparse
import logging
import os
import shutil
import stat
import sys
from enum import Enum, auto
from functools import wraps
from pathlib import Path
from typing import Any

import colorama
import structlog

colorama.init(autoreset=True)
from extras.gmodcommander import run_task as run_gmodcommander_task
from commonconfig import check_paths, next_build_version, stage
from helper import (
    BuildError,
    copy_file,
    create_junction,
    configure_logging,
    expand_value,
    flash_console,
    load_config,
    open_shell,
    read_version_file,
    remove_path,
    run,
)
from helpers import (
    BuildContext,
    TempAddonJunction,
    assign_environment_value,
    dump_build_context,
    load_common_env,
)
import publish_map

LOGGER = structlog.get_logger()


class Task(Enum):
    BUILD = auto()
    REBUILD = auto()
    POSTPROCESS = auto()
    DUMP = auto()
    CLEANUP = auto()
    PUBLISH = auto()
    LEAKTEST = auto()
    PLAY = auto()


_TASK_ALIASES: dict[str, Task] = {
    "b": Task.BUILD,
    "build": Task.BUILD,
    "r": Task.REBUILD,
    "rebuild": Task.REBUILD,
    "p": Task.POSTPROCESS,
    "postprocess": Task.POSTPROCESS,
    "d": Task.DUMP,
    "dump": Task.DUMP,
    "cleanup": Task.CLEANUP,
    "publish": Task.PUBLISH,
    "l": Task.LEAKTEST,
    "leaktest": Task.LEAKTEST,
    "play": Task.PLAY,
    "t": Task.BUILD,
    "test": Task.BUILD,
}

_NEEDS_VERSION_FILE: set[Task] = {
    Task.POSTPROCESS,
    Task.DUMP,
    Task.CLEANUP,
    Task.PLAY,
    Task.PUBLISH,
    Task.LEAKTEST,
}

_TASK_HELP = "/".join(t.name.lower() for t in Task)


def prompt_task() -> tuple[Task, bool]:
    while True:
        print("\nTasks")
        print("   [B]uild")
        print("   [R]ebuild previous")
        print("   [P]ostprocess previous")
        print("   [D]ump build context")
        print("   [t]est build system")
        choice = input("Select task> ").strip().lower()
        if choice in _TASK_ALIASES:
            test_mode = choice == "t"
            return _TASK_ALIASES[choice], test_mode


def parse_command(raw_command: str | None) -> tuple[Task, bool]:
    if raw_command is None:
        return prompt_task()
    normalized = raw_command.lower()
    if normalized in _TASK_ALIASES:
        test_mode = normalized == "t"
        return _TASK_ALIASES[normalized], test_mode
    raise argparse.ArgumentTypeError("unknown command")


@stage("prepare_workspace")
def prepare_workspace(ctx: BuildContext) -> None:
    LOGGER.info("prepare.workspace", target=str(ctx.bspzip_gma_out))
    remove_path(ctx.bspzip_gma_out)
    ctx.bspzip_gma_out.mkdir(parents=True, exist_ok=True)
    junction = TempAddonJunction(ctx.bspzip_gma_out, ctx.maptoolkit_temp_addon)
    junction.link()
    ctx._temp_addon_junction = junction
    copy_file(ctx.mapfolder / f"{ctx.mapfile}.vmf", ctx.targetvmf)
    copy_file(ctx.mapfolder / f"{ctx.mapfile}.rad", ctx.targetrad, optional=True)
    copy_file(ctx.mapfolder / f"{ctx.mapfile}.vbsp", ctx.targetvbsp, optional=True)
    copy_file(
        ctx.mapfolder / "detail_custom.vbsp",
        ctx.vproject / "detail_custom.vbsp",
        optional=True,
    )
    copy_file(
        ctx.mapfolder / "detail.vbsp", ctx.vproject / "detail.vbsp", optional=True
    )


@stage("run_vmfii")
def run_vmfii(ctx: BuildContext) -> None:
    LOGGER.info("vmfii.start", target=str(ctx.targetvmf))
    log_path = ctx.mapfolder / f"{ctx.mapname}.log"
    with log_path.open("a", encoding="utf-8", errors="ignore") as handle:
        run(
            [
                str(ctx.vmfii),
                str(ctx.targetvmf),
                str(ctx.targetvmf),
                "--instancedir",
                str(ctx.mapfolder),
                "--fgd",
                ctx.env["FGDS"],
            ],
            cwd=ctx.root,
            env=ctx.process_env,
            check=True,
            stdout=handle,
            stderr=handle,
        )


@stage("run_trigger_strip")
def run_trigger_strip(ctx: BuildContext) -> None:
    if int(ctx.env.get("TRIGGER_STRIPPING_HACK_ENABLE", "0")) != 1:
        LOGGER.info("trigger_strip.skipped")
        return
    trigger_name = f"{ctx.mapname}_trigger"
    source = ctx.mapfolder / f"{trigger_name}.vmf"
    copy_file(ctx.targetvmf, source)
    run(
        ["vlts.exe", str(source), str(ctx.targetvmf)],
        cwd=ctx.root,
        env=ctx.process_env,
        check=True,
    )
    run(
        [
            str(ctx.compilers_dir / "vbsp.exe"),
            "-allowdynamicpropsasstatic",
            *ctx.env["VBSPEXTRAS"].split(),
            "-leaktest",
            "-low",
            str(ctx.mapfolder / trigger_name),
        ],
        cwd=ctx.root,
        env=ctx.process_env,
        check=True,
    )
    shutil.copy2(
        ctx.mapfolder / f"{trigger_name}.bsp",
        ctx.game_dir / "maps" / f"{trigger_name}.bsp",
    )
    run_gmodcommander_task("trigger_extract", trigger_name, ctx.process_env)
    copy_file(
        ctx.game_dir / "data" / "bspdata" / trigger_name / "triggers.json",
        ctx.game_dir / "maps" / f"{ctx.mapname}_triggers.lmp",
    )
    copy_file(
        ctx.game_dir / "data" / "bspdata" / trigger_name / "trigmesh.json",
        ctx.game_dir / "maps" / f"{ctx.mapname}_trigmesh.lmp",
    )


@stage("run_vbsp_vvis_vrad")
def run_vbsp_vvis_vrad(ctx: BuildContext) -> None:
    run(
        [
            str(ctx.compilers_dir / "vbsp.exe"),
            "-allowdynamicpropsasstatic",
            *ctx.env["VBSPEXTRAS"].split(),
            "-leaktest",
            "-low",
            str(ctx.mapfolder / ctx.mapname),
        ],
        cwd=ctx.root,
        env=ctx.process_env,
        check=True,
    )
    if int(ctx.env.get("TESTBUILD", "0")) != 1:
        run(
            [
                str(ctx.compilers_dir / "vvis.exe"),
                "-low",
                str(ctx.mapfolder / ctx.mapname),
            ],
            cwd=ctx.root,
            env=ctx.process_env,
            check=True,
        )
    if int(ctx.env.get("NOLDR", "0")) != 1:
        run(
            [
                str(ctx.compilers_dir / "vrad.exe"),
                "-low",
                *ctx.env["VRADLDR"].split(),
                "-noskyboxrecurse",
                "-ldr",
                str(ctx.mapfolder / ctx.mapname),
            ],
            cwd=ctx.root,
            env=ctx.process_env,
            check=True,
        )
    if int(ctx.env.get("TESTBUILD", "0")) != 1:
        run(
            [
                str(ctx.compilers_dir / "vrad.exe"),
                "-low",
                *ctx.env["VRADHDR"].split(),
                "-noskyboxrecurse",
                "-hdr",
                str(ctx.mapfolder / ctx.mapname),
            ],
            cwd=ctx.root,
            env=ctx.process_env,
            check=True,
        )


@stage("run_vbsp_only")
def run_vbsp_only(ctx: BuildContext) -> None:
    run(
        [
            str(ctx.compilers_dir / "vbsp.exe"),
            "-allowdynamicpropsasstatic",
            *ctx.env["VBSPEXTRAS"].split(),
            "-leaktest",
            "-low",
            str(ctx.mapfolder / ctx.mapname),
        ],
        cwd=ctx.root,
        env=ctx.process_env,
        check=True,
    )
    if Path(ctx.mapfolder / f"{ctx.mapname}.lin").exists():
        # map leaked
        raise BuildError(
            "leaktest failed: .lin file was generated",
            {"lin_file": str(ctx.mapfolder / f"{ctx.mapname}.lin")},
        )


@stage("run_leaktest")
def run_leaktest(ctx: BuildContext) -> None:
    prepare_workspace(ctx)
    run_vmfii(ctx)
    run_vbsp_only(ctx)


@stage("copy_bsp_to_game")
def copy_bsp_to_game(ctx: BuildContext) -> None:
    source = ctx.mapfolder / f"{ctx.mapname}.bsp"
    destination = ctx.game_dir / "maps" / f"{ctx.mapname}.bsp"
    copy_file(source, destination)


@stage("pack_required_files")
def pack_required_files(ctx: BuildContext) -> None:
    run(
        [
            str(ctx.reslister),
            "--format=bspzip",
            str(ctx.mapfolder / f"{ctx.mapname}.vmf"),
            str(ctx.mapdata),
            str(ctx.game_dir / "maps" / f"{ctx.mapname}.bsp.reslister"),
        ],
        cwd=ctx.root,
        env=ctx.process_env,
        check=True,
    )
    run(
        [
            sys.executable,
            str(ctx.zipsrc),
            "-addlist",
            str(ctx.game_dir / "maps" / f"{ctx.mapname}.bsp"),
            str(ctx.game_dir / "maps" / f"{ctx.mapname}.bsp.reslister"),
            str(ctx.game_dir / "maps" / f"{ctx.mapname}.bsp.new"),
        ],
        cwd=ctx.mapdata,
        env=ctx.process_env,
        check=True,
    )
    move_replace(
        ctx.game_dir / "maps" / f"{ctx.mapname}.bsp.new",
        ctx.game_dir / "maps" / f"{ctx.mapname}.bsp.newx",
        ctx.game_dir / "maps" / f"{ctx.mapname}.bsp",
    )


def move_replace(temp_path: Path, alt_path: Path, final_path: Path) -> None:
    if not temp_path.exists():
        raise BuildError("expected build artifact missing", {"path": str(temp_path)})
    if alt_path.exists():
        alt_path.unlink(missing_ok=True)
    temp_path.replace(alt_path)
    final_path.unlink(missing_ok=True)
    alt_path.replace(final_path)


@stage("pack_missing_materials")
def pack_missing_materials(ctx: BuildContext) -> None:
    if int(ctx.env.get("NO_MISSING_BUNDLING", "0")) == 1:
        LOGGER.info("missing_materials.skipped")
        return
    remove_path(ctx.game_dir / "data" / "mapoverrides")
    remove_path(ctx.game_dir / "data" / "addlist.txt")
    remove_path(ctx.game_dir / "data" / "addlist_src.txt")
    run_gmodcommander_task("missing", ctx.mapname, ctx.process_env)
    addlist = ctx.game_dir / "data" / "addlist.txt"
    if not addlist.exists():
        raise BuildError(
            "missing addlist produced by missing-materials step", {"path": str(addlist)}
        )
    run(
        [
            sys.executable,
            str(ctx.zipsrc),
            "-addlist",
            str(ctx.game_dir / "maps" / f"{ctx.mapname}.bsp"),
            str(addlist),
            str(ctx.game_dir / "maps" / f"{ctx.mapname}.bsp.new"),
        ],
        cwd=ctx.game_dir / "data",
        env=ctx.process_env,
        check=True,
    )
    move_replace(
        ctx.game_dir / "maps" / f"{ctx.mapname}.bsp.new",
        ctx.game_dir / "maps" / f"{ctx.mapname}.bsp.newx",
        ctx.game_dir / "maps" / f"{ctx.mapname}.bsp",
    )
    remove_path(ctx.game_dir / "data" / "mapoverrides")
    remove_path(ctx.game_dir / "data" / "addlist.txt")
    remove_path(ctx.game_dir / "data" / "addlist_src.txt")


@stage("pack_extra_bspzip")
def pack_extra_bspzip(ctx: BuildContext) -> None:
    source = ctx.mapfolder / f"{ctx.mapfile}.bspzip"
    if not source.exists():
        LOGGER.info("extra_bspzip.skipped", path=str(source))
        return
    run(
        [
            sys.executable,
            str(ctx.zipsrc),
            "-addlist",
            str(ctx.game_dir / "maps" / f"{ctx.mapname}.bsp"),
            str(source),
            str(ctx.game_dir / "maps" / f"{ctx.mapname}.bsp.new"),
        ],
        cwd=ctx.mapdata,
        env=ctx.process_env,
        check=True,
    )
    move_replace(
        ctx.game_dir / "maps" / f"{ctx.mapname}.bsp.new",
        ctx.game_dir / "maps" / f"{ctx.mapname}.bsp.newx",
        ctx.game_dir / "maps" / f"{ctx.mapname}.bsp",
    )


@stage("build_cubemaps")
def build_cubemaps(ctx: BuildContext) -> None:
    if int(ctx.env.get("NOLDR", "0")) != 1:
        try:
            run_gmodcommander_task("cubemaps_ldr", ctx.mapname, ctx.process_env)
        except BuildError:
            LOGGER.warning("ldr_cubemaps.failed", mapname=ctx.mapname)
    if int(ctx.env.get("NOHDR", "0")) != 1:
        try:
            run_gmodcommander_task("cubemaps_hdr", ctx.mapname, ctx.process_env)
        except BuildError:
            LOGGER.warning("hdr_cubemaps.failed", mapname=ctx.mapname)


@stage("repack_bsp_if_needed")
def repack_bsp_if_needed(ctx: BuildContext) -> None:
    if int(ctx.env.get("ENABLE_BSPREZIP", "0")) != 1:
        LOGGER.info("bsprezip.skipped")
        return
    copy_file(
        ctx.mapfolder / f"{ctx.mapname}.bsp",
        ctx.game_dir / "maps" / f"{ctx.mapname}_prezip.bsp",
    )
    run_gmodcommander_task("bsprezip", ctx.mapname, ctx.process_env)
    copy_file(
        ctx.game_dir / "data" / f"{ctx.mapname}.bsp.dat",
        ctx.game_dir / "maps" / f"{ctx.mapname}.bsp",
    )


@stage("generate_navmesh")
def generate_navmesh(ctx: BuildContext) -> None:
    seed_file = ctx.mapfolder / f"{ctx.mapfile}.lm.txt"
    if not seed_file.exists():
        LOGGER.info("navmesh.seed_missing", path=str(seed_file))
        return
    copy_file(seed_file, ctx.game_dir / "data" / "navmesh_landmarks.txt")
    run_gmodcommander_task("navmesh", ctx.mapname, ctx.process_env)
    target_nav = ctx.game_dir / "maps" / f"{ctx.mapname}.nav"
    if not target_nav.exists() or target_nav.stat().st_size == 0:
        LOGGER.warning(
            "navmesh.failed",
            path=str(target_nav),
            size=target_nav.stat().st_size if target_nav.exists() else 0,
        )


@stage("launch_game")
def launch_game(ctx: BuildContext) -> None:
    if int(ctx.env.get("TESTBUILD", "0")) == 1:
        LOGGER.info("launch.skipped.testbuild")
        return
    flash_console()
    run_gmodcommander_task("launch", ctx.mapname, ctx.process_env)


@stage("maybe_git_prompt")
def maybe_git_prompt(ctx: BuildContext) -> None:
    if os.environ.get("NOCOMPILERCOMMIT") is not None:
        return
    status = run(
        [
            "git",
            "-C",
            str(ctx.mapfolder),
            "status",
            "--untracked-files=no",
            "-s",
        ],
        cwd=ctx.root,
        env=ctx.process_env,
        capture_output=True,
        check=False,
    )
    if status.stdout.strip():
        LOGGER.warning("git.dirty", output=status.stdout.strip())
        if sys.stdin.isatty():
            answer = input("Open shell in map folder? [Y/n] ").strip().lower()
            if answer in ("", "y", "yes"):
                open_shell(ctx.mapfolder)


def cleanup(ctx: BuildContext) -> None:
    if ctx._temp_addon_junction is not None:
        ctx._temp_addon_junction.teardown()
    else:
        remove_path(ctx.maptoolkit_temp_addon)


def run_build_workflow(ctx: BuildContext, prepare: bool) -> None:
    if prepare:
        prepare_workspace(ctx)
        run_vmfii(ctx)
        run_trigger_strip(ctx)
        run_vbsp_vvis_vrad(ctx)

    copy_bsp_to_game(ctx)
    pack_required_files(ctx)
    pack_missing_materials(ctx)
    pack_extra_bspzip(ctx)
    build_cubemaps(ctx)
    repack_bsp_if_needed(ctx)
    generate_navmesh(ctx)
    launch_game(ctx)
    maybe_git_prompt(ctx)


def run_build(ctx: BuildContext) -> None:
    run_build_workflow(ctx, prepare=True)


def run_postprocess(ctx: BuildContext) -> None:
    run_build_workflow(ctx, prepare=False)


def main() -> int:
    configure_logging()
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "command",
        nargs="?",
        help=_TASK_HELP,
    )
    parser.add_argument("--test", action="store_true", help="enable test build mode")
    args = parser.parse_args()
    try:
        task, test_mode = parse_command(args.command)
        if args.test:
            test_mode = True
        root = Path(__file__).resolve().parent
        base_env = load_common_env(root)
        check_paths(base_env)
        if task in _NEEDS_VERSION_FILE:
            version = read_version_file(Path(base_env["version_file"]))
        else:
            delta = 1 if task == Task.BUILD else 0
            version = next_build_version(Path(base_env["version_file"]), delta)
        env = load_common_env(root, build_version=version)
        env["TESTBUILD"] = "1" if test_mode else env.get("TESTBUILD", "0")
        if task == Task.DUMP:
            ctx = BuildContext(root, env)
            dump_build_context(ctx)
            return 0
        if task == Task.CLEANUP:
            ctx = BuildContext(root, env)
            cleanup(ctx)
            return 0
        if task == Task.PLAY:
            ctx = BuildContext(root, env)
            launch_game(ctx)
            return 0
        if task == Task.POSTPROCESS:
            ctx = BuildContext(root, env)
            run_postprocess(ctx)
            LOGGER.info("build.finished", task=task.name.lower(), version=version)
            return 0
        if task == Task.PUBLISH:
            publish_map.publish_map(root, env)
            LOGGER.info("publish.finished", task=task.name.lower(), version=version)
            return 0
        if task == Task.LEAKTEST:
            ctx = BuildContext(root, env)
            try:
                run_leaktest(ctx)
            except BuildError:
                LOGGER.info(
                    "leaktest.finished", task=task.name.lower(), version=version
                )
                print(colorama.Fore.RED + "LEAKTEST FAILED: .lin file was generated")
                print(f"File path to .lin: {ctx.mapfolder / f'{ctx.mapname}.lin'}")
                return 1
            LOGGER.info("leaktest.finished", task=task.name.lower(), version=version)
            return 0
        ctx = BuildContext(root, env)
        run_build(ctx)
        LOGGER.info("build.finished", task=task.name.lower(), version=version)
        return 0
    except BuildError as exc:
        LOGGER.error(
            "build.failed", exc_info=True, details=getattr(exc, "details", None)
        )
        return 1
    except Exception:
        LOGGER.error("build.unexpected", exc_info=True)
        return 1
    finally:
        try:
            if "ctx" in locals():
                cleanup(ctx)
        except Exception:
            LOGGER.warning("cleanup.failed", exc_info=True)


if __name__ == "__main__":
    raise SystemExit(main())
