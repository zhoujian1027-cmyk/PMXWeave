#!/bin/sh
set -u
MODE=fix
case "${1:-}" in
  --check|-n) MODE=check; shift;;
  --help|-h) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
esac
if [ "$#" -eq 0 ]; then
  echo "usage: pmx_share.sh [--check] <analysis-dir> [...]" >&2
  echo "  grants the SMB share user ownership of <analysis-dir>/.pmx so it can be deleted" >&2
  exit 2
fi
IS_ROOT=0
[ "$(id -u 2>/dev/null || echo 1)" = 0 ] && IS_ROOT=1
RC=0
for d in "$@"; do
  if [ ! -d "$d" ]; then
    echo "PMX_SHARE_SKIP $d (not a directory)" >&2; RC=2; continue
  fi
  UID_TO=${PMX_SMB_UID:-$(stat -c %u "$d")}
  GRP_TO=${PMX_SMB_GRP:-$(stat -c %g "$d")}
  if [ "$MODE" = check ]; then
    TOP=$(find "$d" -mindepth 1 -maxdepth 1 -user 0 2>/dev/null | wc -l | tr -d ' ')
    PMX=$(find "$d/.pmx" -mindepth 1 -user 0 2>/dev/null | wc -l | tr -d ' ')
    if [ "$TOP" = 0 ] && [ "$PMX" = 0 ]; then
      echo "PMX_SHARE_CHECK_OK $d no root-owned entries found"
    else
      echo "PMX_SHARE_CHECK $d root_owned_top=$TOP root_owned_under_pmx=$PMX"
      [ "$PMX" = 0 ] || echo "  fix: sh $0 $d   (gives uid $UID_TO:$GRP_TO the tree, then: rm -rf $d/.pmx)" >&2
      RC=1
    fi
    continue
  fi
  if [ "$IS_ROOT" = 1 ]; then
    [ -e "$d/.pmx" ] && chown -R "$UID_TO:$GRP_TO" "$d/.pmx" 2>/dev/null
  fi
  [ -e "$d/.pmx" ] && chmod -R g+rwX "$d/.pmx" 2>/dev/null
  LEFT=$(find "$d/.pmx" -mindepth 1 -user 0 2>/dev/null | wc -l | tr -d ' ')
  if [ "$LEFT" = 0 ]; then
    echo "PMX_SHARE_OK $d .pmx handed to $UID_TO:$GRP_TO -- delete it any time (rm -rf $d/.pmx)"
  else
    echo "PMX_SHARE_PARTIAL $d $LEFT root-owned entries remain under .pmx (chown needs root: rerun as root)" >&2
    RC=1
  fi
done
exit "$RC"
