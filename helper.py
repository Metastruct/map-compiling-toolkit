from __future__ import annotations

import os
import re
import shlex
import shutil
import stat
import subprocess
import tomllib
from pathlib import Path
from typing import Any

import colorama
import structlog

colorama.init(autoreset=True)


def get_logger() -> structlog.BoundLogger:
    return structlog.get_logger(__name__)


def configure_logging() -> None:
    import logging

    logging.basicConfig(format="%(message)s", level=logging.INFO)
    structlog.configure(
        processors=[
            structlog.stdlib.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.dev.ConsoleRenderer(colors=True),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(logging.INFO),
        logger_factory=structlog.stdlib.LoggerFactory(),
        cache_logger_on_first_use=True,
    )


class BuildError(Exception):
    def __init__(self, message: str, details: dict[str, Any] | None = None) -> None:
        super().__init__(message)
        self.details = details or {}


VAR_PATTERN = re.compile(r"%([^%]+)%")


def load_user_config(path: Path) -> dict[str, str]:
    if not path.exists():
        raise BuildError("user_config.cmd must exist", {"path": str(path)})
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw_line.strip()
        if (
            not line
            or line.lower().startswith("@rem")
            or line.lower().startswith("rem")
        ):
            continue
        if line.lower().startswith("@set "):
            line = line[5:]
        elif line.lower().startswith("set "):
            line = line[4:]
        if "=" not in line:
            continue
        name, value = line.split("=", 1)
        values[name.strip()] = value.strip()
    return values


def load_config(path: Path) -> dict[str, str]:
    if not path.exists():
        raise BuildError("config.toml must exist", {"path": str(path)})
    raw = tomllib.loads(path.read_text(encoding="utf-8", errors="ignore"))
    if not isinstance(raw, dict):
        raise BuildError("config file must contain a table", {"path": str(path)})
    values: dict[str, str] = {}

    def flatten(item: Any) -> None:
        if isinstance(item, dict):
            for key, value in item.items():
                if isinstance(value, dict):
                    flatten(value)
                else:
                    values[key] = str(value)
        else:
            raise BuildError("config file contains invalid entry", {"path": str(path)})

    flatten(raw)
    return values


def expand_value(value: str, env: dict[str, str]) -> str:
    if not value:
        return value
    for _ in range(10):
        candidate = VAR_PATTERN.sub(
            lambda match: env.get(match.group(1), match.group(0)), value
        )
        if candidate == value:
            break
        value = candidate
    return value


def run(
    args: list[str],
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    check: bool = True,
    capture_output: bool = False,
    stdout=None,
    stderr=None,
    shell: bool = False,
    log_path: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    command_str = (
        args
        if isinstance(args, str)
        else " ".join(shlex.quote(str(arg)) for arg in args)
    )
    print()
    print(
        colorama.Fore.YELLOW + ">>> executing command: ",
        colorama.Style.BRIGHT + colorama.Fore.CYAN + command_str,
        colorama.Fore.MAGENTA + f"    (cwd: {cwd})",
    )
    if stdout is not None and not capture_output and hasattr(stdout, "write"):
        stdout.write(f"command: {command_str}\n")
        stdout.flush()
    if log_path is not None:
        with log_path.open("a", encoding="utf-8", errors="ignore") as handle:
            handle.write(f"command: {command_str}\n")

    result = subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        env=env,
        check=False,
        capture_output=capture_output,
        stdout=stdout,
        stderr=stderr,
        text=True,
        shell=shell,
    )
    if result.returncode != 0:
        print(colorama.Fore.RED + f"<<< FAIL: code = {result.returncode}")
        print()
    else:
        print(colorama.Fore.GREEN + f"<<< OK")
        print()
    if check and result.returncode != 0:
        raise BuildError(
            "process failed",
            {
                "args": args,
                "returncode": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
            },
        )
    return result


def read_version_file(path: Path) -> int:
    if not path.exists():
        raise BuildError("version file not found", {"path": str(path)})
    text = path.read_text(encoding="utf-8", errors="ignore").strip()
    if not text:
        raise BuildError("version file is empty", {"path": str(path)})
    try:
        return int(text.splitlines()[0].strip())
    except ValueError as exc:
        raise BuildError(
            "version file contains invalid integer", {"path": str(path), "text": text}
        ) from exc


def write_version_file(path: Path, version: int) -> None:
    path.write_text(f"{version}\n", encoding="utf-8")


def ensure_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def copy_tree(source: Path, destination: Path) -> None:
    if not source.exists():
        raise BuildError("source tree missing", {"path": str(source)})
    if not source.is_dir():
        raise BuildError("source tree must be a directory", {"path": str(source)})

    for root, dirs, files in os.walk(source):
        rel_root = Path(root).relative_to(source)
        for folder in dirs:
            (destination / rel_root / folder).mkdir(parents=True, exist_ok=True)
        for filename in files:
            src = Path(root) / filename
            dst = destination / rel_root / filename
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            # get_logger().debug("copy.tree.file", source=str(src), destination=str(dst))


def set_readonly(path: Path, readonly: bool) -> None:
    if not path.exists():
        return
    current_mode = path.stat().st_mode
    if readonly:
        current_mode &= ~stat.S_IWUSR
        current_mode |= stat.S_IREAD
    else:
        current_mode |= stat.S_IWUSR | stat.S_IREAD
    path.chmod(current_mode)


def create_junction(target: Path, link_name: Path) -> None:
    if link_name.exists() or link_name.is_symlink():
        if link_name.is_dir() and not link_name.is_symlink():
            link_name.rmdir()
        else:
            link_name.unlink(missing_ok=True)
    run(["cmd", "/c", "mklink", "/J", str(link_name), str(target)], shell=False)


def remove_path(path: Path) -> None:
    if not path.exists() and not path.is_symlink():
        return
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path, ignore_errors=True)
    else:
        path.unlink(missing_ok=True)


def copy_file(source: Path, destination: Path, optional: bool = False) -> None:
    if not source.exists():
        if optional:
            get_logger().debug("copy.optional.missing", source=str(source))
            return
        raise BuildError("required file missing", {"path": str(source)})
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    level = "optional" if optional else "required"
    get_logger().info(f"copy.{level}", source=str(source), destination=str(destination))


def flash_console() -> None:
    try:
        import ctypes

        hwnd = ctypes.windll.kernel32.GetConsoleWindow()
        if hwnd:
            ctypes.windll.user32.FlashWindow(hwnd, True)
    except Exception as exc:
        pass


def open_shell(path: Path) -> None:
    shell = shutil.which("bash.exe") or shutil.which("cmd.exe")
    if not shell:
        raise BuildError("no shell available to open", {})
    run([shell], cwd=path, env=os.environ.copy(), check=False)
