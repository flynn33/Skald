# Publication decision

Decision: replace the invalid `.atomic` plus `.withoutOverwriting` production write with a same-directory temporary file and Darwin exclusive rename. `OutputFilePlanning` remains an advisory naming service; the writer owns the final no-replacement guarantee and bounded collision retry.

Before: `ConversionManager` could terminate while trying to write and fixture-only validation did not exercise its writer. After: manager integration tests publish Markdown/JSON and preserve source/existing targets under occupied names and races. A volume without exclusive rename support now returns a controlled capability error rather than falling back to replacement. There is no output JSON schema change and the repository application version remains 1.0.0 during this unreleased remediation.

Consumers should treat an `exclusiveRenameUnsupported`/collision-limit failure as an input that did not publish a final artifact. A successfully published output may receive a qualified filename when another writer wins the preferred name. This changes failure/collision behavior, not the document content schema.

## Delimited schema and default interpretation

Decision: CSV/TSV output schema advances from `1.1` to `1.2` to add `source.importSettings` with the applied encoding, encoding provenance, delimiter, header mode/confirmation, and diagnostic codes. Non-delimited output remains `1.1`. Automatic header mode now retains the first syntactic record; confirmed header-present is an explicit choice.

Before example: `name,code\nAva,00123\n` could be projected with `name,code` silently consumed as labels. After in automatic mode, the table records are `["name","code"]` and `["Ava","00123"]` with `headerUnconfirmed`; in header-present mode, the data record remains `["Ava","00123"]` and the original labels remain separately available. Existing headered fixture values were independently checked unchanged when the validator explicitly selected header-present. Consumers of default automatic output should account for that retained first record; schema-aware consumers should accept CSV/TSV `1.2` and the additive settings object. P03 may need a separate major CSV schema migration for canonical column identity.
