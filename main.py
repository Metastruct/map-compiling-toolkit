from __future__ import annotations

import argparse
import logging
import os
import shutil
import stat
import sys
from dataclasses import dataclass
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
    copy_optional,
    copy_required,
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
import publish_map

LOGGER = structlog.get_logger()


@dataclass
class BuildContext:
    root: Path
    env: dict[str, str]

    def __post_init__(self) -> None:
        self.mapfolder = Path(self.env["mapfolder"])
        self.mapdata = Path(self.env["mapdata"])
        self.game_dir = Path(self.env["GameDir"])
        self.game_exe_dir = Path(self.env["GameExeDir"])
        self.vproject = Path(self.env["VProject"])
        self.vproject_hammer = Path(self.env["VProject_Hammer"])
        self.compilers_dir = Path(self.env["compilers_dir"])
        self.sourcesdk = Path(self.env["sourcesdk"])
        self.version_file = Path(self.env["version_file"])
        self.mapfile = self.env["mapfile"]
        self.mapname = self.env["mapname"]
        self.bspzip_gma_out = self.game_dir / "maps" / self.mapname
        self.maptoolkit_temp_addon = self.game_dir / "addons" / "maptoolkit_temp"
        self.targetvmf = self.mapfolder / f"{self.mapname}.vmf"
        self.targetrad = self.mapfolder / f"{self.mapname}.rad"
        self.targetvbsp = self.vproject / f"{self.mapfile}.vbsp"
        self.env["PATH"] = ";".join(
            [
                str(self.root),
                str(self.sourcesdk / "bin"),
                self.env["SteamPath"],
                os.environ.get("PATH", ""),
            ]
        )
        self.process_env = os.environ.copy()
        self.process_env.update(self.env)

    @property
    def zipsrc(self) -> Path:
        #TODO: use directly
        return self.root / "extras" / "gmazip.py"

    @property
    def reslister(self) -> Path:
        return self.root / "extras" / "reslister.exe"

    @property
    def vmfii(self) -> Path:
        return self.root / "extras" / "vmfii"

    @property
    def launch_game_cmd(self) -> Path:
        return self.root / "LAUNCH game.cmd"

    @property
    def root_cmd(self) -> str:
        return str(self.root)


def assign_environment_value(env: dict[str, str], user: dict[str, str], name: str, default: str) -> None:
    raw_value = expand_value(default, env)
    env[name] = expand_value(user.get(name, raw_value), env)


