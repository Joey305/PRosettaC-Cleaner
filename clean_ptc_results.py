#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Set, Tuple

ATOM_RECORDS = {"ATOM  ", "HETATM"}
PDB_SUFFIXES = {".pdb", ".ent"}
CLEAN_REMARK = "REMARK JARI-CLEANED\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Recursively clean PRosettaC Results folders by first removing duplicate "
            "top-level PDBs that already exist inside cluster directories, then "
            "removing the three highest-numbered carbon atoms from residue PTC and "
            "any directly bonded hydrogens. Adds a REMARK JARI-CLEANED flag so files "
            "are not cleaned twice."
        )
    )
    parser.add_argument(
        "path",
        nargs="?",
        help=(
            "Full path to a job directory that contains a Results folder, or directly "
            "to the Results folder itself. If omitted, you can choose from folders in "
            "the current working directory."
        ),
    )
    parser.add_argument(
        "--ptc-resname",
        default="PTC",
        help="Residue name to clean (default: PTC)",
    )
    parser.add_argument(
        "--out-name",
        default="Results_Cleaned",
        help="Temporary output folder name created beside Results (default: Results_Cleaned)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview what would be cleaned without writing output files.",
    )
    parser.add_argument(
        "--keep-old-results",
        action="store_true",
        help="Keep the original Results folder and do not swap Results_Cleaned back to Results.",
    )
    return parser.parse_args()


def list_cwd_directories() -> List[Path]:
    cwd = Path.cwd()
    return sorted([p for p in cwd.iterdir() if p.is_dir()], key=lambda p: p.name.lower())


def prompt_for_path() -> Path:
    cwd = Path.cwd()
    dirs = list_cwd_directories()

    print(f"Current working directory: {cwd}")
    if dirs:
        print("\nFolders in current working directory:")
        for idx, folder in enumerate(dirs):
            marker = " [contains Results]" if (folder / "Results").is_dir() else ""
            print(f"  {idx}: {folder.name}{marker}")
    else:
        print("\nNo folders found in the current working directory.")

    print("\nChoose one of the following:")
    print("  - Enter an index from the list above")
    print("  - Enter a full path to a job directory or directly to a Results folder")

    raw = input("Selection or full path: ").strip().strip('"').strip("'")
    if not raw:
        raise SystemExit("No selection/path provided. Exiting.")

    if raw.isdigit():
        idx = int(raw)
        if idx < 0 or idx >= len(dirs):
            raise SystemExit(f"Invalid index: {idx}")
        return dirs[idx].resolve()

    return Path(raw).expanduser().resolve()


def resolve_results_dir(user_path: Path) -> Tuple[Path, Path]:
    if not user_path.exists():
        raise FileNotFoundError(f"Path does not exist: {user_path}")

    if user_path.is_dir() and user_path.name == "Results":
        return user_path, user_path.parent

    results_dir = user_path / "Results"
    if results_dir.is_dir():
        return results_dir, user_path

    raise FileNotFoundError(
        f"Could not find a Results folder at {user_path} or {user_path / 'Results'}"
    )


def is_atom_or_hetatm(line: str) -> bool:
    return len(line) >= 6 and line[:6] in ATOM_RECORDS


def atom_serial(line: str) -> int:
    return int(line[6:11])


def atom_name(line: str) -> str:
    return line[12:16].strip()


def resname(line: str) -> str:
    return line[17:20].strip()


def element(line: str) -> str:
    if len(line) >= 78:
        elem = line[76:78].strip()
        if elem:
            return elem
    name = atom_name(line)
    letters = "".join(ch for ch in name if ch.isalpha())
    return letters[:1].upper() if letters else ""


def carbon_index_from_name(name: str) -> int | None:
    m = re.fullmatch(r"C(\d+)", name)
    if not m:
        return None
    return int(m.group(1))


def parse_conect(lines: Iterable[str]) -> Dict[int, Set[int]]:
    bonds: Dict[int, Set[int]] = {}
    for line in lines:
        if not line.startswith("CONECT"):
            continue
        ints: List[int] = []
        for start in range(6, len(line), 5):
            field = line[start : start + 5].strip()
            if field:
                try:
                    ints.append(int(field))
                except ValueError:
                    pass
        if not ints:
            continue
        src, *neighbors = ints
        bonds.setdefault(src, set()).update(neighbors)
        for nbr in neighbors:
            bonds.setdefault(nbr, set()).add(src)
    return bonds


def is_cluster_path(path: Path) -> bool:
    return any(part.lower().startswith("cluster") for part in path.parts)


