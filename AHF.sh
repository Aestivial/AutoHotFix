#!/usr/bin/env bash
#
# hf_deploy.sh — Interactive HotFix (HF) deployment helper for JARs (or any extension)
#
# What it does
#  1) Prompts for HF folder and Target folder (or accepts flags).
#  2) Builds a map of Target files by "artifact name" = filename with extension removed,
#     with the trailing "-<version or qualifier>" stripped. Example:
#        tpt-cxl-trade-capture-8.25.01.0.16.jar  -> key: tpt-cxl-trade-capture
#        tpt-cxl-trade-capture-8.25.01.0.17-SNAPSHOT.jar -> same key.
#  3) For each HF file, finds target files with the same key and *prompts you* to replace.
#     Replacement means:
#        - Move the old target file into:  <HF_DIR>/backup/<YYYYmmdd_HHMMSS>/<relative-target-dir>/
#        - Copy the HF file into the target directory (keeps the HF filename).
#
# Notes
#  - Default extension is "jar". You can change with --ext.
#  - Only HF folder top-level files are processed by default; use --hf-recursive to recurse.
#  - Prompts per match: [y]es, [n]o, [a]ll for this HF file, [s]kip all for this HF file, [q]uit.
#  - A dry run is available via --dry-run.
#
# Usage
#   chmod +x hf_deploy.sh
#   ./hf_deploy.sh
#
# Optional flags (can combine with interactive prompts):
#   --source /path/to/HF             HotFix folder
#   --target /path/to/target         Target folder
#   --ext jar                        File extension to process (default: jar)
#   --hf-recursive                   Recurse inside HF folder (default: off)
#   --dry-run                        Show actions without changing anything
#   --keep-target-name               Copy HF file using the *target's* original filename
#
# Exit codes: 0 success, non-zero on error.
#

set -o errexit
set -o pipefail
set -o nounset

# ---------- defaults ----------
HF_DIR=""
TARGET_DIR=""
FILE_EXT="jar"
HF_RECURSIVE=false
DRY_RUN=false
KEEP_TARGET_NAME=false

# ---------- helpers ----------
die() { printf "Error: %s\n" "$*" >&2; exit 1; }

# Normalize a filename to an "artifact key":
# - strip extension
# - cut at the first hyphen followed by a digit (start of version/qualifier)
#   e.g., "abc-capture-8.25.01.0.16-SNAPSHOT" -> "abc-capture"
artifact_key() {
  # input: full path OR bare filename
  local f base noext key
  f=$1
  base=$(basename -- "$f")
  noext=${base%.*}
  if [[ "$noext" =~ ^(.*?)-[0-9].*$ ]]; then
    key="${BASH_REMATCH[1]}"
  else
    key="$noext"
  fi
  printf "%s" "$key"
}

# Ask a yes/no/choice question with default No
ask_replace() {
  # args: HF_FILE TARGET_FILE
  local hf="$1"
  local tgt="$2"
  local hf_base tgt_base hf_ver tgt_ver
  hf_base=$(basename -- "$hf")
  tgt_base=$(basename -- "$tgt")

  # Extract "version-ish" tail for info only
  extract_ver() {
    local name="$1" noext="${1%.*}" ver=""
    if [[ "$noext" =~ ^(.*?)-(.*)$ ]]; then
      ver="${BASH_REMATCH[2]}"
    fi
    printf "%s" "$ver"
  }
  hf_ver=$(extract_ver "$hf_base")
  tgt_ver=$(extract_ver "$tgt_base")

  printf "\nMatch found:\n"
  printf "  TARGET: %s\n" "$tgt"
  printf "    (detected version: %s)\n" "${tgt_ver:-<none>}"
  printf "     ---> will be replaced by HF: %s\n" "$hf"
  printf "    (detected version: %s)\n" "${hf_ver:-<none>}"
  printf "Proceed? [y]es / [n]o / [a]ll (for this HF) / [s]kip all (for this HF) / [q]uit: "
}

timestamp() { date +"%Y%m%d_%H%M%S"; }

