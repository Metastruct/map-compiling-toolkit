from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import os
from typing import Any

import structlog

from helper import (
    expand_value,
    load_config,
    read_version_file,
    create_junction,
    remove_path,
)

LOGGER = structlog.get_logger()


class TempAddonJunction:
    def __init__(self, target: Path, link_path: Path) -> None:
        self.target = target
        self.link_path = link_path

    def link(self) -> "TempAddonJunction":
        remove_path(self.link_path)
        LOGGER.info(
            "temp_addon_junction.creating",
            link=str(self.link_path.resolve()),
            target=str(self.target),
        )
        create_junction(self.target, self.link_path)
        return self

    def teardown(self) -> None:
        LOGGER.info(
            "temp_addon_junction.cleanup",
            link=str(self.link_path.resolve()),
            target=str(self.target),
        )
        remove_path(self.link_path)

    def __enter__(self) -> "TempAddonJunction":
        return self.link()

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        self.teardown()


def assign_environment_value(
    env: dict[str, str], user: dict[str, str], name: str, default: str
) -> None:
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
    assign_environment_value(env, user, "SteamUser", "%SteamAppUser%")
    assign_environment_value(env, user, "SteamPath", r"C:\Program Files (x86)\Steam")
    assign_environment_value(env, user, "SteamPathAlt", "%SteamPath%")
    assign_environment_value(env, user, "mapfolder", r"C:\metastruct\mapfiles")
    assign_environment_value(env, user, "version_file", r"%mapfolder%\ver_meta3.txt")
    if build_version is not None:
        env["BUILD_VERSION"] = str(build_version)
    elif "BUILD_VERSION" not in env:
        env["BUILD_VERSION"] = str(
            read_version_file(Path(expand_value(env["version_file"], env)))
        )
    assign_environment_value(env, user, "mapfile", "metastruct_3")
    assign_environment_value(env, user, "mapname", "gm_construct_m_%BUILD_VERSION%")
    assign_environment_value(env, user, "mapdata", r"C:\metastruct\mapdata")
    assign_environment_value(env, user, "mapwsid", "0")
    assign_environment_value(env, user, "GCNOADDONS", "-noaddons")
    assign_environment_value(env, user, "NO_MISSING_BUNDLING", "0")
    assign_environment_value(env, user, "VBSPEXTRAS", "-notjunc -blocksize 2048")
    assign_environment_value(env, user, "VRADHDR", "-softsun 0 -bounce 1")
    assign_environment_value(env, user, "VRADLDR", "%VRADHDR%")
    assign_environment_value(
        env,
        user,
        "sourcesdk",
        r"%SteamPath%\steamapps\common\Source SDK Base 2013 Multiplayer",
    )
    assign_environment_value(
        env,
        user,
        "FGDS",
        r"%sourcesdk%\bin\base.fgd,%sourcesdk%\bin\halflife2.fgd,%mapfolder%\metastruct.fgd",
    )
    env["toolkit_root"] = str(root) + "\\"
    assign_environment_value(
        env, user, "VProject_Hammer", r"%toolkit_root%game_hammer\garrysmod"
    )
    assign_environment_value(
        env, user, "VProject", r"%toolkit_root%game_compiling\garrysmod"
    )
    assign_environment_value(
        env, user, "compilers_dir", r"%toolkit_root%game_compiling\bin\win64"
    )
    if (
        not Path(expand_value(env["VProject_Hammer"], env))
        .joinpath("gameinfo.txt")
        .exists()
    ):
        env["VProject_Hammer"] = expand_value(env["VProject"], env)
    assign_environment_value(
        env, user, "GameDir", r"%SteamPath%\steamapps\common\GarrysMod\garrysmod"
    )
    assign_environment_value(
        env, user, "GameExeDir", r"%SteamPath%\steamapps\common\GarrysMod"
    )
    assign_environment_value(env, user, "ValvePlatformMutex", r"%SteamPath%\steam.exe")
    assign_environment_value(
        env, user, "PATH", r"%toolkit_root%;%sourcesdk%\bin;%SteamPath%;%PATH%"
    )
    assign_environment_value(env, user, "SteamAppId", "4000")
    assign_environment_value(env, user, "SteamAppVersionId", "45")
    assign_environment_value(env, user, "SteamGameId", "211")
    assign_environment_value(env, user, "SteamGame", "garrysmod")
    return {k: expand_value(v, env) for k, v in env.items()}


@dataclass
class BuildContext:
    root: Path
    env: dict[str, str]
    _temp_addon_junction: TempAddonJunction | None = None

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
        return self.root / "extras" / "gmazip.py"

    @property
    def reslister(self) -> Path:
        return self.root / "extras" / "reslister.exe"

    @property
    def vmfii(self) -> Path:
        return self.root / "extras" / "vmfii"

    @property
    def root_cmd(self) -> str:
        return str(self.root)


def dump_build_context(ctx: BuildContext) -> None:
    import colorama

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
        "root_cmd": ctx.root_cmd,
    }
    for name, value in derived.items():
        print(
            f"  {colorama.Fore.GREEN}{name}{colorama.Style.RESET_ALL}: "
            f"{colorama.Fore.CYAN}{value}"
        )
    print(colorama.Style.BRIGHT + colorama.Fore.YELLOW + "=== end dump ===")
