#!/usr/bin/env python
import os,sys
from pathlib import Path
import shutil

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)
    
args=sys.argv[1:]

addlist=args.index('-addlist')
args.pop(addlist)
input_bsp=Path(args.pop(addlist))
file_list=Path(args.pop(addlist))
output_bsp=Path(args.pop(addlist))
for remaining in args:
    if remaining.startswith("-"):
        raise NotImplementedError(f"Not implemented param: {remaining}")

#print(f"input_bsp={input_bsp} file_list={file_list} output_bsp={output_bsp}")

if not input_bsp.exists():
    raise FileNotFoundError(f"Not found: {input_bsp}")

if not file_list.exists():
    raise FileNotFoundError(f"Not found: {file_list}")

folder_out=os.getenv("BSPZIP_GMA_OUT","")
if folder_out:
    folder_out=Path(folder_out)
    if not folder_out.exists():
        raise FileNotFoundError(f"Destination folder from env=BSPZIP_GMA_OUT not found: {folder_out}")
else:
    folder_out=output_bsp.with_suffix('').with_suffix('').with_suffix('')
    folder_out.mkdir(exist_ok=True)

#print(f"OUT={folder_out}")
#if folder_out.glob("*"):
#    try:
#        raise FileExistsError(f"Already files in {folder_out}")
#    except FileExistsError as e:
#        eprint(e)

def process(src,dst):
    if src==Path(".") or dst==Path("."):
        return
    
    #print(f"== PROCESS {src} {dst}==")
    try:
        if not src.exists() and not src.resolve().exists():
            print(src.resolve())
            raise FileNotFoundError(f"Source path not found: {src}")
        if dst.is_absolute():
            raise ValueError(f"Absolute destination path found: {dst}")
        
    except ValueError as e:
        eprint(f"ERROR: src={src} dst={dst}")
        raise e    
    dst = folder_out/dst

    if src.is_dir():
        raise ValueError("src is folder")
    if dst.is_dir():
        raise ValueError("dst is folder")
    dst.parent.mkdir(exist_ok=True,parents=True)
    shutil.copy(src, dst)

with file_list.open("r", encoding='utf-8') as f:
    while True:
        internal_path = f.readline().strip()
        external_path = f.readline().strip()
        process(Path(external_path),Path(internal_path))
        if not external_path:
            break

# We want to maintain compatibility even if nothing was changed
shutil.copy(input_bsp, output_bsp)
print("Finished processing reslist")