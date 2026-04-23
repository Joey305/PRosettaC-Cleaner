#!/usr/bin/env bash
set -euo pipefail

# clean_ptc_results.sh
# Bash version of the PRosettaC Results cleaner.
# Requires: bash, awk, find, sort, cp, mv, rm

PTC_RESNAME="PTC"
OUT_NAME="Results_Cleaned"
DRY_RUN=0
KEEP_OLD_RESULTS=0
INPUT_PATH=""
CLEAN_REMARK="REMARK JARI-CLEANED"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [path] [options]

Description:
  Recursively clean PRosettaC Results folders by:
    1) removing duplicate top-level PDB/ENT files if the same filename exists
       in any cluster* subdirectory
    2) removing the three highest-numbered carbon atoms from residue PTC
       (e.g. C17, C18, C19) and any directly bonded hydrogens via CONECT records
    3) adding a REMARK JARI-CLEANED tag so files are not cleaned twice

Arguments:
  path                    Path to a job directory containing Results, or directly
                          to the Results folder. If omitted, interactive selection
                          is used.

Options:
  --ptc-resname NAME      Residue name to clean (default: PTC)
  --out-name NAME         Temporary output folder name (default: Results_Cleaned)
  --dry-run               Preview actions without writing files
  --keep-old-results      Keep original Results; do not swap cleaned folder back
  -h, --help              Show this help message
USAGE
}

log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

is_pdb_ext() {
  local f="$1"
  case "${f,,}" in
    *.pdb|*.ent) return 0 ;;
    *) return 1 ;;
  esac
}

