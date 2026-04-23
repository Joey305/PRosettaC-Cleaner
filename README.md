# 🔬 PRosettaC-Cleaner

> A workflow-specific post-processing utility for **PRosettaC** output folders generated on **Pegasus2 / IDSC**.

---

## 🚀 Overview

`clean_ptc_results.py` is a targeted cleanup script for PRosettaC `Results/` directories. It was built to handle the final modeled ternary-complex PDB outputs produced by this workflow and to make them more suitable for downstream analysis.

This script is **not** a general-purpose PDB cleaner. It is designed specifically for a PRosettaC post-processing step in which:

- duplicate top-level result files are removed if the same filename already exists in a cluster directory
- residual `PTC` construction atoms are trimmed from the final models
- a `REMARK JARI-CLEANED` tag is inserted so already-processed files can be identified and skipped in future runs

---

## 🧠 Why this script exists

During PRosettaC, the PROTAC is constructed and positioned using a modeling representation that includes **virtual atoms / extended construction atoms** to help define geometry, anchor placement, and linker orientation.

Those atoms are useful **during model generation**, but they are not intended to remain as meaningful chemistry in the final cleaned structures used for downstream work.

In practice, some of those construction-related atoms persist in the final `PTC` residue inside the output PDB files. This script removes the **last three highest-numbered carbon atoms** from `PTC`, along with any directly bonded hydrogens, to produce cleaner structures for analysis.

At the same time, it also removes redundant unclustered files and marks cleaned files so users do not accidentally process the same structures twice.

---

## ✅ What the script does

### 1. Duplicate detection before cleanup
Before performing atom cleanup, the script checks whether a PDB file in the **top-level `Results/` directory** has the same filename as a PDB already present in a **cluster directory** such as `cluster1/`, `cluster2/`, etc.

If the same filename exists in a cluster directory, the top-level file is treated as redundant and removed from the cleaned output.

This helps avoid:

- redundant downstream analysis
- duplicate counting of the same structure
- wasted compute and confusion when comparing clustered vs unclustered outputs

### 2. PTC cleanup
For each remaining PDB file, the script:

- finds residue `PTC`
- identifies the **three highest-numbered carbon atoms** (`C##`)
- removes those atoms
- removes any directly bonded hydrogens via `CONECT`
- rewrites `CONECT` records to stay consistent

### 3. Anti-double-cleaning safeguard
After a file is successfully cleaned, the script inserts:

```text
REMARK JARI-CLEANED
```

directly under the `EXPDTA` line when present.

On future runs, if a file already contains this remark, the script recognizes that it has already been processed and skips it.

This prevents accidental re-cleaning and helps users avoid double-analysis of the same structures.

---

## 🖼️ Example workflow screenshots

The following screenshots document the key stages of the script and should be included in the repository under `assets/`.

### ▶️ Running the script and initial duplicate scan

This screenshot shows the script being launched, the `Results/` folder being detected, and the initial duplicate scan being reported.

![Script start and duplicate scan](assets/scriptstart-duplicates.png)

---

### 🔍 Duplicate detection output

This screenshot shows the script identifying top-level files whose names also exist in cluster directories. These are the files that will be removed before the structural cleanup step.

![Duplicate detection output](assets/scriptdupedetect.png)

---

### 🧹 Deduplication and main cleanup pass

This screenshot shows the script actively removing duplicate top-level files and then proceeding into the main cleaning pass.

![Deduplication and cleanup pass](assets/scriptstart-dedupes.png)

---

### 🧬 Atom removal + REMARK insertion

This screenshot shows the core cleaning behavior: removal of the terminal `PTC` carbons and insertion of `REMARK JARI-CLEANED`, which is used to prevent accidental double-processing later.

![PTC cleanup and REMARK insertion](assets/scriptclean-addremark.png)

---

## 🛡️ How duplicate prevention works

There are **two layers** of duplicate prevention in this script:

### A. Cluster-aware file deduplication
If:

```text
Results/combined_11_14_0001.pdb
```

also exists as:

```text
Results/cluster1/combined_11_14_0001.pdb
```

then the **top-level version** is removed from the cleaned output.

This prevents users from analyzing both the clustered and unclustered copy of the same structure.

### B. `REMARK JARI-CLEANED` detection
If a file already contains:

```text
REMARK JARI-CLEANED
```

the script treats it as already processed and skips it.

This prevents users from:

- cleaning the same file twice
- deleting the terminal `PTC` carbons again
- accidentally mixing previously cleaned files into a fresh cleanup run

---

## 📁 Expected directory structure

Typical input:

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

The script accepts either:

- the path to the **job directory** containing `Results/`
- or the path directly to the **`Results/` folder**

---

## 📥 Installation / Download

Clone the repository:

```bash
git clone https://github.com/Joey305/PRosettaC-Cleaner.git
cd PRosettaC-Cleaner
```

No third-party dependencies are required beyond standard Python.

---

## 🧑‍💻 Usage

### Interactive mode

```bash
python clean_ptc_results.py
```

This will:

- list directories in your current working directory
- allow selection by index
- or allow entry of a full path manually

### Direct path mode

```bash
python clean_ptc_results.py /full/path/to/job_directory
```

or

```bash
python clean_ptc_results.py /full/path/to/job_directory/Results
```

### Dry run

```bash
python clean_ptc_results.py --dry-run
```

This previews the duplicate detection and cleanup logic without writing changes.

### Keep original Results folder

```bash
python clean_ptc_results.py --keep-old-results
```

This keeps the original `Results/` folder and leaves the cleaned output as a separate folder.

---

## ⚠️ Important assumptions

This script assumes:

- the ligand residue name is `PTC`
- the atoms to remove are the **three highest-numbered carbon atoms**
- those atoms follow a numbered naming convention such as `C47`, `C48`, `C49`
- `CONECT` records are present and usable for attached-hydrogen cleanup
- duplicate removal is based on **filename match** between top-level `Results/` and cluster directories

If your output differs from the standard PRosettaC Pegasus2 / IDSC conventions, inspect your files first before running broad cleanup.

---

## 🔄 Final output behavior

After the script finishes:

- duplicate top-level files that already exist in clusters are removed
- terminal `PTC` construction carbons are removed
- attached hydrogens are removed
- `CONECT` records are updated
- cleaned files are tagged with `REMARK JARI-CLEANED`

By default, the script then:

- replaces the original `Results/` folder with the cleaned version

This means downstream tools can continue using the normal `Results/` name without modification.

---

## 🧾 Repository description

> Post-processing utility for PRosettaC outputs that removes duplicate unclustered files, trims virtual-atom-derived `PTC` construction artifacts, and marks cleaned structures to prevent accidental double-processing.

---

## 📌 Provenance note

This repository contains workflow-specific utilities developed for handling PRosettaC output structures generated on Pegasus2 at IDSC.

These scripts are:

- specific to this PRosettaC workflow
- not part of the official PRosettaC distribution
- intended for post-processing and downstream analysis preparation
