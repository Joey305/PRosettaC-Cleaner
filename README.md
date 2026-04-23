# 🔬 PRosettaC-Cleaner

> A lightweight post-processing utility for cleaning **PRosettaC ternary complex outputs** and preparing them for downstream analysis.

---

## 🚀 Overview

`clean_ptc_results.py` is a workflow-specific cleanup tool designed for **PRosettaC output folders generated on Pegasus2 at IDSC**.

It operates on the standard `Results/` directory and performs a **complete post-processing cleanup** of PRosettaC outputs by:

- trimming residual linker/construction atoms from the `PTC` residue
- removing attached hydrogens from those deleted atoms
- preserving valid connectivity records
- removing redundant unclustered files when the same structure already exists inside a cluster directory

⚠️ This is **not** a general-purpose PDB cleaner. It exists for a very specific and practical cleanup stage in the PRosettaC workflow.

---

## 🧠 Why this script exists

During the PRosettaC workflow, PROTAC molecules are constructed and positioned using **virtual atoms** and an extended representation of the linker. These virtual atoms are useful during modeling because they help:

- define anchor geometry between the two ligand heads
- guide conformational sampling
- center and orient the PROTAC correctly in the ternary complex

These modeling aids are important **during PRosettaC generation**, but they are not meant to remain part of the final chemically meaningful structure.

By the time PRosettaC writes the final PDB files into the `Results/` directory, the geometry-building step is already complete. However, residual atoms from that construction strategy can still persist in the final `PTC` residue representation.

This script removes those leftover atoms so the final models are cleaner and more appropriate for:

- downstream structural analysis
- docking evaluation
- molecular dynamics preparation
- visualization and figure generation

---

## ⚠️ What gets cleaned up

### 1. `PTC` linker artifact cleanup

For each PRosettaC result structure, the script:

- identifies the `PTC` residue
- finds the **three highest-numbered carbon atoms** in that residue
- removes those terminal carbons
- removes any directly bonded hydrogens attached to those deleted carbons
- rewrites `CONECT` records so the structure remains internally consistent

These terminal carbons correspond to the residual atoms left behind from the virtual-atom / construction representation used during PRosettaC setup and placement.

---

### 2. Cluster-aware duplicate cleanup

In addition to structural cleanup, the script also performs **file-level cleanup** across the PRosettaC `Results/` tree.

If a file with the **same exact filename** exists:

- at the top level of `Results/`, and
- inside a cluster directory such as `cluster1/`, `cluster2/`, etc.

then the top-level unclustered copy is removed.

This means clustered results are treated as the **canonical retained outputs**, and redundant unclustered duplicates are discarded.

✅ In practice, this makes the tool a more **complete cleanup utility for PRosettaC outputs**, not just a ligand-editing script.

---

## ✅ Final outcome

After running the script, your `Results/` directory is cleaned so that it is:

- free of leftover virtual-atom-derived terminal linker artifacts
- stripped of redundant unclustered duplicates when clustered copies exist
- more compact, consistent, and ready for downstream workflows

---

## 📁 Intended environment

This script was written specifically for:

- **PRosettaC outputs**
- generated on **Pegasus2**
- from **IDSC workflows**
- using the standard PRosettaC-style `Results/` directory structure

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

- the full path to the **job directory** containing `Results/`, or
- the full path directly to the **`Results/`** folder

When run without a path, it can also list directories in the current working directory and let you select one interactively by numeric index.

---

## 📥 Installation / Download

Clone the repository:

```bash
git clone https://github.com/Joey305/PRosettaC-Cleaner.git
cd PRosettaC-Cleaner
```

No additional dependencies are required beyond standard Python.

---

## 🧑‍💻 Usage

### Interactive mode

```bash
python clean_ptc_results.py
```

This will:

- print directories in your current working directory
- let you choose one by numeric index
- or allow you to enter a full path manually

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

### Keep old results

```bash
python clean_ptc_results.py --keep-old-results
```

Use this if you want to preserve the original `Results/` folder instead of replacing it.

---

## ⚙️ What the script does

1. Accepts a target directory interactively or by full path
2. Resolves the correct `Results/` directory
3. Creates a cleaned copy of the results
4. For every `.pdb` file under `Results/`, it:
   - finds residue `PTC`
   - identifies the three highest-numbered carbon atoms
   - removes those atoms
   - removes directly bonded hydrogens via `CONECT`
   - rewrites connectivity records to remain consistent
5. Scans for duplicate filenames across clustered and unclustered outputs
6. Removes redundant top-level files if the same filename exists inside a cluster directory
7. Replaces the old `Results/` folder with the cleaned version

Final state:

- original `Results/` is removed (unless preservation is requested)
- cleaned directory is renamed back to `Results/`

This allows downstream scripts to continue using the expected `Results` name without modification.

---

## ⚠️ Important assumptions

This script assumes:

- the ligand residue name is `PTC`
- the atoms to remove are the **three highest-numbered carbon atoms** in that residue
- those carbons are named in a numbered format such as `C47`, `C48`, `C49`
- PRosettaC output PDBs contain usable `CONECT` records for hydrogen cleanup
- duplicate file cleanup is based on **exact filename matches** between top-level and clustered outputs

If your output format differs from the standard PRosettaC Pegasus2/IDSC convention, inspect a few files manually before applying the script broadly.

---

## 🛡️ Safety notes

- This is a **workflow-specific post-processing utility**, not a general structure editor
- Always test on a small example first
- Use `--dry-run` before bulk cleanup if you want to confirm what will be removed
- If you are preparing a public repository, it can be helpful to include example input/output trees or screenshots

---

## 📌 GitHub repository description

> Post-processing utility for PRosettaC outputs that removes virtual-atom-derived linker artifacts and redundant unclustered duplicates from final `Results` PDB structures.

---

## 🧾 Provenance note

This repository contains workflow-specific post-processing scripts developed for handling PRosettaC output structures generated on Pegasus2 at IDSC.

These scripts are:

- tailored to local PRosettaC workflow conventions
- intended for Pegasus2 / IDSC-generated output trees
- **not** part of the official PRosettaC distribution
