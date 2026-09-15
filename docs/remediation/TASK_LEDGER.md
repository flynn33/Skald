# Remediation task ledger

Package baseline/current commit: `f9592b41f4106f354d9b7e36e7bd1b7a9b2d2277` (matched by package `check_baseline.py`).
Native baseline tested-source fingerprint: `5b7e5917ea2cc75f958b55d299e537f675e5706b9945be6b2cbecaa46ca4ef6d` (captured after the 15-test run and before the documentation edits; production source was unchanged).
Working branch and pre-existing changes: `main`, clean after clone from `https://github.com/flynn33/Skald.git`; no pre-existing local files.
Toolchain: macOS 26.6.2 arm64, Xcode 26.6 (17F113), Swift 6.3.3 in Swift 5 language mode, macOS SDK 26.5, deployment target 26.2. Four code-signing identities were listed. A signed Debug build after P01 showed Apple Development identity, app sandbox, and user-selected-file read/write entitlement; signed IDE interaction and Release entitlements remain for P08.
Repository version at baseline: `1.0.0`, Xcode build `1`; no phase P00 version change.
Available guidance invoked: Build macOS Apps `build-run-debug` skill for Xcode project discovery and native build. The remediation package was validated with `validate_bundle.py --root ... --require-manifest`. Xcode command-line build and baseline native tests ran. IDE Build/Test/Run, review, and release checks remain pending.

| Phase | Status | Evidence | Findings remaining | Next action |
|---|---|---|---|---|
| P00 | foundation established | `Skald-P00-baseline.xcresult`, summary SHA-256 below; shared scheme and native test target discovered; Debug build-for-testing passed; 15 baseline tests ran, 6 passed, 9 failed | F10 full coverage remains incomplete; original user crash trace unavailable | Continue the native harness through remaining phases |
| P01 | focused repair verified | 17/17 Debug and 17/17 Release native writer/manager tests passed, no skips; existing fixture and planner validators passed; signed Debug build entitlements inspected; hashes below | G02 signed IDE exercise/full final rerun remain pending | Repair parser/interpretation in P02 |
| P02 | not_run | | F02/F03/F04/F06 | Repair byte decoding and parser |
| P03 | not_run | | F05/F09 | Canonical tables |
| P04 | not_run | | F07 | Broaden intake |
| P05 | not_run | | F08/F11 | Complete extraction |
| P06 | not_run | | F09 and safety limits | Bound resource use |
| P07 | not_run | | F12 | Native format expansion |
| P08 | not_run | | G01–G12 | Full gates and independent review |

P00 baseline result: the child-process invalid writer flags probe passed; nine parser tests failed on CRLF collapse, whitespace/empty-record loss, and malformed quote acceptance. `Skald-P00-baseline-summary.json` SHA-256: `d7f72745476dd81520183456a6965066498f60de576ac40a5941c3f5d1c4df53`. The exact installed-app crash remains unconfirmed without its crash trace/binary revision. Parser and integration tests are not yet a repaired-product pass.

P01 focused tested-source fingerprint before documentation edits: `1adae263e22b3acbafa50d41ad67deab2778fa7488bd33aee96728303eb74bed`. The Debug summary `Skald-P01-debug-summary.json` has SHA-256 `9d6ec0282cd956395207f0199fd043a5da1cca72b9367f1fc46505b48b65903c`; the Release summary `Skald-P01-release-summary.json` has SHA-256 `7873d59e1cfbbbed2df8afd3772f0163131d42dfb56aee706699af7021b1760d`. The signed Debug app showed `com.apple.security.app-sandbox=true` and `com.apple.security.files.user-selected.read-write=true`. The tests used `CODE_SIGNING_ALLOWED=NO`; signed-app manual behavior remains unverified. A Release testability project setting was repaired after the first Release test compile failed; the same 17 focused tests then passed on the final implementation.