list_cwd_directories() {
  local i=0
  while IFS= read -r -d '' d; do
    printf '%s\t%s\n' "$i" "$d"
    i=$((i+1))
  done < <(find . -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
}

prompt_for_path() {
  local cwd
  cwd=$(pwd)
  log "Current working directory: $cwd"
  log ""
  log "Folders in current working directory:"

  mapfile -t DIRS < <(find . -mindepth 1 -maxdepth 1 -type d | sort)
  if [[ ${#DIRS[@]} -eq 0 ]]; then
    log "  No folders found in the current working directory."
  else
    local idx=0
    local d
    for d in "${DIRS[@]}"; do
      local name marker=""
      name=$(basename "$d")
      [[ -d "$d/Results" ]] && marker=" [contains Results]"
      log "  $idx: $name$marker"
      idx=$((idx+1))
    done
  fi

  log ""
  log "Choose one of the following:"
  log "  - Enter an index from the list above"
  log "  - Enter a full path to a job directory or directly to a Results folder"
  printf 'Selection or full path: '
  read -r raw
  raw="${raw%\"}"
  raw="${raw#\"}"
  raw="${raw%'}"
  raw="${raw#'}"

  [[ -z "$raw" ]] && { err "No selection/path provided. Exiting."; exit 1; }

  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    local idx="$raw"
    [[ "$idx" -lt 0 || "$idx" -ge ${#DIRS[@]} ]] && { err "Invalid index: $idx"; exit 1; }
    realpath "${DIRS[$idx]}"
  else
    realpath "$raw"
  fi
}

resolve_results_dir() {
  local user_path="$1"
  [[ ! -e "$user_path" ]] && { err "Path does not exist: $user_path"; exit 1; }

  if [[ -d "$user_path" && "$(basename "$user_path")" == "Results" ]]; then
    printf '%s\t%s\n' "$user_path" "$(dirname "$user_path")"
    return
  fi

  if [[ -d "$user_path/Results" ]]; then
    printf '%s\t%s\n' "$user_path/Results" "$user_path"
    return
  fi

  err "Could not find a Results folder at $user_path or $user_path/Results"
  exit 1
}

detect_duplicate_top_level_pdbs() {
  local results_dir="$1"
  local tmp_top tmp_cluster
  tmp_top=$(mktemp)
  tmp_cluster=$(mktemp)

  find "$results_dir" -maxdepth 1 -type f \( -iname '*.pdb' -o -iname '*.ent' \) -printf '%f\t%p\n' | sort > "$tmp_top"
  find "$results_dir" -type f \( -iname '*.pdb' -o -iname '*.ent' \) | awk -v base="$results_dir" '
    {
      rel=$0
      sub("^" base "/?", "", rel)
      n=split(rel, a, "/")
      cluster=0
      for (i=1; i<n; i++) {
        low=tolower(a[i])
        if (index(low, "cluster") == 1) { cluster=1; break }
      }
      if (cluster) print a[n]
    }
  ' | sort -u > "$tmp_cluster"

  awk 'NR==FNR { names[$1]=1; next } ($1 in names) { print $2 }' "$tmp_cluster" "$tmp_top"

  rm -f "$tmp_top" "$tmp_cluster"
}

preview_first_uncleaned() {
  local results_dir="$1"
  local ptc_resname="$2"
  while IFS= read -r -d '' f; do
    awk -v ptc="$ptc_resname" '
      function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
      BEGIN { has_clean=0 }
      /^REMARK JARI-CLEANED$/ { has_clean=1 }
      {
        lines[++n]=$0
        if (substr($0,1,6)=="ATOM  " || substr($0,1,6)=="HETATM") {
          serial=trim(substr($0,7,5))+0
          aname=trim(substr($0,13,4))
          rname=trim(substr($0,18,3))
          serial_line[serial]=$0
          if (rname==ptc && aname ~ /^C[0-9]+$/) {
            idx=substr(aname,2)+0
            carbon_idx[++c]=idx
            carbon_serial[idx]=serial
            carbon_name[idx]=aname
          }
        }
      }
      END {
        if (has_clean) exit 2
        if (c<3) exit 3
        # sort numeric ascending
        for (i=1; i<=c; i++) {
          for (j=i+1; j<=c; j++) {
            if (carbon_idx[i] > carbon_idx[j]) {
              t=carbon_idx[i]; carbon_idx[i]=carbon_idx[j]; carbon_idx[j]=t
            }
          }
        }
        n1=carbon_idx[c-2]; n2=carbon_idx[c-1]; n3=carbon_idx[c]
        print FILENAME "\t" carbon_name[n1] ", " carbon_name[n2] ", " carbon_name[n3]
        exit 0
      }
    ' "$f" 2>/dev/null && return 0
  done < <(find "$results_dir" -type f \( -iname '*.pdb' -o -iname '*.ent' \) -print0 | sort -z)
  return 1
}

clean_one_pdb() {
  local src="$1"
  local dst="$2"
  local ptc_resname="$3"

  awk -v ptc="$ptc_resname" -v remark="$CLEAN_REMARK" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function atom_serial(line) { return trim(substr(line,7,5))+0 }
    function atom_name(line)   { return trim(substr(line,13,4)) }
    function resname(line)     { return trim(substr(line,18,3)) }
    function elem(line,  e,n,letters) {
      e=trim(substr(line,77,2))
      if (e != "") return toupper(e)
      n=atom_name(line)
      gsub(/[^A-Za-z]/, "", n)
      return toupper(substr(n,1,1))
    }
    function rebuild_conect(src, arr, cnt,   i, out) {
      out = sprintf("CONECT%5d", src)
      for (i=1; i<=cnt; i++) out = out sprintf("%5d", arr[i])
      return out
    }
    BEGIN {
      has_clean=0; expdta_idx=0; header_idx=0; line_count=0; carbon_count=0
    }
    {
      line=$0
      lines[++line_count]=line
      if (line == remark) has_clean=1
      if (substr(line,1,6)=="EXPDTA" && expdta_idx==0) expdta_idx=line_count
      if (substr(line,1,6)=="HEADER" && header_idx==0) header_idx=line_count

      rec=substr(line,1,6)
      if (rec=="ATOM  " || rec=="HETATM") {
        serial=atom_serial(line)
        serial_to_line[serial]=line
        serial_rname[serial]=resname(line)
        serial_elem[serial]=elem(line)
        an=atom_name(line)
        if (resname(line)==ptc && an ~ /^C[0-9]+$/) {
          idx=substr(an,2)+0
          carbon_idx[++carbon_count]=idx
          carbon_serial[idx]=serial
          carbon_name[idx]=an
        }
      }
      else if (substr(line,1,6)=="CONECT") {
        k=0
        for (start=7; start<=length(line); start+=5) {
          field=trim(substr(line,start,5))
          if (field != "") nums[++k]=field+0
        }
        if (k>0) {
          srca=nums[1]
          for (i=2; i<=k; i++) {
            nb=nums[i]
            bond[srca, nb]=1
            bond[nb, srca]=1
            bond_seen[srca]=1
            bond_seen[nb]=1
          }
        }
        delete nums
      }
    }
    END {
      if (has_clean) {
        for (i=1; i<=line_count; i++) print lines[i]
        printf("STATUS\talready_cleaned\n") > "/dev/stderr"
        exit 0
      }

      if (carbon_count < 3) {
        printf("Found fewer than 3 numbered carbon atoms in residue %s.\n", ptc) > "/dev/stderr"
        exit 10
      }

      # sort ascending
      for (i=1; i<=carbon_count; i++) {
        for (j=i+1; j<=carbon_count; j++) {
          if (carbon_idx[i] > carbon_idx[j]) {
            t=carbon_idx[i]; carbon_idx[i]=carbon_idx[j]; carbon_idx[j]=t
          }
        }
      }

      n1=carbon_idx[carbon_count-2]
      n2=carbon_idx[carbon_count-1]
      n3=carbon_idx[carbon_count]
      remove[carbon_serial[n1]]=1
      remove[carbon_serial[n2]]=1
      remove[carbon_serial[n3]]=1
      removed_names = carbon_name[n1] ", " carbon_name[n2] ", " carbon_name[n3]
      removed_named_count=3

      # remove directly bonded hydrogens within same residue
      for (key in remove) {
        s=key+0
        for (pair in bond) {
          split(pair, ij, SUBSEP)
          if ((ij[1]+0)==s) {
            nb=ij[2]+0
            if (serial_rname[nb]==ptc && serial_elem[nb]=="H") remove[nb]=1
          }
        }
      }

      total_remove=0
      for (r in remove) total_remove++
      extra_h=total_remove-removed_named_count

      insert_after=0
      if (expdta_idx>0) insert_after=expdta_idx
      else if (header_idx>0) insert_after=header_idx

      for (i=1; i<=line_count; i++) {
        if (insert_after==0 && i==1) print remark

        line=lines[i]
        rec=substr(line,1,6)

        if ((rec=="ATOM  " || rec=="HETATM")) {
          serial=atom_serial(line)
          if (serial in remove) continue
        }
        else if (rec=="ANISOU") {
          serial=trim(substr(line,7,5))+0
          if (serial in remove) continue
        }
        else if (rec=="CONECT") {
          k=0
          for (start=7; start<=length(line); start+=5) {
            field=trim(substr(line,start,5))
            if (field != "") nums[++k]=field+0
          }
          if (k>0) {
            srca=nums[1]
            if (srca in remove) { delete nums; continue }
            kept=0
            for (x=2; x<=k; x++) {
              nb=nums[x]
              if (!(nb in remove)) keep[++kept]=nb
            }
            if (kept>0) print rebuild_conect(srca, keep, kept)
            delete nums; delete keep
            if (i==insert_after) print remark
            continue
          }
          delete nums
        }

        print line
        if (i==insert_after) print remark
      }

      printf("STATUS\tcleaned\t%s\t%d\n", removed_names, extra_h) > "/dev/stderr"
    }
  ' "$src" > "$dst"
}

swap_cleaned_into_results() {
  local results_dir="$1"
  local out_dir="$2"
  local parent backup_dir
  parent=$(dirname "$results_dir")
  backup_dir="$parent/Results_Original_Backup"

  [[ -e "$backup_dir" ]] && {
    err "Backup folder already exists: $backup_dir. Remove/rename it before swapping."
    exit 1
  }

  if [[ -e "$results_dir" ]]; then
    log "Moving original Results -> $(basename "$backup_dir")"
    mv "$results_dir" "$backup_dir"
  fi
  log "Renaming $(basename "$out_dir") -> Results"
  mv "$out_dir" "$results_dir"
  log "Deleting backup folder: $backup_dir"
  rm -rf "$backup_dir"
}

# --------------------------
# Parse args
# --------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ptc-resname)
      [[ $# -lt 2 ]] && { err "--ptc-resname requires a value"; exit 1; }
      PTC_RESNAME="$2"
      shift 2
      ;;
    --out-name)
      [[ $# -lt 2 ]] && { err "--out-name requires a value"; exit 1; }
      OUT_NAME="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --keep-old-results)
      KEEP_OLD_RESULTS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -* )
      err "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      if [[ -z "$INPUT_PATH" ]]; then
        INPUT_PATH="$1"
      else
        err "Unexpected extra argument: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$INPUT_PATH" ]]; then
  INPUT_PATH=$(prompt_for_path)
else
  INPUT_PATH=$(realpath "$INPUT_PATH")
fi

IFS=$'\t' read -r RESULTS_DIR BASE_DIR < <(resolve_results_dir "$INPUT_PATH")
OUT_DIR="$BASE_DIR/$OUT_NAME"

mapfile -d '' -t PDB_FILES < <(find "$RESULTS_DIR" -type f \( -iname '*.pdb' -o -iname '*.ent' \) -print0 | sort -z)
[[ ${#PDB_FILES[@]} -eq 0 ]] && { err "No PDB files found under $RESULTS_DIR"; exit 1; }

log "Input Results folder : $RESULTS_DIR"
log "Temporary output     : $OUT_DIR"
log "PDB files discovered : ${#PDB_FILES[@]}"

mapfile -t DUPLICATES < <(detect_duplicate_top_level_pdbs "$RESULTS_DIR")
if [[ ${#DUPLICATES[@]} -gt 0 ]]; then
  log ""
  log "Duplicate top-level PDBs found that also exist in cluster directories:"
  for dup in "${DUPLICATES[@]}"; do
    rel=${dup#"$RESULTS_DIR"/}
    log "  [duplicate] $rel"
  done
else
  log ""
  log "No duplicate top-level PDBs detected against cluster directories."
fi

if preview=$(preview_first_uncleaned "$RESULTS_DIR" "$PTC_RESNAME" 2>/dev/null); then
  rel=${preview%%$'\t'*}
  names=${preview#*$'\t'}
  rel=${rel#"$RESULTS_DIR"/}
  log ""
  log "Preview from first uncleaned file ($rel):"
  log "Will remove PTC carbons: $names (plus directly bonded hydrogens)"
else
  log ""
  log "Preview skipped: no uncleaned file with removable PTC carbons found."
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  log ""
  log "Dry run complete. No files written."
  exit 0
fi

[[ -e "$OUT_DIR" ]] && {
  err "Temporary output folder already exists: $OUT_DIR"
  err "Rename/remove it first, or rerun with a different --out-name."
  exit 1
}

cp -a "$RESULTS_DIR" "$OUT_DIR"

removed_duplicates=0
mapfile -t OUT_DUPLICATES < <(detect_duplicate_top_level_pdbs "$OUT_DIR")
for dup in "${OUT_DUPLICATES[@]}"; do
  rel=${dup#"$OUT_DIR"/}
  log "[deduplicated] removing top-level duplicate $rel"
  rm -f "$dup"
  removed_duplicates=$((removed_duplicates+1))
done

changed=0
skipped_already_cleaned=0
failed=0

while IFS= read -r -d '' dst_pdb; do
  tmpfile=$(mktemp)
  if status_output=$(clean_one_pdb "$dst_pdb" "$tmpfile" "$PTC_RESNAME" 2>&1); then
    mv "$tmpfile" "$dst_pdb"
    rel=${dst_pdb#"$OUT_DIR"/}
    if grep -q $'^STATUS\talready_cleaned$' <<< "$status_output"; then
      skipped_already_cleaned=$((skipped_already_cleaned+1))
      log "[skipped] $rel | already contains REMARK JARI-CLEANED"
    else
      changed=$((changed+1))
      details=$(grep $'^STATUS\tcleaned\t' <<< "$status_output" | tail -n1)
      removed_names=$(printf '%s' "$details" | awk -F'\t' '{print $3}')
      extra_h=$(printf '%s' "$details" | awk -F'\t' '{print $4}')
      log "[cleaned] $rel | removed $removed_names (+ $extra_h bonded H atoms) | added REMARK JARI-CLEANED"
    fi
  else
    rm -f "$tmpfile"
    failed=$((failed+1))
    rel=${dst_pdb#"$OUT_DIR"/}
    log "[failed]  $rel | $status_output"
  fi
done < <(find "$OUT_DIR" -type f \( -iname '*.pdb' -o -iname '*.ent' \) -print0 | sort -z)

log ""
log "Summary"
log "  Duplicate top-level files removed : $removed_duplicates"
log "  PDB files cleaned                 : $changed"
log "  Already-cleaned files skipped     : $skipped_already_cleaned"
log "  Files failed                      : $failed"
log "  Temporary cleaned folder          : $OUT_DIR"

if [[ "$KEEP_OLD_RESULTS" -eq 0 ]]; then
  swap_cleaned_into_results "$RESULTS_DIR" "$OUT_DIR"
  log ""
  log "Done. Final cleaned Results folder is now: $RESULTS_DIR"
else
  log ""
  log "Done. Original Results kept; cleaned copy remains at: $OUT_DIR"
fi
