#!/bin/bash

echo "> propperall.sh 0.1"
skipped=0
compiled=0

for f in *.vmf; do
	
	
	if cmp -s "$f" ".$f.tmp"; then
		#echo "Skipping $f"
		skipped=$((skipped+1))
		continue
	fi
	
	echo Processing "$f"   Log: "$f.log"
	"$VBSPNAME" "$f" > "$f.log"
	if [ $? -ne 0 ] || ! grep -q Completed "$f.log"; then
		echo ""
		echo "Failed: $f"
		echo ""
		cat "$f.log"
		echo ""
		echo "SKIPPING OTHER MODELS UNTIL THIS IS FIXED"
		echo ""
		exit 1
		break
	fi
	cp "$f" ".$f.tmp"
	
	compiled=$((compiled+1))
done

if [ $skipped -ge 0 ]; then
	echo "Skipped $skipped VMFs"
fi
echo "Compiled $compiled VMFs"
