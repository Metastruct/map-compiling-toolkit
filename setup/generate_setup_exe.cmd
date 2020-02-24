pip install -r requirements.txt
pyinstaller --distpath . -F setup.py --upx-exclude ucrtbase.dll --upx-exclude vcruntime140.dll
pause