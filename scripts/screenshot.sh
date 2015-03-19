#!/bin/sh
#  screenshot wrapper
#  uses "scrot" (xfce) to take a screenshot and
#  opens the resulting file with $X_PIC_VIEWER (default: mirage)
#
: ${X_PIC_VIEWER=mirage}
: ${X_PIC_VIEWER_OPTS=}

FEXT=".png"
D="${TMPDIR:-/tmp}/screenshot"
mkdir -- "${D}" 2>/dev/null || [ -d "${D}" ] || exit

f="${D}/$(date +%F)"

i=0
while [ -e "${f}_${i}${FEXT}" ]; do
   i=$(( i + 1 ))
   [ ${i} -lt 50000 ] || exit 22
done

OUT_FILE="${f}_${i}${FEXT}"

scrot -m "${OUT_FILE}" && [ -e "${OUT_FILE}" ] || exit

if [ -n "${X_PIC_VIEWER}" ]; then
   exec "${X_PIC_VIEWER}" ${X_PIC_VIEWER_OPTS-} "${OUT_FILE}"
fi
