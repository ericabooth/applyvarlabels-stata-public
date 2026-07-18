*! test_applyvarlabels.do -- assertion battery for -applyvarlabels-
*! ----------------------------------------------------------------------------
*!  Run from the package directory:   do test_applyvarlabels.do
*!  Every check is an -assert-; the do-file stops on the first failure.  A
*!  final line prints ALL TESTS PASSED when the battery completes.
*! ----------------------------------------------------------------------------
version 16
clear all
set more off

local pkgdir "`c(pwd)'"
adopath ++ "`pkgdir'"
capture program drop applyvarlabels
local xlsx "`pkgdir'/example_varlabels.xlsx"
capture confirm file "`xlsx'"
if _rc {
    di as err "example_varlabels.xlsx not found -- run make_example_varlabels.py first"
    exit 601
}
tempfile scratch
local nfail 0

* ============================================================================
* TEST 1 -- the headline case: apply from the shipped var_labels sheet
* ============================================================================
import excel using "`xlsx'", sheet("data") firstrow clear
applyvarlabels using "`xlsx'", sheet("var_labels")

assert "`: variable label age'"    == "Respondent's age at last birthday"   // apostrophe
assert "`: variable label q7'"     == "Q7: satisfaction with local schools & services" // ampersand
assert "`: variable label income'" == "Annual household income in dollars"
assert "`: variable label notes'"  == "notes"          // untouched (import artifact = varname)
assert r(N_applied)  == 13
assert r(N_nomatch)  == 2
assert r(N_nolabel)  == 1
assert "`r(nolabel)'" == "notes"
* order-independent membership checks on the not-found list
local nomatch `r(nomatch)'
assert `: list posof "q7_other"    in nomatch'
assert `: list posof "income_2019" in nomatch'
assert r(N_variables) == 14
di as res ">> TEST 1 passed (headline apply, apostrophe + ampersand preserved)"

* ============================================================================
* TEST 2 -- matching is BY NAME, not by row order (levelsof-alphabetize trap)
*   Shuffle the crosswalk rows; labels must still land on the right variables.
* ============================================================================
clear
input id x1 x2 x3
1 10 20 30
end
preserve
clear
input str8 Variable str40 Label
"x3" "third measure"
"id" "identifier"
"x1" "first measure"
"x2" "second measure"
end
export excel using "`scratch'.xlsx", firstrow(variables) replace
restore
applyvarlabels using "`scratch'.xlsx"
assert "`: variable label x1'" == "first measure"
assert "`: variable label x3'" == "third measure"
assert "`: variable label id'" == "identifier"
di as res ">> TEST 2 passed (by-name match survives shuffled rows)"

* ============================================================================
* TEST 3 -- nocase: crosswalk names differ only in case
* ============================================================================
clear
input id agev incv
1 40 50000
end
preserve
clear
input str8 Variable str40 Label
"ID"   "identifier"
"AgeV" "age in years"
"INCV" "income"
end
export excel using "`scratch'.xlsx", firstrow(variables) replace
restore
* without nocase: nothing matches
applyvarlabels using "`scratch'.xlsx"
assert r(N_applied) == 0
assert r(N_nomatch) == 3
* with nocase: all three match and the do-file uses the REAL variable spelling
applyvarlabels using "`scratch'.xlsx", nocase
assert r(N_applied) == 3
assert "`: variable label agev'" == "age in years"
assert "`: variable label incv'" == "income"
di as res ">> TEST 3 passed (nocase matches across case, real spelling used)"

* ============================================================================
* TEST 4 -- CSV crosswalk (importer chosen from the extension)
* ============================================================================
clear
input id a b
1 2 3
end
preserve
clear
input str8 Variable str40 Label
"a" "alpha"
"b" "beta"
end
export delimited using "`scratch'.csv", replace
restore
applyvarlabels using "`scratch'.csv"
assert "`: variable label a'" == "alpha"
assert "`: variable label b'" == "beta"
assert r(N_applied) == 2
di as res ">> TEST 4 passed (CSV crosswalk)"

