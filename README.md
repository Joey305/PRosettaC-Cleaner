# clean_ptc_results

`clean_ptc_results.py` is a small post-processing utility for **PRosettaC output folders generated on Pegasus2 at IDSC**. It is designed specifically for the `Results` directory structure produced by PRosettaC runs in that environment, where the final modeled ternary-complex PDB files are written as clustered and unclustered `combined_*.pdb` structures.

This script is **not intended as a general PDB cleaner**. It exists for one very specific cleanup step in this workflow:

- identify the `PTC` residue in each PRosettaC result structure
- remove the **last three carbon atoms** from that `PTC` ligand (the highest-numbered `C##` atoms)
- remove any directly bonded hydrogens attached to those deleted carbons
- preserve the full `Results` folder layout
- replace the original `Results` folder with the cleaned version

---

## Why this script exists

In the PRosettaC workflow, PROTAC conformers are generated and positioned using **virtual atoms** as geometric reference points. These virtual atoms help define anchor locations and orient the PROTAC correctly between the two ligand heads during sampling, alignment, and model construction. In practice, they help **center and place the PROTAC in the intended ternary-complex geometry** while the workflow is building candidate structures.

By the time you are running this script, that stage is already complete.

At the `Results` stage, PRosettaC has already used those geometric/placement conventions to produce final combined models. The extra terminal carbons in the `PTC` residue are no longer needed for placement or centering at this point, so this script removes them from the final output models as a **post-processing cleanup step**.

In other words:

- **during PRosettaC**: the virtual/placement representation is useful for building and centering the PROTAC
- **at this cleanup stage**: that job is already done, and the final `Results` models can be trimmed for downstream use

---

## Intended environment

This script was written for:

- **PRosettaC outputs**
- run on **Pegasus2**
- from **IDSC**
- with a job directory containing a `Results/` folder like the standard PRosettaC output tree

Typical example:

```text
JARI-04212026-1/
├── Results/
│   ├── cluster1/
│   ├── cluster2/
│   ├── ...
│   ├── combined_2_17_0001.pdb
│   ├── combined_11_4_0001.pdb
│   └── ...
├── PT0.params
├── PT1.params
├── Ligase.pdb
├── Warhead.pdb
└── ...
```

The script expects either:

- the full path to the **job directory** that contains `Results/`, or
- the full path directly to the **Results** folder itself

When run interactively with no path argument, it can also list directories in your **current working directory** and let you choose one by numeric index.

---

## What the script does

1. Accepts a target directory interactively or by full path.
2. Resolves the correct `Results/` directory.
3. Creates a cleaned copy of the results.
4. For every `.pdb` file under `Results/`, it:
   - finds residue `PTC`
   - identifies the three highest-numbered carbon atoms named like `C47`, `C48`, `C49`
   - removes those atoms
   - removes directly bonded hydrogens connected through `CONECT` records
   - rewrites `CONECT` records to stay consistent
5. Replaces the old `Results/` folder with the cleaned one.

Final state:

- original `Results/` is removed
- cleaned directory is renamed back to `Results/`

This means downstream scripts can keep using the normal `Results` name without modification.

---

## Usage

### Interactive mode

```bash
python clean_ptc_results.py
```

This will:

- print directories in your current working directory with numeric indices
- let you choose by index
- or let you enter a full path manually

### Direct path mode

```bash
python clean_ptc_results.py /full/path/to/JARI-04212026-1
```

or

```bash
python clean_ptc_results.py /full/path/to/JARI-04212026-1/Results
```

### Dry run

```bash
python clean_ptc_results.py --dry-run
```

This previews what would be removed without writing changes.

### Keep the old Results folder

```bash
python clean_ptc_results.py --keep-old-results
```

Use this if you want to preserve the old results instead of replacing them.

---

## Important assumptions

This script assumes:

- the ligand residue name is `PTC`
- the atoms to remove are the **three highest-numbered carbon atoms** in that residue
- those carbons are named in a numbered format like `C47`, `C48`, `C49`
- PRosettaC output PDBs contain valid enough `CONECT` records for attached hydrogen cleanup

If your output format differs from the standard PRosettaC Pegasus2/IDSC convention, inspect a few files first before using the script broadly.

---

## Safety notes

- The script is workflow-specific and should be treated as a **post-processing utility**, not a general structure editor.
- Always test on a small example first.
- Use `--dry-run` before bulk cleanup if you want to confirm the detected atoms.
- If you are preparing a public repository, it is a good idea to include a small example tree or screenshots of expected input/output structure.

---

## Suggested GitHub repo description

> Post-processing utilities for PRosettaC output structures generated on Pegasus2 at IDSC, including cleanup of terminal PTC atoms in final `Results` PDB models.

---

## Suggested citation / provenance note for the repo

If you publish this script in a repository, it helps to state clearly that it is:

- built for your local PRosettaC workflow conventions
- intended for Pegasus2/IDSC-generated output trees
- not an official PRosettaC utility

Example wording:

> This repository contains workflow-specific post-processing scripts developed for handling PRosettaC output structures generated on Pegasus2 at IDSC. These scripts are not part of the official PRosettaC distribution.
# PRosettaC-Cleaner