def load_common_env(root: Path, build_version: int | None = None) -> dict[str, str]:
    user = load_config(root / "config.toml")
    env: dict[str, str] = {}
    assign_environment_value(env, user, "SteamAppUser", "dummy")
    assign_environment_value(env, user, "HammerParams", "-nop4")
    assign_environment_value(env, user, "NOLDR", "0")
    assign_environment_value(env, user, "NOHDR", "0")
    assign_environment_value(env, user, "TRIGGER_STRIPPING_HACK_ENABLE", "0")
    assign_environment_value(env, user, "DONT_PUBLISH_NAV", "0")
    assign_environment_value(env, user, "ENABLE_BSPREZIP", "0")
    assign_environment_value(env, user, "prompt", "\x1b[32m$P$G\x1b[0m")
    assign_environment_value(env, user, "SteamUser", "%SteamAppUser%")
    assign_environment_value(env, user, "SteamPath", r"C:\Program Files (x86)\Steam")
    assign_environment_value(env, user, "SteamPathAlt", "%SteamPath%")
    assign_environment_value(env, user, "mapfolder", r"C:\metastruct\mapfiles")
    assign_environment_value(env, user, "version_file", r"%mapfolder%\ver_meta3.txt")
    if build_version is not None:
        env["BUILD_VERSION"] = str(build_version)
    elif "BUILD_VERSION" not in env:
        env["BUILD_VERSION"] = str(read_version_file(Path(expand_value(env["version_file"], env))))
    assign_environment_value(env, user, "mapfile", "metastruct_3")
    assign_environment_value(env, user, "mapname", "gm_construct_m_%BUILD_VERSION%")
    assign_environment_value(env, user, "mapdata", r"C:\metastruct\mapdata")
    assign_environment_value(env, user, "mapwsid", "0")
    assign_environment_value(env, user, "GCNOADDONS", "-noaddons")
    assign_environment_value(env, user, "NO_MISSING_BUNDLING", "0")
    assign_environment_value(env, user, "VBSPEXTRAS", "-notjunc -blocksize 2048")
    assign_environment_value(env, user, "VRADHDR", "-softsun 0 -bounce 1")
    assign_environment_value(env, user, "VRADLDR", "%VRADHDR%")
    assign_environment_value(env, user, "sourcesdk", r"%SteamPath%\steamapps\common\Source SDK Base 2013 Multiplayer")
    assign_environment_value(env, user, "FGDS", r"%sourcesdk%\bin\base.fgd,%sourcesdk%\bin\halflife2.fgd,%mapfolder%\metastruct.fgd")
    env["toolkit_root"] = str(root) + "\\"
    assign_environment_value(env, user, "VProject_Hammer", r"%toolkit_root%game_hammer\garrysmod")
    assign_environment_value(env, user, "VProject", r"%toolkit_root%game_compiling\garrysmod")
    assign_environment_value(env, user, "compilers_dir", r"%toolkit_root%game_compiling\bin\win64")
    if not Path(expand_value(env["VProject_Hammer"], env)).joinpath("gameinfo.txt").exists():
        env["VProject_Hammer"] = expand_value(env["VProject"], env)
    assign_environment_value(env, user, "GameDir", r"%SteamPath%\steamapps\common\GarrysMod\garrysmod")
    assign_environment_value(env, user, "GameExeDir", r"%SteamPath%\steamapps\common\GarrysMod")
    assign_environment_value(env, user, "ValvePlatformMutex", r"%SteamPath%\steam.exe")
    assign_environment_value(env, user, "PATH", r"%toolkit_root%;%sourcesdk%\bin;%SteamPath%;%PATH%")
    assign_environment_value(env, user, "SteamAppId", "4000")
    assign_environment_value(env, user, "SteamAppVersionId", "45")
    assign_environment_value(env, user, "SteamGameId", "211")
    assign_environment_value(env, user, "SteamGame", "garrysmod")
    return {k: expand_value(v, env) for k, v in env.items()}


def prompt_task() -> tuple[str, bool]:
    while True:
        print("\nTasks")
        print("   [B]uild")
        print("   [R]ebuild previous")
        print("   [P]ostprocess previous")
        print("   [D]ump build context")
        print("   [t]est build system")
        choice = input("Select task> ").strip().lower()
        if choice in ("b", "build"):
            return "build", False
        if choice in ("r", "rebuild"):
            return "rebuild", False
        if choice in ("p", "postprocess"):
            return "postprocess", False
        if choice in ("d", "dump"):
            return "dump", False
        if choice in ("t", "test"):
            return "build", True


@stage("prepare_workspace")
def prepare_workspace(ctx: BuildContext) -> None:
    LOGGER.info("prepare.workspace", target=str(ctx.bspzip_gma_out))
    remove_path(ctx.bspzip_gma_out)
    ctx.bspzip_gma_out.mkdir(parents=True, exist_ok=True)
    remove_path(ctx.maptoolkit_temp_addon)
    create_junction(ctx.bspzip_gma_out, ctx.maptoolkit_temp_addon)
    copy_required(ctx.mapfolder / f"{ctx.mapfile}.vmf", ctx.targetvmf)
    copy_optional(ctx.mapfolder / f"{ctx.mapfile}.rad", ctx.targetrad)
    copy_optional(ctx.mapfolder / f"{ctx.mapfile}.vbsp", ctx.targetvbsp)
    copy_optional(ctx.mapfolder / "detail_custom.vbsp", ctx.vproject / "detail_custom.vbsp")
    copy_optional(ctx.mapfolder / "detail.vbsp", ctx.vproject / "detail.vbsp")


@stage("run_vmfii")
def run_vmfii(ctx: BuildContext) -> None:
    LOGGER.info("vmfii.start", target=str(ctx.targetvmf))
    log_path = ctx.mapfolder / f"{ctx.mapname}.log"
    with log_path.open("a", encoding="utf-8", errors="ignore") as handle:
        run([
            str(ctx.vmfii),
            str(ctx.targetvmf),
            str(ctx.targetvmf),
            "--instancedir",
            str(ctx.mapfolder),
            "--fgd",
            ctx.env["FGDS"],
        ], cwd=ctx.root, env=ctx.process_env, check=True, stdout=handle, stderr=handle)


