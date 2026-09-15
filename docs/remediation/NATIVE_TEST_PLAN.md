# Native acceptance test plan

The remediation contract has 76 required requirements. Identifiers marked planned are reserved test or observation names; they have no passing evidence yet. Existing integration tests are compiled but intentionally excluded from the P00 baseline run because the production writer terminates on its invalid flags.

| Requirement | Contract | Test or observation identifier | Registration |
|---|---|---|---|
| G01-T01 | Debug build and test | `G01ContractTests/testDebugBuildAndTest` | planned |
| G01-T02 | Release build and test | `G01ContractTests/testReleaseBuildAndTest` | planned |
| G01-T03 | Test discovery and nonzero assertions | `G01ContractTests/testTestDiscoveryAndNonzeroAssertions` | planned |
| G01-T04 | Separate ASan/TSan and analyzer | `G01ContractTests/testSeparateAsanTsanAndAnalyzer` | planned |
| G01-T05 | Existing fixture validators | `G01ContractTests/testExistingFixtureValidators` | planned |
| G02-T01 | LF CSV to Markdown through manager | `ConversionPipelineIntegrationTests/testRealManagerPublishesMarkdown` | registered; Debug/Release P01 focused passed |
| G02-T02 | CSV to JSON through manager | `ConversionPipelineIntegrationTests/testRealManagerPublishesParseableJSON` | registered; Debug/Release P01 focused passed |
| G02-T03 | Existing output hash unchanged | `ConversionPipelineIntegrationTests/testExistingDestinationRemainsByteIdentical` | registered; Debug/Release P01 focused passed |
| G02-T04 | Same source and target | `ConversionPipelineIntegrationTests/testSourceEqualsTargetDoesNotOverwriteOrReingestOutput` | registered; Debug/Release P01 focused passed |
| G02-T05 | Concurrent exclusive publish | `OutputWriterRegressionTests/testConcurrentPublishersChooseDistinctFinalNames` | registered; Debug/Release P01 focused passed |
| G02-T06 | Symlink and dangling-link destination | `OutputWriterRegressionTests/testDanglingSymlinkDestinationIsNeverReplaced` | registered; Debug/Release P01 focused passed |
| G02-T07 | Partial write and EINTR injection | `OutputWriterRegressionTests/testInjectedShortWriteAndEINTRCompletePayload` | registered; Debug/Release P01 focused passed |
| G02-T08 | Cancel before/after commit | `OutputWriterRegressionTests/testCancellationAfterCommitPreservesPublishedArtifact` | registered; Debug/Release P01 focused passed |
| G02-T09 | Filesystem capability error | `OutputWriterRegressionTests/testUnsupportedExclusiveRenameReturnsCapabilityError` | registered; Debug/Release P01 focused passed |
| G02-T10 | Bounded collision retry and cleanup | `OutputWriterRegressionTests/testCollisionLimitDoesNotRemoveCompetingDestination` | registered; Debug/Release P01 focused passed |
| G03-T01 | All CSV oracle cases | `DelimitedCorpusTests/testAllIndependentByteCases` | registered; full Debug/Release passed |
| G03-T02 | Encoding choice through UI | `ConversionViewModelOptionsTests/testVisibleInterpretationChoicesReachProductionManagerAndOutput` | registered; ViewModel path passed; actual picker IDE check pending |
| G03-T03 | Delimiter/header settings through coordinator | `DelimitedCorpusTests/testExplicitEncodingHeaderAndDelimiterReachRealManager` | registered; full Debug/Release passed |
| G03-T04 | Strict malformed quote diagnostics | `DelimitedParserRegressionTests/testUnterminatedQuoteIsRejected` | registered; full Debug/Release passed |
| G03-T05 | 1000 seeded round trips | `DelimitedCorpusTests/testOneThousandSeededRoundTripsAcrossChunkSizes` | registered; full Debug/Release passed |
| G03-T06 | Chunk sizes across CRLF, quotes and Unicode | `DelimitedCorpusTests/testByteReadBoundariesAcrossBOMUnicodeCRLFAndQuotes` | registered; full Debug/Release passed |
| G04-T01 | Duplicate/blank column identity | `CanonicalTableTests/testDuplicateBlankAndExtraColumnsStayDistinct` | registered; P03 Debug passed |
| G04-T02 | Ragged record no loss | `CanonicalTableTests/testDuplicateBlankAndExtraColumnsStayDistinct` | registered; P03 Debug passed |
| G04-T03 | Missing differs from empty | `CanonicalTableTests/testMissingAndExplicitEmptyAreDifferent` | registered; P03 Debug passed |
| G04-T04 | Every Markdown cell recoverable | `CanonicalTableTests/testIndependentCorpusAgreesAcrossCanonicalJSONAndMarkdown` | registered; full positive corpus comparison pending rerun |
| G04-T05 | Literal HTML/Markdown and fence safety | `CanonicalTableTests/testFenceExceedsSourceRunAndPreservesLiteralMarkup` | registered; pending native rerun |
| G04-T06 | Schema/timestamp normalization integrity | `scripts/validate_fixtures.sh` and `CanonicalTableTests/testDuplicateBlankAndExtraColumnsStayDistinct` | registered; 12 fixtures and schema shape passed; P08 source-bound rerun pending |
| G05-T01 | Files/folders/multiple/drop selection | `IntakeTraversalTests/testDirectFileMultipleSelectionsAndDuplicateIdentity`, `ConversionViewModelOptionsTests/testDroppedMultipleFilesReachProductionManager` | registered; native paths passed; actual picker/drop IDE observation pending |
| G05-T02 | Recursive option and nested target exclusion | `IntakeTraversalTests/testRecursiveToggleNestedTargetAndDotfile` | registered; native passed |
| G05-T03 | RTFD package before directory skip | `IntakeTraversalTests/testPackageSymlinkAndSpecialFileDoNotDescendOrBlock` | registered; native RTFD conversion passed |
| G05-T04 | Dotfile and extensionless text | `IntakeTraversalTests/testExtensionlessStrictTextAndBinaryClassification`, `testExplicitHiddenFileIsHonoredAndRecursiveHiddenToggleControlsDiscovery` | registered; native passed |
| G05-T05 | Unknown binary and special files | `IntakeTraversalTests/testExtensionlessStrictTextAndBinaryClassification`, `testPackageSymlinkAndSpecialFileDoNotDescendOrBlock` | registered; native passed |
| G05-T06 | Duplicate/symlink aliases and loops | `IntakeTraversalTests/testAppBundleIsSkippedAndHardlinkAliasDeduplicated`, `testExplicitLinkCannotEscapeSelectedRoot` | registered; native passed |
| G05-T07 | Scopes and permission denial | `IntakeTraversalTests/testUnreadableSourceReportsFailureWithoutPublishing` | registered; denial passed; successful sandbox scope balance IDE observation pending |
| G05-T08 | Single-run guard and restart | `IntakeTraversalTests/testServiceRejectsConcurrentStartAndAllowsSecondRun`, `testCancellationPreservesCommittedFirstOutputAndStopsNewWork` | registered; native passed; responsive IDE observation pending |
| G06-T01 | Scanned PDF | `PDFExtractionTests/testProductionVisionReadsRasterOnlyPDF` | registered; P05 Debug/Release passed |
| G06-T02 | Mixed PDF | `PDFExtractionTests/testNativeAndOCRPagesKeepIdentityWithoutDuplicatingNativeText` | registered; P05 Debug/Release passed |
| G06-T03 | Locked PDF and partial pages | `PDFExtractionTests/testLockedPDFRequiresPasswordAndPublishesNoNormalArtifact`, `testNoTextAndOCRFailureAreDistinctOutcomes` | registered; P05 Debug/Release passed |
| G06-T04 | Meaningful PDF running text | `PDFExtractionTests/testRepeatedMeaningfulNativeTextIsNotStripped` | registered; P05 Debug/Release passed |
| G06-T05 | Multipage TIFF with orientation | `ImagePageTests/testMultipageTIFFKeepsBothFramesAndOrientation` | registered; P05 Debug/Release passed |
| G06-T06 | No OCR text and failure | `ImagePageTests/testEmptyOCRAndFrameLimitAreExplicit`, `PDFExtractionTests/testNoTextAndOCRFailureAreDistinctOutcomes` | registered; P05 Debug/Release passed |
| G06-T07 | XML mixed/order/space/namespaces | `OrderedXMLTests/testMixedTextChildTextOrder`, `testNamespaceIdentityAndCDATAStaySeparateFromChildOrder`, `testXMLSpacePreservesBeforeAndAfterWhitespace` | registered; P05 Debug/Release passed |
| G06-T08 | HTML background and external-resource denial | `HTMLAndAttributedTests/testSafeHTMLExtractsOnBackgroundTaskAndTableIsPartial`, `testResourceBearingHTMLIsDeniedWithoutNetworkRequest` | registered; unsandboxed local TCP request count zero; signed IDE denial observed; P05 Debug/Release/IDE passed |
| G06-T09 | Attributed tables/attachments and RTFD | `HTMLAndAttributedTests/testRTFAttachmentAndTableWarningsArePartial`, `testRealRTFAndContainerDocumentsReportTheirLimits`; `IntakeTraversalTests/testPackageSymlinkAndSpecialFileDoNotDescendOrBlock` | registered; P05 Debug/Release passed |
| G07-T01 | Padding amplification upper bound | `CanonicalTableTests/testPaddingCorpusPreservesAllRecordsUnderOneMegabyte` | registered; P03 Debug passed |
| G07-T02 | Documented large batch memory | `G07ContractTests/testDocumentedLargeBatchMemory` | planned |
| G07-T03 | Limits at all stages | `G07ContractTests/testLimitsAtAllStages` | planned |
| G07-T04 | Cancellation latency and cleanup measured | `G07ContractTests/testCancellationLatencyAndCleanupMeasured` | planned |
| G08-T01 | XML DTD/entity restrictions | `OrderedXMLTests/testMalformedAndDTDInputsFailWithoutNormalOutput` | registered; UTF-8 and UTF-16 DTD denial passed; adverse entity matrix remains P06 |
| G08-T02 | HTML local/network denial | `HTMLAndAttributedTests/testResourceBearingHTMLIsDeniedWithoutNetworkRequest` | registered; independent unsandboxed TCP request count zero and signed IDE preflight denial passed; local-file matrix remains P06 |
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
