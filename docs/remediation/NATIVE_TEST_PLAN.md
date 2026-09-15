# Native acceptance test plan

The remediation contract has 76 required requirements. Identifiers marked planned are reserved test or observation names; they have no passing evidence yet. Existing integration tests are compiled but intentionally excluded from the P00 baseline run because the production writer terminates on its invalid flags.

| Requirement | Contract | Test or observation identifier | Registration |
|---|---|---|---|
| G01-T01 | Debug build and test | `G01ContractTests/testDebugBuildAndTest` | planned |
| G01-T02 | Release build and test | `G01ContractTests/testReleaseBuildAndTest` | planned |
| G01-T03 | Test discovery and nonzero assertions | `G01ContractTests/testTestDiscoveryAndNonzeroAssertions` | planned |
| G01-T04 | Separate ASan/TSan and analyzer | `G01ContractTests/testSeparateAsanTsanAndAnalyzer` | planned |
| G01-T05 | Existing fixture validators | `G01ContractTests/testExistingFixtureValidators` | planned |
| G02-T01 | LF CSV to Markdown through manager | `ConversionPipelineIntegrationTests/testRealManagerPublishesMarkdown` | registered, not run in baseline |
| G02-T02 | CSV to JSON through manager | `ConversionPipelineIntegrationTests/testRealManagerPublishesParseableJSON` | registered, not run in baseline |
| G02-T03 | Existing output hash unchanged | `ConversionPipelineIntegrationTests/testExistingDestinationRemainsByteIdentical` | registered, not run in baseline |
| G02-T04 | Same source and target | `ConversionPipelineIntegrationTests/testSourceEqualsTargetDoesNotOverwriteOrReingestOutput` | registered, not run in baseline |
| G02-T05 | Concurrent exclusive publish | `G02ContractTests/testConcurrentExclusivePublish` | planned |
| G02-T06 | Symlink and dangling-link destination | `G02ContractTests/testSymlinkAndDanglingLinkDestination` | planned |
| G02-T07 | Partial write and EINTR injection | `G02ContractTests/testPartialWriteAndEintrInjection` | planned |
| G02-T08 | Cancel before/after commit | `G02ContractTests/testCancelBeforeAfterCommit` | planned |
| G02-T09 | Filesystem capability error | `G02ContractTests/testFilesystemCapabilityError` | planned |
| G02-T10 | Bounded collision retry and cleanup | `G02ContractTests/testBoundedCollisionRetryAndCleanup` | planned |
| G03-T01 | All CSV oracle cases | `G03ContractTests/testAllCsvOracleCases` | planned |
| G03-T02 | Encoding choice through UI | `G03ContractTests/testEncodingChoiceThroughUi` | planned |
| G03-T03 | Delimiter/header settings through coordinator | `G03ContractTests/testDelimiterHeaderSettingsThroughCoordinator` | planned |
| G03-T04 | Strict malformed quote diagnostics | `DelimitedParserRegressionTests/testUnterminatedQuoteIsRejected` | registered, not run in baseline |
| G03-T05 | 1000 seeded round trips | `G03ContractTests/test1000SeededRoundTrips` | planned |
| G03-T06 | Chunk sizes across CRLF, quotes and Unicode | `G03ContractTests/testChunkSizesAcrossCrlfQuotesAndUnicode` | planned |
| G04-T01 | Duplicate/blank column identity | `G04ContractTests/testDuplicateBlankColumnIdentity` | planned |
| G04-T02 | Ragged record no loss | `G04ContractTests/testRaggedRecordNoLoss` | planned |
| G04-T03 | Missing differs from empty | `G04ContractTests/testMissingDiffersFromEmpty` | planned |
| G04-T04 | Every Markdown cell recoverable | `G04ContractTests/testEveryMarkdownCellRecoverable` | planned |
| G04-T05 | Literal HTML/Markdown and fence safety | `G04ContractTests/testLiteralHtmlMarkdownAndFenceSafety` | planned |
| G04-T06 | Schema/timestamp normalization integrity | `G04ContractTests/testSchemaTimestampNormalizationIntegrity` | planned |
| G05-T01 | Files/folders/multiple/drop selection | `G05ContractTests/testFilesFoldersMultipleDropSelection` | planned |
| G05-T02 | Recursive option and nested target exclusion | `G05ContractTests/testRecursiveOptionAndNestedTargetExclusion` | planned |
| G05-T03 | RTFD package before directory skip | `G05ContractTests/testRtfdPackageBeforeDirectorySkip` | planned |
| G05-T04 | Dotfile and extensionless text | `G05ContractTests/testDotfileAndExtensionlessText` | planned |
| G05-T05 | Unknown binary and special files | `G05ContractTests/testUnknownBinaryAndSpecialFiles` | planned |
| G05-T06 | Duplicate/symlink aliases and loops | `G05ContractTests/testDuplicateSymlinkAliasesAndLoops` | planned |
| G05-T07 | Scopes and permission denial | `G05ContractTests/testScopesAndPermissionDenial` | planned |
| G05-T08 | Single-run guard and restart | `G05ContractTests/testSingleRunGuardAndRestart` | planned |
| G06-T01 | Scanned PDF | `G06ContractTests/testScannedPdf` | planned |
| G06-T02 | Mixed PDF | `G06ContractTests/testMixedPdf` | planned |
| G06-T03 | Locked PDF and partial pages | `G06ContractTests/testLockedPdfAndPartialPages` | planned |
| G06-T04 | Meaningful PDF running text | `G06ContractTests/testMeaningfulPdfRunningText` | planned |
| G06-T05 | Multipage TIFF with orientation | `G06ContractTests/testMultipageTiffWithOrientation` | planned |
| G06-T06 | No OCR text and failure | `G06ContractTests/testNoOcrTextAndFailure` | planned |
| G06-T07 | XML mixed/order/space/namespaces | `G06ContractTests/testXmlMixedOrderSpaceNamespaces` | planned |
| G06-T08 | HTML background and external-resource denial | `G06ContractTests/testHtmlBackgroundAndExternalResourceDenial` | planned |
| G06-T09 | Attributed tables/attachments and RTFD | `G06ContractTests/testAttributedTablesAttachmentsAndRtfd` | planned |
| G07-T01 | Padding amplification upper bound | `G07ContractTests/testPaddingAmplificationUpperBound` | planned |
| G07-T02 | Documented large batch memory | `G07ContractTests/testDocumentedLargeBatchMemory` | planned |
| G07-T03 | Limits at all stages | `G07ContractTests/testLimitsAtAllStages` | planned |
| G07-T04 | Cancellation latency and cleanup measured | `G07ContractTests/testCancellationLatencyAndCleanupMeasured` | planned |
| G08-T01 | XML DTD/entity restrictions | `G08ContractTests/testXmlDtdEntityRestrictions` | planned |
| G08-T02 | HTML local/network denial | `G08ContractTests/testHtmlLocalNetworkDenial` | planned |
| G08-T03 | Archive traversal and symlink | `G08ContractTests/testArchiveTraversalAndSymlink` | planned |
| G08-T04 | Archive expanded bytes and nesting | `G08ContractTests/testArchiveExpandedBytesAndNesting` | planned |
| G08-T05 | Private logging with synthetic secrets | `G08ContractTests/testPrivateLoggingWithSyntheticSecrets` | planned |
| G08-T06 | No executable content or external conversions | `G08ContractTests/testNoExecutableContentOrExternalConversions` | planned |
| G09-T01 | Actual Xcode Product Build | `G09ContractTests/testActualXcodeProductBuild` | planned |
| G09-T02 | Actual Xcode Product Test | `G09ContractTests/testActualXcodeProductTest` | planned |
| G09-T03 | Actual Xcode Product Run | `G09ContractTests/testActualXcodeProductRun` | planned |
| G09-T04 | Native picker and options | `G09ContractTests/testNativePickerAndOptions` | planned |
| G09-T05 | Release sandbox effective entitlements | `G09ContractTests/testReleaseSandboxEffectiveEntitlements` | planned |
| G09-T06 | Cancel/restart and responsive UI | `G09ContractTests/testCancelRestartAndResponsiveUi` | planned |
| G10-T01 | Valid XLSX semantic data both outputs | `G10ContractTests/testValidXlsxSemanticDataBothOutputs` | planned |
| G10-T02 | Valid XLS semantic data both outputs | `G10ContractTests/testValidXlsSemanticDataBothOutputs` | planned |
| G10-T03 | Valid ODS semantic data both outputs | `G10ContractTests/testValidOdsSemanticDataBothOutputs` | planned |
| G10-T04 | ZIP collection through registry both outputs | `G10ContractTests/testZipCollectionThroughRegistryBothOutputs` | planned |
| G10-T05 | Formula/cache/precision/date/sparse semantics | `G10ContractTests/testFormulaCachePrecisionDateSparseSemantics` | planned |
| G10-T06 | Adverse encrypted/unsupported container outcomes | `G10ContractTests/testAdverseEncryptedUnsupportedContainerOutcomes` | planned |
| G11-T01 | macOS CI build/test execution | `G11ContractTests/testMacosCiBuildTestExecution` | planned |
| G11-T02 | Native artifact/test count inspection | `G11ContractTests/testNativeArtifactTestCountInspection` | planned |
| G11-T03 | Capability README migration accuracy | `G11ContractTests/testCapabilityReadmeMigrationAccuracy` | planned |
| G11-T04 | Policy workflows unchanged | `G11ContractTests/testPolicyWorkflowsUnchanged` | planned |
| G12-T01 | Behavior review | `G12ContractTests/testBehaviorReview` | planned |
| G12-T02 | Independent oracle integrity review | `G12ContractTests/testIndependentOracleIntegrityReview` | planned |
| G12-T03 | Safety and concurrency review | `G12ContractTests/testSafetyAndConcurrencyReview` | planned |
| G12-T04 | Final complete rerun | `G12ContractTests/testFinalCompleteRerun` | planned |
| G12-T05 | Source fingerprint and evidence review | `G12ContractTests/testSourceFingerprintAndEvidenceReview` | planned |
| G12-T06 | Attribution and unauthorized-change scan | `G12ContractTests/testAttributionAndUnauthorizedChangeScan` | planned |

P00 executed `BaselineWriterProbeTests/testInvalidFlagCombinationTerminatesOnlyChildProcess` in a bounded child process and the 14 `DelimitedParserRegressionTests` methods. The 9 parser failures establish F02/F06 at the native source boundary; they are expected baseline defects, not waived acceptance tests.