@stage("run_trigger_strip")
def run_trigger_strip(ctx: BuildContext) -> None:
    if int(ctx.env.get("TRIGGER_STRIPPING_HACK_ENABLE", "0")) != 1:
        LOGGER.info("trigger_strip.skipped")
        return
    trigger_name = f"{ctx.mapname}_trigger"
    source = ctx.mapfolder / f"{trigger_name}.vmf"
    copy_required(ctx.targetvmf, source)
    run(["vlts.exe", str(source), str(ctx.targetvmf)], cwd=ctx.root, env=ctx.process_env, check=True)
    run([
        str(ctx.compilers_dir / "vbsp.exe"),
        "-allowdynamicpropsasstatic",
        *ctx.env["VBSPEXTRAS"].split(),
        "-leaktest",
        "-low",
        str(ctx.mapfolder / trigger_name),
    ], cwd=ctx.root, env=ctx.process_env, check=True)
    shutil.copy2(
        ctx.mapfolder / f"{trigger_name}.bsp",
        ctx.game_dir / "maps" / f"{trigger_name}.bsp",
    )
    run_gmodcommander_task("trigger_extract", trigger_name, ctx.process_env)
    copy_required(ctx.game_dir / "data" / "bspdata" / trigger_name / "triggers.json", ctx.game_dir / "maps" / f"{ctx.mapname}_triggers.lmp")
    copy_required(ctx.game_dir / "data" / "bspdata" / trigger_name / "trigmesh.json", ctx.game_dir / "maps" / f"{ctx.mapname}_trigmesh.lmp")


@stage("run_vbsp_vvis_vrad")
def run_vbsp_vvis_vrad(ctx: BuildContext) -> None:
    run([
        str(ctx.compilers_dir / "vbsp.exe"),
        "-allowdynamicpropsasstatic",
        *ctx.env["VBSPEXTRAS"].split(),
        "-leaktest",
        "-low",
        str(ctx.mapfolder / ctx.mapname),
    ], cwd=ctx.root, env=ctx.process_env, check=True)
    if int(ctx.env.get("TESTBUILD", "0")) != 1:
        run([
            str(ctx.compilers_dir / "vvis.exe"),
            "-low",
            str(ctx.mapfolder / ctx.mapname),
        ], cwd=ctx.root, env=ctx.process_env, check=True)
    if int(ctx.env.get("NOLDR", "0")) != 1:
        run([
            str(ctx.compilers_dir / "vrad.exe"),
            "-low",
            *ctx.env["VRADLDR"].split(),
            "-noskyboxrecurse",
            "-ldr",
            str(ctx.mapfolder / ctx.mapname),
        ], cwd=ctx.root, env=ctx.process_env, check=True)
    if int(ctx.env.get("TESTBUILD", "0")) != 1:
        run([
            str(ctx.compilers_dir / "vrad.exe"),
            "-low",
            *ctx.env["VRADHDR"].split(),
            "-noskyboxrecurse",
            "-hdr",
            str(ctx.mapfolder / ctx.mapname),
        ], cwd=ctx.root, env=ctx.process_env, check=True)


@stage("run_vbsp_only")
def run_vbsp_only(ctx: BuildContext) -> None:
    run([
        str(ctx.compilers_dir / "vbsp.exe"),
        "-allowdynamicpropsasstatic",
        *ctx.env["VBSPEXTRAS"].split(),
        "-leaktest",
        "-low",
        str(ctx.mapfolder / ctx.mapname),
    ], cwd=ctx.root, env=ctx.process_env, check=True)
    if Path(ctx.mapfolder / f"{ctx.mapname}.lin").exists():
        # map leaked
        raise BuildError("leaktest failed: .lin file was generated", {"lin_file": str(ctx.mapfolder / f"{ctx.mapname}.lin")})

@stage("run_leaktest")
def run_leaktest(ctx: BuildContext) -> None:
    prepare_workspace(ctx)
    run_vmfii(ctx)
    run_vbsp_only(ctx)