* ============================================================================
* TEST 5 -- norun writes the do-file but applies nothing
* ============================================================================
clear
input id q1
1 5
end
preserve
clear
input str8 Variable str40 Label
"q1" "question one"
end
export excel using "`scratch'.xlsx", firstrow(variables) replace
restore
applyvarlabels using "`scratch'.xlsx", norun dofile("`scratch'_relabel.do") replace
assert "`: variable label q1'" == ""             // NOT applied (input-created var, no label)
capture confirm file "`scratch'_relabel.do"
assert _rc == 0                                    // do-file exists
* running it by hand now applies the label
do "`scratch'_relabel.do"
assert "`: variable label q1'" == "question one"
di as res ">> TEST 5 passed (norun defers application to the kept do-file)"

* ============================================================================
* TEST 6 -- duplicate crosswalk rows: last label wins, dup is reported
* ============================================================================
clear
input id z
1 9
end
preserve
clear
input str8 Variable str40 Label
"z" "first label"
"z" "second label"
end
export excel using "`scratch'.xlsx", firstrow(variables) replace
restore
applyvarlabels using "`scratch'.xlsx"
assert "`: variable label z'" == "second label"
assert "`r(dups)'" == "z"
di as res ">> TEST 6 passed (duplicate rows: last wins, flagged)"

* ============================================================================
* TEST 7 -- a label longer than 80 characters draws the truncation caution
* ============================================================================
clear
input id long1
1 1
end
preserve
clear
input str8 Variable str120 Label
"long1" "This label is deliberately far longer than the eighty character maximum that Stata allows for a variable label"
end
export excel using "`scratch'.xlsx", firstrow(variables) replace
restore
applyvarlabels using "`scratch'.xlsx"
assert r(N_long) == 1
assert strlen("`: variable label long1'") == 80    // Stata truncated it
di as res ">> TEST 7 passed (over-length label counted and truncated)"

* ============================================================================
* TEST 8 -- error handling: missing file, and missing columns
* ============================================================================
clear
input id v
1 1
end
capture applyvarlabels using "`scratch'_does_not_exist.xlsx"
assert _rc == 601
* a crosswalk whose columns are not named Variable/Label
preserve
clear
input str8 name str40 text
"v" "value"
end
export excel using "`scratch'.xlsx", firstrow(variables) replace
restore
capture applyvarlabels using "`scratch'.xlsx"
assert _rc == 111
* ...but variable()/label() point it at the right columns
applyvarlabels using "`scratch'.xlsx", variable(name) label(text)
assert "`: variable label v'" == "value"
di as res ">> TEST 8 passed (missing file and mis-named columns handled)"

* ============================================================================
* TEST 9 -- the data in memory are not reordered or otherwise disturbed
* ============================================================================
clear
input id b a
3 2 1
1 5 4
end
gen byte _order = _n
preserve
clear
input str8 Variable str40 Label
"a" "aaa"
"b" "bbb"
end
export excel using "`scratch'.xlsx", firstrow(variables) replace
restore
* variable order before: id b a _order ; row order intact
applyvarlabels using "`scratch'.xlsx"
quietly ds
assert "`r(varlist)'" == "id b a _order"           // columns unmoved
assert id[1] == 3 & id[2] == 1                      // rows unmoved
di as res ">> TEST 9 passed (data left untouched but for the labels)"

* ============================================================================
* TEST 10 -- a label containing a straight double-quote (which a Stata label
*   cannot hold) is normalized to curly quotes, applied, and reported
* ============================================================================
clear
input id q
1 1
end
preserve
clear
set obs 1
gen str8  Variable = "q"
gen str60 Label = `"They said "yes" to the 35" item"'
export excel using "`scratch'.xlsx", firstrow(variables) replace
restore
applyvarlabels using "`scratch'.xlsx"
* the label was applied (not skipped, not an error)...
assert "`: variable label q'" != ""
* ...and holds no straight double-quote character...
assert strpos(`"`: variable label q'"', char(34)) == 0
* ...and the variable is reported as normalized:
assert "`r(normalized)'" == "q"
assert r(N_normalized) == 1
* the non-quote text survived intact:
assert strpos(`"`: variable label q'"', "They said ") == 1
assert strpos(`"`: variable label q'"', " to the ") > 0
di as res ">> TEST 10 passed (straight quotes normalized, applied, reported)"

