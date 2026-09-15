# Native acceptance test plan

The remediation contract has 76 required requirements. P00 reserved gate-observation names before native qualification. P08 replaces those placeholders with real Xcode, sanitizer, validator, CI, review, and signed-app observations; the external gate evidence binds each requirement to a file hash. Existing integration tests were intentionally excluded from the P00 baseline run because the production writer terminated on its invalid flags.

| Requirement | Contract | Test or observation identifier | Registration |
|---|---|---|---|
| G01-T01 | Debug build and test | `P08/Debug-build`, `P08/Debug-test` | signed build and 107/107 native tests passed |
| G01-T02 | Release build and test | `P08/Release-build`, `P08/Release-test` | signed build and 107/107 native tests passed |
| G01-T03 | Test discovery and nonzero assertions | `scripts/check_native_test_results.py`, `P08/IDE-Product-Test` | 107 registered cases, zero failures or skips |
| G01-T04 | Separate ASan/TSan and analyzer | `P08/ASan`, `P08/TSan`, `P08/analyze` | separate 107/107 sanitizer runs and analyzer passed |
| G01-T05 | Existing fixture validators | `P08/validate_fixtures`, `P08/validate_pdf_fixture`, `P08/validate_output_file_planner` | all three passed |
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
| G03-T02 | Encoding choice through UI | `ConversionViewModelOptionsTests/testVisibleInterpretationChoicesReachProductionManagerAndOutput` | registered; ViewModel path passed; signed IDE Windows-1252 picker and output inspected |
| G03-T03 | Delimiter/header settings through coordinator | `DelimitedCorpusTests/testExplicitEncodingHeaderAndDelimiterReachRealManager` | registered; full Debug/Release passed |
| G03-T04 | Strict malformed quote diagnostics | `DelimitedParserRegressionTests/testUnterminatedQuoteIsRejected` | registered; full Debug/Release passed |
| G03-T05 | 1000 seeded round trips | `DelimitedCorpusTests/testOneThousandSeededRoundTripsAcrossChunkSizes` | registered; full Debug/Release passed |
| G03-T06 | Chunk sizes across CRLF, quotes and Unicode | `DelimitedCorpusTests/testByteReadBoundariesAcrossBOMUnicodeCRLFAndQuotes` | registered; full Debug/Release passed |
| G04-T01 | Duplicate/blank column identity | `CanonicalTableTests/testDuplicateBlankAndExtraColumnsStayDistinct` | registered; P03 Debug passed |
| G04-T02 | Ragged record no loss | `CanonicalTableTests/testDuplicateBlankAndExtraColumnsStayDistinct` | registered; P03 Debug passed |
| G04-T03 | Missing differs from empty | `CanonicalTableTests/testMissingAndExplicitEmptyAreDifferent` | registered; P03 Debug passed |
| G04-T04 | Every Markdown cell recoverable | `CanonicalTableTests/testIndependentCorpusAgreesAcrossCanonicalJSONAndMarkdown` | registered; full Debug/Release/IDE positive corpus passed |
| G04-T05 | Literal HTML/Markdown and fence safety | `CanonicalTableTests/testFenceExceedsSourceRunAndPreservesLiteralMarkup` | registered; full Debug/Release/IDE native rerun passed |
| G04-T06 | Schema/timestamp normalization integrity | `scripts/validate_fixtures.sh` and `CanonicalTableTests/testDuplicateBlankAndExtraColumnsStayDistinct` | registered; 12 fixtures and schema shape passed; P08 source-bound validators and suites passed |
| G05-T01 | Files/folders/multiple/drop selection | `IntakeTraversalTests/testDirectFileMultipleSelectionsAndDuplicateIdentity`, `ConversionViewModelOptionsTests/testDroppedMultipleFilesReachProductionManager`, `FinderDropTests/testFinderDropSelectsTwoFiles` | native paths passed; picker converted two files; Xcode Finder drop reported `2 selected` |
| G05-T02 | Recursive option and nested target exclusion | `IntakeTraversalTests/testRecursiveToggleNestedTargetAndDotfile` | registered; native passed |
| G05-T03 | RTFD package before directory skip | `IntakeTraversalTests/testPackageSymlinkAndSpecialFileDoNotDescendOrBlock` | registered; native RTFD conversion passed |
| G05-T04 | Dotfile and extensionless text | `IntakeTraversalTests/testExtensionlessStrictTextAndBinaryClassification`, `testExplicitHiddenFileIsHonoredAndRecursiveHiddenToggleControlsDiscovery` | registered; native passed |
| G05-T05 | Unknown binary and special files | `IntakeTraversalTests/testExtensionlessStrictTextAndBinaryClassification`, `testPackageSymlinkAndSpecialFileDoNotDescendOrBlock` | registered; native passed |
| G05-T06 | Duplicate/symlink aliases and loops | `IntakeTraversalTests/testAppBundleIsSkippedAndHardlinkAliasDeduplicated`, `testExplicitLinkCannotEscapeSelectedRoot` | registered; native passed |
| G05-T07 | Scopes and permission denial | `IntakeTraversalTests/testUnreadableSourceReportsFailureWithoutPublishing` | registered; denial passed; signed picker access observed; start/stop balance reviewed in manager source |
| G05-T08 | Single-run guard and restart | `IntakeTraversalTests/testServiceRejectsConcurrentStartAndAllowsSecondRun`, `testCancellationPreservesCommittedFirstOutputAndStopsNewWork` | registered; native passed; signed Release cancel/restart and responsive UI observed |
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
| G07-T02 | Documented large batch memory | `ResourceBoundsTests/testSustainedBatchHasBoundedProgressAndNoTemporaryArtifacts`, `test2000RecordCorpusThroughputAndPeakRSS` | registered; P06 100-file/2,000-record measurements passed; process peak includes test host |
| G07-T03 | Limits at all stages | `ResourceBoundsTests/testReaderRejectsBeforeLoadingAndExactLimitIsAccepted`, `testDelimitedRecordColumnAndFieldLimitsIdentifyBoundary`, `testJSONNodeAndDepthLimitsAreTyped`, `testBatchAndOutputLimitsFailExplicitlyWithoutArtifacts`; `WorkbookFormatTests/testNamedWorkbookExactByteCeilingAndOneByteBelow`, `ZipContainerTests/testZipExactInputByteLimitAndOneByteBelow` | registered; P06 and P07 native boundaries passed; full P08 Debug/Release/IDE rerun passed |
| G07-T04 | Cancellation latency and cleanup measured | `ResourceBoundsTests/testReadCancellationStopsBeforeFullFileLoad`, `IntakeTraversalTests/testCancellationPreservesCommittedFirstOutputAndStopsNewWork`, `OutputWriterRegressionTests/testCancellationAfterCommitPreservesPublishedArtifact` | registered; native pass; signed Release stopped before all 6,000 inputs, restarted immediately, and cleaned owned temporaries |
| G08-T01 | XML DTD/entity restrictions | `OrderedXMLTests/testMalformedAndDTDInputsFailWithoutNormalOutput` | registered; UTF-8 and UTF-16 DTD denial passed; DTD and external-entity denial reviewed; no normal output |
| G08-T02 | HTML local/network denial | `HTMLAndAttributedTests/testResourceBearingHTMLIsDeniedWithoutNetworkRequest`, `ResourceBoundsTests/testResourceBearingHTMLAndMarkdownMarkupRemainInert` | registered; independent unsandboxed TCP request count zero, signed IDE preflight denial, and local-file denial passed |
| G08-T03 | Archive traversal and symlink | `ZipContainerTests/testUnsafeAndUnsupportedVariantsFailBeforePublication` | P07 traversal, absolute/reserved/colliding paths, links, and local-header mismatch passed |
| G08-T04 | Archive expanded bytes and nesting | `ZipContainerTests/testEntryExpansionAndDepthLimits`, `testZipExactInputByteLimitAndOneByteBelow` | P07 expansion ratio/byte/depth boundaries passed; full P08 Debug/Release/IDE rerun passed |
| G08-T05 | Private logging with synthetic secrets | `ResourceBoundsTests/testMalformedJSONPreservesCauseWithoutEchoingContent`, `ConversionManager.logFailure` source inspection | registered; P06 synthetic visible-summary test and private-path OSLog source inspection passed; signed Debug console and default Release log inspected without paths or contents |
| G08-T06 | No executable content or external conversions | `ResourceBoundsTests/testResourceBearingHTMLAndMarkdownMarkupRemainInert`, `ZipContainerTests/testRealRegistryReportsCollectionMembersAndNestedProvenance`; production registry/source inspection | registered; P07 typed member routing and unknown-binary visibility passed; P08 source and signed-UI review passed |
| G09-T01 | Actual Xcode Product Build | `P08/IDE-Product-Build` | Xcode activity reported Build Succeeded |
| G09-T02 | Actual Xcode Product Test | `P08/IDE-Product-Test` | Xcode reported 107/107; xcresult confirmed no skips |
| G09-T03 | Actual Xcode Product Run | `P08/IDE-Product-Run` | signed workspace launched and mixed batch completed |
| G09-T04 | Native picker and options | `P08/IDE-native-picker`, `P08/IDE-CSV-options`, `FinderDropTests/testFinderDropSelectsTwoFiles` | picker and controls converted selected files; Xcode Finder-drop UI test verified `2 selected` |
| G09-T05 | Release sandbox effective entitlements | `P08/standalone-Release-entitlements` | sandbox and selected-file access verified; no network/temporary exception |
| G09-T06 | Cancel/restart and responsive UI | `P08/Release-cancel-restart` | 6,000-file batch cancelled and restarted, leaving committed files and no owned temporary files |
| G10-T01 | Valid XLSX semantic data both outputs | `WorkbookFormatTests/testXLSXPreservesOrderSparseTypesFormulaCacheDateAndMerge`, `testNamedWorkbooksRouteThroughRealManager` | P07 focused passed; full P08 Debug/Release/IDE rerun passed |
| G10-T02 | Valid XLS semantic data both outputs | `WorkbookFormatTests/testBIFF8XLSReadsCompoundWorkbookCellsFormulaCacheAndMerge`, `testNamedWorkbooksRouteThroughRealManager` | P07 real CFB/BIFF8 subset passed; full P08 Debug/Release/IDE rerun passed |
| G10-T03 | Valid ODS semantic data both outputs | `WorkbookFormatTests/testODSPreservesRepeatedSparseCellsPrecisionFormulaDateAndMerge`, `testNamedWorkbooksRouteThroughRealManager` | P07 focused passed; full P08 Debug/Release/IDE rerun passed |
| G10-T04 | ZIP collection through registry both outputs | `ZipContainerTests/testRealRegistryReportsCollectionMembersAndNestedProvenance`, `testWorkbookMembersUseNamedFormatReadersInsideCollection` | P07 focused passed; full P08 Debug/Release/IDE rerun passed |
| G10-T05 | Formula/cache/precision/date/sparse semantics | three positive `WorkbookFormatTests` methods | P07 focused passed; BIFF8 variants bounded |
| G10-T06 | Adverse encrypted/unsupported container outcomes | `WorkbookFormatTests/testExternalEntityEncryptedAndRepeatedVariantsFailWithoutOutput`, `ZipContainerTests/testUnsafeAndUnsupportedVariantsFailBeforePublication` | P07 focused passed; full P08 Debug/Release/IDE rerun passed |
| G11-T01 | macOS CI build/test execution | `P08/hosted-native-run` | macos-26/Xcode 26.6 run and final artifact readback in external evidence |
| G11-T02 | Native artifact/test count inspection | `scripts/check_native_test_results.py`, `P08/hosted-xcresult-summary` | required identifiers and nonzero/no-skip counts inspected |
| G11-T03 | Capability README migration accuracy | `P08/README-review` | README variant limits and schema migration compared to native outcomes |
| G11-T04 | Policy workflows unchanged | `P08/workflow-diff-review` | only macOS native workflow added; unrelated policy workflows untouched |
| G12-T01 | Behavior review | `P08_REVIEW.md/Behavior and architecture` | full compiled production path traced |
| G12-T02 | Independent oracle integrity review | `P08_REVIEW.md/Data integrity` | fixture hashes and independently asserted source semantics inspected |
| G12-T03 | Safety and concurrency review | `P08_REVIEW.md/Writer, security, and concurrency` | writer, scope, logging, resources, and one-run guard inspected |
| G12-T04 | Final complete rerun | `P08/native-run`, `P08/ASan`, `P08/TSan`, `P08/IDE-Product-Test`, `P08/hosted-native-run` | full matrices and validators executed |
| G12-T05 | Source fingerprint and evidence review | `P08/source-before-after`, `P08/gate-ledger` | hashes and tested commit recorded outside checkout |
| G12-T06 | Attribution and unauthorized-change scan | `P08/attribution-scan`, `P08/git-diff-review` | added paths, text, commits, and workflow scope inspected |

P00 executed `BaselineWriterProbeTests/testInvalidFlagCombinationTerminatesOnlyChildProcess` in a bounded child process and the 14 `DelimitedParserRegressionTests` methods. The 9 parser failures establish F02/F06 at the native source boundary; they are expected baseline defects, not waived acceptance tests.
