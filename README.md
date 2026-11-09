# applyvarlabels - apply Stata variable labels from an Excel/CSV crosswalk

Label the variables in memory from a two-column **(Variable, Label)** crosswalk
held in Excel or a CSV. Matches every label to its variable **by name, never by
position**, writes a capture-guarded relabel do-file, runs it, and prints an
inventory of whatever did not line up.

## The problem it solves

You are handed a dataset with 100+ variables, **none of them labeled**, and a
separate spreadsheet listing each variable name beside the label it should
carry ([Statalist thread 1768839](https://www.statalist.org/forums/forum/general-stata-discussion/general/1768839)).
The intuitive loop fails:

```stata
import excel "labels.xlsx", sheet("var_labels") firstrow clear
levelsof Label, local(labels)     // <-- returns the labels sorted ALPHABETICALLY
use mydata, clear
ds _all
tokenize `r(varlist)'
foreach x of local labels {       // <-- so the wrong label lands on each variable
    lab var `1' "`x'"
    macro shift
}
```

`levelsof` returns the distinct labels sorted alphabetically, so pairing them
positionally with the variables lines them up in the wrong order. The fix is to
stop pairing by position and pair **by name** instead:

```stata
import excel "survey.xlsx", sheet("data") firstrow clear   // your unlabeled data
applyvarlabels using "survey.xlsx", sheet("var_labels")     // its labels, applied
```

```
------------------------------------------------------------------------
applyvarlabels  -  survey.xlsx
------------------------------------------------------------------------
labels applied: 13 of 14 variables in memory

crosswalk rows with no matching variable (2):
  q7_other income_2019

variables in memory with no crosswalk row (1):
  notes

the relabel do-file:
  >> click to VIEW the capture-guarded relabel do-file
  >> click to VIEW this inventory
------------------------------------------------------------------------
```

## What it does

1. **Reads the crosswalk in row order** from an `.xlsx`/`.xls` workbook or a
   `.csv`/`.tsv`/`.txt` file, in its own [frame](https://www.stata.com/help.cgi?frames)
   so your data in memory are never touched.
2. **Matches each label to its variable by name** (exact, or case-insensitively
   with `nocase`). Variable-name abbreviation is turned off during matching, so
   a crosswalk row `inc` never silently lands on a variable named `income`.
3. **Writes a capture-guarded relabel do-file** - one
   `capture label variable` line per match. `capture` means a variable named in
   the crosswalk but absent from the data is skipped, not an error, so the file
   is safe to rerun on any dataset that shares the names.
4. **Runs it** to apply the labels (unless you say `norun`).
5. **Prints an inventory** of everything that did not line up: crosswalk rows
   with no such variable, variables in memory with no crosswalk row, plus notes
   on duplicate rows, empty-label rows, and labels past Stata's 80-character
   limit - on screen and to a viewable `.smcl` file.

The generated do-file is a keepable, auditable, version-controllable artifact:
name it with `dofile()` and commit it next to your data-cleaning code.

## Install

`applyvarlabels` is self-contained - the command and its help file, with no
external Stata dependencies (Stata 16+).

```stata
net install applyvarlabels, from("https://raw.githubusercontent.com/ericabooth/applyvarlabels-stata-public/main/") replace force
help applyvarlabels
```

The package ships `applyvarlabels.pkg` and `stata.toc`, so Stata's installer
picks up the command and help in one call. To pull the worked example and the
example workbook alongside it, `net get` the ancillary files:

```stata
net get applyvarlabels, from("https://raw.githubusercontent.com/ericabooth/applyvarlabels-stata-public/main/")
do example_applyvarlabels.do
```

## The example workbook

`example_varlabels.xlsx` (regenerate with `python3 make_example_varlabels.py`;
the script lives in the GitHub repository and is not installed by `net install`
or `net get`) has two sheets, mirroring exactly how these data arrive:

- **`data`** - the first row is the variable names, the rows below are values.
  This is the unlabeled dataset.
- **`var_labels`** - the crosswalk: a `Variable` column and a `Label` column,
  one variable per row.

The crosswalk is deliberately imperfect so the example exercises the whole
inventory: two rows (`q7_other`, `income_2019`) name variables not in the data,
one data variable (`notes`) is missing from the crosswalk, and the labels
include an apostrophe, an ampersand, and one over 80 characters.

## Quick start

```stata
* headline case: data in memory, crosswalk on its own sheet
import excel using "survey.xlsx", sheet("data") firstrow clear
applyvarlabels using "survey.xlsx", sheet("var_labels")
```

```stata
* crosswalk columns named something else
applyvarlabels using "labels.xlsx", variable(varname) label(description)
```

```stata
* a CSV crosswalk; importer is chosen from the extension
applyvarlabels using "labels.csv"
```

```stata
* names that differ only in case
applyvarlabels using "labels.xlsx", nocase
```

```stata
* keep the relabel do-file; dry-run first, inspect, then apply
applyvarlabels using "labels.xlsx", norun dofile("relabel_survey.do") replace
do "relabel_survey.do"
```

## Syntax

```
applyvarlabels using crosswalkfile [, variable(name) label(name) sheet(name)
    nocase dofile(filename) norun smcl(filename) replace]
```

`crosswalkfile` is the Excel or delimited file with a variable-name column and a
label column. The dataset to label must already be in memory. See
`help applyvarlabels` for every option.

## Stored results

| Result | Meaning |
| ------ | ------- |
| `r(N_variables)` | variables in memory |
| `r(N_applied)` | variables that received a label |
| `r(N_nomatch)` | crosswalk rows with no matching variable |
| `r(N_nolabel)` | variables in memory with no crosswalk row |
| `r(N_normalized)` | labels altered for Stata (straight quotes, backticks, line breaks) |
| `r(N_long)` | labels over 80 characters (truncated by Stata) |
| `r(applied)` | variables that received a label |
| `r(nomatch)` | crosswalk names not found in memory |
| `r(nolabel)` | variables in memory with no crosswalk row |
| `r(dups)` | variables named more than once (last label wins) |
| `r(blanks)` | variables whose crosswalk label cell was empty |
| `r(normalized)` | variables whose label was altered for Stata (curly quotes, apostrophes, spaces for line breaks) |
| `r(dofile)` | path of the generated relabel do-file |
| `r(smcl)` | path of the inventory `.smcl` file |

## Design notes (v1.0.1)

- **Matching is exact by default** (Stata is case-sensitive); `nocase` relaxes
  it, and the generated do-file then uses the variable's real spelling so
  `capture` never misfires. Leading/trailing spaces in the crosswalk are
  trimmed.
- **Labels are capped at 80 characters** by Stata; longer labels are applied
  truncated and counted in `r(N_long)`.
- **Special characters.** Apostrophes, ampersands, and dollar signs are
  preserved exactly (a `$name` is escaped in the generated do-file so it is not
  macro-expanded when the file runs). Three characters a Stata label cannot
  carry are normalized and reported in `r(normalized)`: a straight double-quote
  (`"`, which `label variable` cannot parse) becomes a curly quote, a backtick
  (`` ` ``, which would start a macro reference when the do-file runs) becomes an
  apostrophe, and a line break inside a cell (Excel Alt+Enter) becomes a space.
  A `.csv` crosswalk is read with `bindquote(strict)`, so a quoted multi-line
  label stays in one cell.
- **A failed relabel run is reported honestly.** If the do-file stops part way,
  the labels are rechecked on the data and only those actually applied are
  counted in `r(N_applied)`; your `varabbrev` setting is restored on every exit.
- **Nothing else changes**: the data keep their observations, sort order, and
  variable order; only variable labels are touched, and only for matched
  variables.
- **The crosswalk can be broader than the data.** Extra rows (variables dropped
  upstream, a superset codebook) apply cleanly to whatever is present and are
  reported in `r(nomatch)` rather than raising an error.

## Changes

- **1.0.1 (2026-11-09):** a line break inside a crosswalk label is normalized
  to a space (and reported in `r(normalized)`); in 1.0.0 it split the written
  do-file line, the do-file stopped part way, and later labels were left
  unapplied while still being counted. A `.csv` crosswalk is read with
  `bindquote(strict)`. `varabbrev` is restored after an unexpected error. The
  importer's `(N vars, N obs)` echo is no longer printed. The help now says the
  do-file holds one line per matched variable. `make_example_varlabels.py` is
  no longer in the package manifest (it stays in the repository).
- **1.0.0 (2026-07-18):** first public release.

## Author and license

Eric A. Booth, Sr Researcher, Texas 2036 (eric.a.booth@gmail.com).

MIT. See [LICENSE](LICENSE). Copyright (c) 2026 Eric A. Booth.