@stage("copy_bsp_to_game")
def copy_bsp_to_game(ctx: BuildContext) -> None:
    source = ctx.mapfolder / f"{ctx.mapname}.bsp"
    destination = ctx.game_dir / "maps" / f"{ctx.mapname}.bsp"
    copy_required(source, destination)


@stage("pack_required_files")
def pack_required_files(ctx: BuildContext) -> None:
    run([
        str(ctx.reslister),
        "--format=bspzip",
        str(ctx.mapfolder / f"{ctx.mapname}.vmf"),
        str(ctx.mapdata),
        str(ctx.game_dir / "maps" / f"{ctx.mapname}.bsp.reslister"),
    ], cwd=ctx.root, env=ctx.process_env, check=True)
    run([
        sys.executable,
        str(ctx.zipsrc),
        "-addlist",
        str(ctx.game_dir / "maps" / f"{ctx.mapname}.bsp"),
        str(ctx.game_dir / "maps" / f"{ctx.mapname}.bsp.reslister"),
        str(ctx.game_dir / "maps" / f"{ctx.mapname}.bsp.new"),
    ], cwd=ctx.mapdata, env=ctx.process_env, check=True)
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
        raise BuildError("missing addlist produced by missing-materials step", {"path": str(addlist)})
    run([
        sys.executable,
        str(ctx.zipsrc),
        "-addlist",
        str(ctx.game_dir / "maps" / f"{ctx.mapname}.bsp"),
        str(addlist),
        str(ctx.game_dir / "maps" / f"{ctx.mapname}.bsp.new"),
    ], cwd=ctx.game_dir / "data", env=ctx.process_env, check=True)
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
    run([
        sys.executable,
        str(ctx.zipsrc),
        "-addlist",
        str(ctx.game_dir / "maps" / f"{ctx.mapname}.bsp"),
        str(source),
        str(ctx.game_dir / "maps" / f"{ctx.mapname}.bsp.new"),
    ], cwd=ctx.mapdata, env=ctx.process_env, check=True)
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
    copy_required(ctx.mapfolder / f"{ctx.mapname}.bsp", ctx.game_dir / "maps" / f"{ctx.mapname}_prezip.bsp")
    run_gmodcommander_task("bsprezip", ctx.mapname, ctx.process_env)
    copy_required(ctx.game_dir / "data" / f"{ctx.mapname}.bsp.dat", ctx.game_dir / "maps" / f"{ctx.mapname}.bsp")


@stage("generate_navmesh")
def generate_navmesh(ctx: BuildContext) -> None:
    seed_file = ctx.mapfolder / f"{ctx.mapfile}.lm.txt"
    if not seed_file.exists():
        LOGGER.info("navmesh.seed_missing", path=str(seed_file))
        return
    copy_required(seed_file, ctx.game_dir / "data" / "navmesh_landmarks.txt")
    run_gmodcommander_task("navmesh", ctx.mapname, ctx.process_env)
    target_nav = ctx.game_dir / "maps" / f"{ctx.mapname}.nav"
    if not target_nav.exists() or target_nav.stat().st_size == 0:
        LOGGER.warning("navmesh.failed", path=str(target_nav), size=target_nav.stat().st_size if target_nav.exists() else 0)


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
    status = run([
        "git",
        "-C",
        str(ctx.mapfolder),
        "status",
        "--untracked-files=no",
        "-s",
    ], cwd=ctx.root, env=ctx.process_env, capture_output=True, check=False)
    if status.stdout.strip():
        LOGGER.warning("git.dirty", output=status.stdout.strip())
        if sys.stdin.isatty():
            answer = input("Open shell in map folder? [Y/n] ").strip().lower()
            if answer in ("", "y", "yes"):
                open_shell(ctx.mapfolder)


def cleanup(ctx: BuildContext) -> None:
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