* ============================================================================
* TEST 11 -- an empty label cell is skipped and reported in r(blanks)
* ============================================================================
clear
input id keep1 skip1
1 1 2
end
preserve
clear
input str8 Variable str40 Label
"keep1" "kept label"
"skip1" ""
end
export excel using "`scratch'.xlsx", firstrow(variables) replace
restore
applyvarlabels using "`scratch'.xlsx"
assert "`: variable label keep1'" == "kept label"
assert "`: variable label skip1'" == ""      // untouched (input-created, no label)
assert "`r(blanks)'" == "skip1"
di as res ">> TEST 11 passed (empty label cell skipped and reported)"

* ============================================================================
* TEST 12 -- smcl() names the inventory file; r(smcl) points to it; a second
*   call without replace ERRORS rather than silently redirecting
* ============================================================================
clear
input id m1
1 1
end
preserve
clear
input str8 Variable str40 Label
"m1" "measure one"
end
export excel using "`scratch'.xlsx", firstrow(variables) replace
restore
applyvarlabels using "`scratch'.xlsx", smcl("`scratch'_inv.smcl") replace
assert "`: variable label m1'" == "measure one"
capture confirm file "`scratch'_inv.smcl"
assert _rc == 0
assert "`r(smcl)'" == "`scratch'_inv.smcl"
capture applyvarlabels using "`scratch'.xlsx", smcl("`scratch'_inv.smcl")
assert _rc == 602
di as res ">> TEST 12 passed (smcl() honored, r(smcl) set, no-replace errors)"

* ============================================================================
* TEST 13 -- a tab-delimited (.tsv) crosswalk
* ============================================================================
clear
input id t1 t2
1 1 2
end
preserve
clear
input str8 Variable str40 Label
"t1" "tab one"
"t2" "tab two"
end
export delimited using "`scratch'.tsv", delimiter(tab) replace
restore
applyvarlabels using "`scratch'.tsv"
assert "`: variable label t1'" == "tab one"
assert "`: variable label t2'" == "tab two"
assert r(N_applied) == 2
di as res ">> TEST 13 passed (.tsv crosswalk)"

* ============================================================================
* TEST 14 -- labels with $name and a backtick survive being written to and
*   run from the relabel do-file (macro-expansion escaping)
* ============================================================================
clear
input id d1 d2
1 1 2
end
preserve
clear
set obs 2
gen str12 Variable = cond(_n==1, "d1", "d2")
gen str40 Label = ""
replace Label = "Net worth in " + char(36) + "wealth" in 1
replace Label = "code " + char(96) + "size" + char(39) + " ref" in 2
export excel using "`scratch'.xlsx", firstrow(variables) replace
restore
global wealth "CORRUPT"          // would replace an unescaped $wealth
applyvarlabels using "`scratch'.xlsx"
macro drop wealth
* $name label kept its literal dollar sign, not the global's value:
local d1lab : variable label d1
assert `"`macval(d1lab)'"' == "Net worth in \$wealth"
* backtick label kept its backtick (no local expansion to empty):
local d2lab : variable label d2
assert strpos(`"`macval(d2lab)'"', char(96)) > 0
assert strpos(`"`macval(d2lab)'"', "code ") == 1
assert strpos(`"`macval(d2lab)'"', " ref") > 0
di as res ">> TEST 14 passed (dollar-sign and backtick labels survive the do-file)"

di as res _n "============================================================"
di as res "ALL TESTS PASSED"
di as res "============================================================"