# Perform the replacement: move target -> backup; copy HF -> target dir
do_replace() {
  local hf_file="$1"
  local tgt_file="$2"
  local backup_root="$3"
  local keep_target_name="$4" # true/false

  local tgt_dir rel_dir backup_dir copy_dest log_line
  tgt_dir=$(dirname -- "$tgt_file")

  # Compute relative dir under target, to mirror in backup
  case "$tgt_dir" in
    "$TARGET_DIR") rel_dir="." ;;
    "$TARGET_DIR"/*) rel_dir="${tgt_dir#"$TARGET_DIR"/}" ;;
    *) rel_dir="." ;; # unexpected but safe fallback
  esac

  backup_dir="$backup_root/$rel_dir"
  mkdir -p -- "$backup_dir"

  if $DRY_RUN; then
    printf "[DRY] mv -- '%s' '%s/'\n" "$tgt_file" "$backup_dir"
  else
    mv -- "$tgt_file" "$backup_dir/"
  fi

  if $keep_target_name; then
    # Copy HF over using the original target filename
    local tgt_name
    tgt_name=$(basename -- "$tgt_file")
    copy_dest="$tgt_dir/$tgt_name"
  else
    # Copy HF using its own filename
    local hf_name
    hf_name=$(basename -- "$hf_file")
    copy_dest="$tgt_dir/$hf_name"
  fi

  if $DRY_RUN; then
    printf "[DRY] cp -p -- '%s' '%s'\n" "$hf_file" "$copy_dest"
  else
    cp -p -- "$hf_file" "$copy_dest"
  fi
}

# Index target files by artifact key.
# For portability (bash 3 on macOS), we build a temp file index:
#   key<TAB>absolute_path
build_target_index() {
  local idx_file="$1"
  : > "$idx_file"

  # Build list of target files with the given extension
  # -print0 to handle spaces/newlines in names safely
  while IFS= read -r -d '' f; do
    local key
    key=$(artifact_key "$f")
    printf "%s\t%s\n" "$key" "$f" >> "$idx_file"
  done < <(find "$TARGET_DIR" -type f -name "*.${FILE_EXT}" -print0)
}

# Lookup in the index: echo all paths matching a given key, NUL-separated
lookup_target_matches() {
  local idx_file="$1" key="$2"
  # Use awk to match the key exactly (tab-delimited), print path
  awk -v k="$key" -F'\t' '$1==k {print $2}' "$idx_file" | tr '\n' '\0'
}

# ---------- arg parsing ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source|-s) HF_DIR="${2:-}"; shift 2;;
    --target|-t) TARGET_DIR="${2:-}"; shift 2;;
    --ext) FILE_EXT="${2:-jar}"; shift 2;;
    --hf-recursive) HF_RECURSIVE=true; shift;;
    --dry-run) DRY_RUN=true; shift;;
    --keep-target-name) KEEP_TARGET_NAME=true; shift;;
    -h|--help)
      sed -n '1,120p' "$0"
      exit 0;;
    *) die "Unknown argument: $1";;
  esac
done

# ---------- interactive prompts if needed ----------
if [[ -z "${HF_DIR}" ]]; then
  read -r -p "Enter HF folder path: " HF_DIR
fi
if [[ -z "${TARGET_DIR}" ]]; then
  read -r -p "Enter Target folder path: " TARGET_DIR
fi

# Resolve to absolute paths
HF_DIR=$(cd "$HF_DIR" 2>/dev/null && pwd) || die "HF folder not found or inaccessible"
TARGET_DIR=$(cd "$TARGET_DIR" 2>/dev/null && pwd) || die "Target folder not found or inaccessible"

[[ -d "$HF_DIR" ]] || die "HF folder is not a directory: $HF_DIR"
[[ -d "$TARGET_DIR" ]] || die "Target folder is not a directory: $TARGET_DIR"

# Permissions sanity (best-effort)
[[ -r "$HF_DIR" ]] || die "HF folder not readable"
[[ -r "$TARGET_DIR" ]] || die "Target folder not readable"
if ! $DRY_RUN; then
  [[ -w "$HF_DIR" ]] || die "HF folder not writable (needed to store backups)"
  [[ -w "$TARGET_DIR" ]] || die "Target folder not writable"
fi

# Prepare backup directory root under HF folder
BACKUP_ROOT="$HF_DIR/backup/$(timestamp)"
LOG_FILE="$BACKUP_ROOT/replace.log"
mkdir -p -- "$BACKUP_ROOT"
if $DRY_RUN; then
  printf "[DRY] Would create backup at: %s\n" "$BACKUP_ROOT"
else
  printf "Backup folder: %s\n" "$BACKUP_ROOT"
  printf "# HF Deployment Log (%s)\n" "$(date -Iseconds)" > "$LOG_FILE"
fi

# Build target index
IDX_FILE="$(mktemp -t hf_target_index.XXXXXX)"
trap 'rm -f "$IDX_FILE"' EXIT
printf "Indexing target files (*.%s) under: %s ...\n" "$FILE_EXT" "$TARGET_DIR"
build_target_index "$IDX_FILE"

# Gather HF candidates (default: only top-level files; optional recursive)
printf "Scanning HF files (*.%s) under: %s%s ...\n" "$FILE_EXT" "$HF_DIR" "$($HF_RECURSIVE && printf " (recursive)")"
HF_FIND_OPTS=(-type f -name "*.${FILE_EXT}")
$HF_RECURSIVE || HF_FIND_OPTS=(-maxdepth 1 "${HF_FIND_OPTS[@]}")

mapfile -d '' HF_FILES < <(find "$HF_DIR" "${HF_FIND_OPTS[@]}" -print0)

if [[ "${#HF_FILES[@]}" -eq 0 ]]; then
  printf "No HF files with extension '.%s' found in %s\n" "$FILE_EXT" "$HF_DIR"
  exit 0
fi

# Loop over HF files; for each, find matches in target and prompt
for hf in "${HF_FILES[@]}"; do
  key=$(artifact_key "$hf")
  # Get all target matches for this key (NUL-separated)
  mapfile -d '' MATCHES < <(lookup_target_matches "$IDX_FILE" "$key")

  if [[ "${#MATCHES[@]}" -eq 0 ]]; then
    printf "No target match for HF '%s' (key: %s)\n" "$(basename -- "$hf")" "$key"
    continue
  fi

  # Interactive loop over matches
  apply_all=false
  skip_all=false

  for tgt in "${MATCHES[@]}"; do
    # Safety: if the exact same file path is in both HF and target, skip self-replacement
    if [[ "$hf" -ef "$tgt" ]]; then
      printf "Skipping self-match (same file): %s\n" "$tgt"
      continue
    fi

    if $apply_all; then
      action="y"
    elif $skip_all; then
      action="n"
    else
      ask_replace "$hf" "$tgt"
      read -r action
      action=${action:-n}
    fi

    case "$action" in
      y|Y)
        do_replace "$hf" "$tgt" "$BACKUP_ROOT" "$KEEP_TARGET_NAME"
        if ! $DRY_RUN; then
          printf "%s\tREPLACED\t%s\t->\t%s\n" "$(date -Iseconds)" "$tgt" "$hf" >> "$LOG_FILE"
        fi
        ;;
      a|A)
        apply_all=true
        do_replace "$hf" "$tgt" "$BACKUP_ROOT" "$KEEP_TARGET_NAME"
        if ! $DRY_RUN; then
          printf "%s\tREPLACED\t%s\t->\t%s\n" "$(date -Iseconds)" "$tgt" "$hf" >> "$LOG_FILE"
        fi
        ;;
      s|S)
        skip_all=true
        printf "Skipping all matches for HF: %s\n" "$hf"
        ;;
      q|Q)
        printf "Quitting on user request.\n"
        exit 0
        ;;
      n|N|*)
        printf "Skipped: %s\n" "$tgt"
        ;;
    esac
  done
done

printf "\nDone.\n"
if ! $DRY_RUN; then
  printf "Backup: %s\n" "$BACKUP_ROOT"
  printf "Log:    %s\n" "$LOG_FILE"
fi