def dump_build_context(ctx: BuildContext) -> None:
    print()
    print(colorama.Style.BRIGHT + colorama.Fore.YELLOW + "=== BuildContext dump ===")
    print(colorama.Fore.CYAN + "root: " + colorama.Style.BRIGHT + str(ctx.root))
    print()
    print(colorama.Fore.YELLOW + "env:")
    for key in sorted(ctx.env):
        print(
            f"  {colorama.Fore.GREEN}{key}{colorama.Style.RESET_ALL}="
            f"{colorama.Fore.CYAN}{ctx.env[key]}"
        )
    print()
    print(colorama.Fore.YELLOW + "derived:")
    derived = {
        "mapfolder": ctx.mapfolder,
        "mapdata": ctx.mapdata,
        "game_dir": ctx.game_dir,
        "game_exe_dir": ctx.game_exe_dir,
        "vproject": ctx.vproject,
        "vproject_hammer": ctx.vproject_hammer,
        "compilers_dir": ctx.compilers_dir,
        "sourcesdk": ctx.sourcesdk,
        "version_file": ctx.version_file,
        "bspzip_gma_out": ctx.bspzip_gma_out,
        "maptoolkit_temp_addon": ctx.maptoolkit_temp_addon,
        "targetvmf": ctx.targetvmf,
        "targetrad": ctx.targetrad,
        "targetvbsp": ctx.targetvbsp,
        "zipsrc": ctx.zipsrc,
        "reslister": ctx.reslister,
        "vmfii": ctx.vmfii,
        "launch_game_cmd": ctx.launch_game_cmd,
        "root_cmd": ctx.root_cmd,
    }
    for name, value in derived.items():
        print(
            f"  {colorama.Fore.GREEN}{name}{colorama.Style.RESET_ALL}: "
            f"{colorama.Fore.CYAN}{value}"
        )
    print(colorama.Style.BRIGHT + colorama.Fore.YELLOW + "=== end dump ===")


def parse_command(raw_command: str | None) -> tuple[str, bool]:
    if raw_command is None:
        return prompt_task()
    normalized = raw_command.lower()
    if normalized in ("b", "build"):
        return "build", False
    if normalized in ("r", "rebuild"):
        return "rebuild", False
    if normalized in ("p", "postprocess"):
        return "postprocess", False
    if normalized in ("d", "dump"):
        return "dump", False
    if normalized in ("publish",):
        return "publish", False
    if normalized in ("l", "leaktest"):
        return "leaktest", False
    if normalized in ("t", "test"):
        return "build", True
    raise argparse.ArgumentTypeError("unknown command")


def main() -> int:
    configure_logging()
    parser = argparse.ArgumentParser()
    parser.add_argument("command", nargs="?", help="build/rebuild/postprocess/dump/publish/leaktest/test")
    parser.add_argument("--test", action="store_true", help="enable test build mode")
    args = parser.parse_args()
    try:
        task, test_mode = parse_command(args.command)
        if args.test:
            test_mode = True
        root = Path(__file__).resolve().parent
        base_env = load_common_env(root)
        check_paths(base_env)
        if task in ("postprocess", "dump", "publish", "leaktest"):
            version = read_version_file(Path(base_env["version_file"]))
        else:
            delta = 1 if task == "build" else 0
            version = next_build_version(Path(base_env["version_file"]), delta)
        env = load_common_env(root, build_version=version)
        env["TESTBUILD"] = "1" if test_mode else env.get("TESTBUILD", "0")
        if task == "dump":
            ctx = BuildContext(root, env)
            dump_build_context(ctx)
            return 0
        if task == "postprocess":
            ctx = BuildContext(root, env)
            run_postprocess(ctx)
            LOGGER.info("build.finished", task=task, version=version)
            return 0
        if task == "publish":
            publish_map.publish_map(root, env)
            LOGGER.info("publish.finished", task=task, version=version)
            return 0
        if task == "leaktest":
            ctx = BuildContext(root, env)
            try:
                run_leaktest(ctx)
            except BuildError:
                LOGGER.info("leaktest.finished", task=task, version=version)
                print(colorama.Fore.RED + "LEAKTEST FAILED: .lin file was generated")
                print(f"File path to .lin: {ctx.mapfolder / f'{ctx.mapname}.lin'}")
                return 1
            LOGGER.info("leaktest.finished", task=task, version=version)
            return 0
        ctx = BuildContext(root, env)
        run_build(ctx)
        LOGGER.info("build.finished", task=task, version=version)
        return 0
    except BuildError as exc:
        LOGGER.error("build.failed", exc_info=True, details=getattr(exc, "details", None))
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

copy_optional
if __name__ == "__main__":
    raise SystemExit(main())
