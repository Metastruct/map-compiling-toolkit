uv sync --group dev
uv run pyinstaller --distpath . -F setup.py --upx-exclude ucrtbase.dll --upx-exclude vcruntime140.dll
pause
