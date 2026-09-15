# Publication decision

Decision: replace the invalid `.atomic` plus `.withoutOverwriting` production write with a same-directory temporary file and Darwin exclusive rename. `OutputFilePlanning` remains an advisory naming service; the writer owns the final no-replacement guarantee and bounded collision retry.

Before: `ConversionManager` could terminate while trying to write and fixture-only validation did not exercise its writer. After: manager integration tests publish Markdown/JSON and preserve source/existing targets under occupied names and races. A volume without exclusive rename support now returns a controlled capability error rather than falling back to replacement. There is no output JSON schema change and the repository application version remains 1.0.0 during this unreleased remediation.

Consumers should treat an `exclusiveRenameUnsupported`/collision-limit failure as an input that did not publish a final artifact. A successfully published output may receive a qualified filename when another writer wins the preferred name. This changes failure/collision behavior, not the document content schema.