def detect_duplicate_top_level_pdbs(results_dir: Path) -> List[Path]:
    """
    Remove top-level Results/*.pdb files if the same filename appears anywhere
    inside a cluster directory under Results/.
    """
    top_level_files = {
        p.name: p
        for p in results_dir.iterdir()
        if p.is_file() and p.suffix.lower() in PDB_SUFFIXES
    }

    clustered_names: Set[str] = set()
    for p in results_dir.rglob("*"):
        if not p.is_file() or p.suffix.lower() not in PDB_SUFFIXES:
            continue
        rel = p.relative_to(results_dir)
        if is_cluster_path(rel.parent):
            clustered_names.add(p.name)

    duplicates = [path for name, path in top_level_files.items() if name in clustered_names]
    return sorted(duplicates, key=lambda p: p.name.lower())


def has_clean_remark(lines: List[str]) -> bool:
    return any(line.strip() == "REMARK JARI-CLEANED" for line in lines)


def insert_clean_remark(lines: List[str]) -> List[str]:
    if has_clean_remark(lines):
        return lines

    expdta_idx = next((i for i, line in enumerate(lines) if line.startswith("EXPDTA")), None)
    if expdta_idx is not None:
        return lines[: expdta_idx + 1] + [CLEAN_REMARK] + lines[expdta_idx + 1 :]

    header_idx = next((i for i, line in enumerate(lines) if line.startswith("HEADER")), None)
    if header_idx is not None:
        return lines[: header_idx + 1] + [CLEAN_REMARK] + lines[header_idx + 1 :]

    return [CLEAN_REMARK] + lines


def identify_atoms_to_remove(lines: List[str], ptc_resname: str) -> Tuple[List[Tuple[int, str]], Set[int]]:
    ptc_carbons: List[Tuple[int, int, str]] = []
    serial_to_line: Dict[int, str] = {}

    for line in lines:
        if not is_atom_or_hetatm(line):
            continue
        serial = atom_serial(line)
        serial_to_line[serial] = line
        if resname(line) != ptc_resname:
            continue
        idx = carbon_index_from_name(atom_name(line))
        if idx is not None:
            ptc_carbons.append((idx, serial, atom_name(line)))

    if len(ptc_carbons) < 3:
        raise ValueError(
            f"Found fewer than 3 numbered carbon atoms in residue {ptc_resname}."
        )

    ptc_carbons.sort(key=lambda x: x[0])
    selected = ptc_carbons[-3:]
    remove_serials: Set[int] = {serial for _, serial, _ in selected}

    bonds = parse_conect(lines)
    for serial in list(remove_serials):
        for nbr in bonds.get(serial, set()):
            nbr_line = serial_to_line.get(nbr)
            if not nbr_line:
                continue
            if resname(nbr_line) == ptc_resname and element(nbr_line).upper() == "H":
                remove_serials.add(nbr)

    removed_named = [(serial, name) for _, serial, name in sorted(selected, key=lambda x: x[0])]
    return removed_named, remove_serials


def clean_pdb_lines(
    lines: List[str],
    ptc_resname: str,
) -> Tuple[List[str], List[Tuple[int, str]], Set[int], bool]:
    """
    Returns:
        cleaned_lines,
        removed_named,
        remove_serials,
        already_cleaned
    """
    already_cleaned = has_clean_remark(lines)
    if already_cleaned:
        return lines, [], set(), True

    removed_named, remove_serials = identify_atoms_to_remove(lines, ptc_resname)

    cleaned: List[str] = []
    for line in lines:
        if is_atom_or_hetatm(line) and atom_serial(line) in remove_serials:
            continue

        if line.startswith("ANISOU"):
            try:
                if int(line[6:11]) in remove_serials:
                    continue
            except ValueError:
                pass

        if line.startswith("CONECT"):
            ints: List[int] = []
            for start in range(6, len(line), 5):
                field = line[start : start + 5].strip()
                if field:
                    try:
                        ints.append(int(field))
                    except ValueError:
                        pass

            if ints:
                src, *neighbors = ints
                if src in remove_serials:
                    continue

                kept_neighbors = [n for n in neighbors if n not in remove_serials]
                if kept_neighbors:
                    rebuilt = f"CONECT{src:5d}" + "".join(f"{n:5d}" for n in kept_neighbors)
                    cleaned.append(rebuilt + "\n")
                continue

        cleaned.append(line)

    cleaned = insert_clean_remark(cleaned)
    return cleaned, removed_named, remove_serials, False


def clean_pdb_file(
    src: Path,
    dst: Path,
    ptc_resname: str,
) -> Tuple[List[Tuple[int, str]], Set[int], bool]:
    text = src.read_text(errors="ignore")
    lines = text.splitlines(keepends=True)
    cleaned, removed_named, remove_serials, already_cleaned = clean_pdb_lines(lines, ptc_resname)
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text("".join(cleaned))
    return removed_named, remove_serials, already_cleaned


def swap_cleaned_into_results(results_dir: Path, out_dir: Path) -> None:
    backup_dir = results_dir.parent / "Results_Original_Backup"
    if backup_dir.exists():
        raise FileExistsError(
            f"Backup folder already exists: {backup_dir}. Remove/rename it before swapping."
        )
    if results_dir.exists():
        print(f"Moving original Results -> {backup_dir.name}")
        results_dir.rename(backup_dir)
    print(f"Renaming {out_dir.name} -> Results")
    out_dir.rename(results_dir)
    print(f"Deleting backup folder: {backup_dir}")
    shutil.rmtree(backup_dir)


def main() -> int:
    args = parse_args()
    user_path = Path(args.path).expanduser().resolve() if args.path else prompt_for_path()

    results_dir, base_dir = resolve_results_dir(user_path)
    out_dir = base_dir / args.out_name

    pdb_files = sorted(
        p for p in results_dir.rglob("*")
        if p.is_file() and p.suffix.lower() in PDB_SUFFIXES
    )

    if not pdb_files:
        raise FileNotFoundError(f"No PDB files found under {results_dir}")

    print(f"Input Results folder : {results_dir}")
    print(f"Temporary output     : {out_dir}")
    print(f"PDB files discovered : {len(pdb_files)}")

    duplicates = detect_duplicate_top_level_pdbs(results_dir)
    if duplicates:
        print("\nDuplicate top-level PDBs found that also exist in cluster directories:")
        for dup in duplicates:
            print(f"  [duplicate] {dup.relative_to(results_dir)}")
    else:
        print("\nNo duplicate top-level PDBs detected against cluster directories.")

    preview_removed: List[Tuple[int, str]] | None = None
    preview_total_removed = None
    preview_source = None

    for first_pdb in pdb_files:
        lines = first_pdb.read_text(errors="ignore").splitlines(keepends=True)
        if has_clean_remark(lines):
            continue
        try:
            preview_removed, remove_serials = identify_atoms_to_remove(lines, args.ptc_resname)
            preview_total_removed = len(remove_serials)
            preview_source = first_pdb
            break
        except Exception:
            continue

    if preview_removed and preview_source:
        print(
            "\nPreview from first uncleaned file "
            f"({preview_source.relative_to(results_dir)}):\n"
            "Will remove PTC carbons: "
            + ", ".join(name for _, name in preview_removed)
            + f" (plus directly bonded hydrogens; total atoms removed typically {preview_total_removed})"
        )
    else:
        print("\nPreview skipped: no uncleaned file with removable PTC carbons found.")

    if args.dry_run:
        print("\nDry run complete. No files written.")
        return 0

    if out_dir.exists():
        raise FileExistsError(
            f"Temporary output folder already exists: {out_dir}\n"
            f"Rename/remove it first, or rerun with a different --out-name."
        )

    shutil.copytree(results_dir, out_dir)

    removed_duplicates = 0
    for dup_src in detect_duplicate_top_level_pdbs(out_dir):
        print(f"[deduplicated] removing top-level duplicate {dup_src.relative_to(out_dir)}")
        dup_src.unlink()
        removed_duplicates += 1

    changed = 0
    skipped_already_cleaned = 0
    failed = 0

    for dst_pdb in sorted(out_dir.rglob("*")):
        if not dst_pdb.is_file() or dst_pdb.suffix.lower() not in PDB_SUFFIXES:
            continue

        try:
            removed_named, remove_serials, already_cleaned = clean_pdb_file(
                dst_pdb, dst_pdb, args.ptc_resname
            )

            if already_cleaned:
                skipped_already_cleaned += 1
                print(f"[skipped] {dst_pdb.relative_to(out_dir)} | already contains REMARK JARI-CLEANED")
                continue

            changed += 1
            removed_names = ", ".join(name for _, name in removed_named)
            extra_h = len(remove_serials) - len(removed_named)
            print(
                f"[cleaned] {dst_pdb.relative_to(out_dir)} | removed {removed_names} "
                f"(+ {extra_h} bonded H atoms) | added REMARK JARI-CLEANED"
            )

        except Exception as exc:
            failed += 1
            print(f"[failed]  {dst_pdb.relative_to(out_dir)} | {exc}")

    print("\nSummary")
    print(f"  Duplicate top-level files removed : {removed_duplicates}")
    print(f"  PDB files cleaned                 : {changed}")
    print(f"  Already-cleaned files skipped     : {skipped_already_cleaned}")
    print(f"  Files failed                      : {failed}")
    print(f"  Temporary cleaned folder          : {out_dir}")

    if not args.keep_old_results:
        swap_cleaned_into_results(results_dir, out_dir)
        print(f"\nDone. Final cleaned Results folder is now: {results_dir}")
    else:
        print(f"\nDone. Original Results kept; cleaned copy remains at: {out_dir}")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)