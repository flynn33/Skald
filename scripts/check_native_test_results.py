#!/usr/bin/env python3
"""Reject empty, skipped, or disconnected native Skald test runs."""

import argparse
import json
import subprocess
from pathlib import Path


REQUIRED = {
    "ConversionPipelineIntegrationTests/testBothModePublishesMarkdownAndJSONInOneRun()",
    "ConversionPipelineIntegrationTests/testBundledBothModePublishesOriginalMarkdownAndJSONTogether()",
    "ConversionViewModelOptionsTests/testBothAndBundleOptionsReachProductionManager()",
    "OutputBundleWriterTests/testConcurrentPublishersChooseDistinctCompleteBundles()",
    "OutputBundleWriterTests/testChangedTargetDirectoryIsRejectedAndStagingIsRemoved()",
    "CanonicalTableTests/testIndependentCorpusAgreesAcrossCanonicalJSONAndMarkdown()",
    "DelimitedCorpusTests/testAllIndependentByteCases()",
    "OutputWriterRegressionTests/testConcurrentPublishersChooseDistinctFinalNames()",
    "PDFExtractionTests/testProductionVisionReadsRasterOnlyPDF()",
    "ImagePageTests/testMultipageTIFFKeepsBothFramesAndOrientation()",
    "OrderedXMLTests/testMixedTextChildTextOrder()",
    "HTMLAndAttributedTests/testResourceBearingHTMLIsDeniedWithoutNetworkRequest()",
    "ResourceBoundsTests/test2000RecordCorpusThroughputAndPeakRSS()",
    "WorkbookFormatTests/testXLSXPreservesOrderSparseTypesFormulaCacheDateAndMerge()",
    "WorkbookFormatTests/testBIFF8XLSReadsCompoundWorkbookCellsFormulaCacheAndMerge()",
    "WorkbookFormatTests/testODSPreservesRepeatedSparseCellsPrecisionFormulaDateAndMerge()",
    "ZipContainerTests/testWorkbookMembersUseNamedFormatReadersInsideCollection()",
}


def result(bundle: Path, kind: str) -> dict:
    data = subprocess.check_output([
        "xcrun", "xcresulttool", "get", "test-results", kind,
        "--path", str(bundle), "--format", "json",
    ])
    return json.loads(data)


def cases(node: dict):
    if node.get("nodeType") == "Test Case":
        yield node
    for child in node.get("children", []):
        yield from cases(child)


def check(bundle: Path, minimum: int, output: Path) -> None:
    summary = result(bundle, "summary")
    tree = result(bundle, "tests")
    found = list(case for node in tree["testNodes"] for case in cases(node))
    identifiers = {case["nodeIdentifier"] for case in found}
    bad = [case["nodeIdentifier"] for case in found if case.get("result") != "Passed"]
    count = summary["totalTestCount"]
    assert summary["result"] == "Passed", summary["result"]
    assert count >= minimum, f"Only {count} tests; required minimum is {minimum}."
    assert count == len(found) == summary["passedTests"], "Test count or case status disagrees."
    assert summary["failedTests"] == summary["skippedTests"] == 0, "Failed or skipped tests."
    assert not bad, f"Non-passing cases: {bad}"
    assert REQUIRED <= identifiers, f"Required test identifiers absent: {sorted(REQUIRED - identifiers)}"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({
        "result": "Passed", "count": count, "passed": summary["passedTests"],
        "failed": 0, "skipped": 0, "requiredIdentifiers": sorted(REQUIRED),
        "observedIdentifiers": sorted(identifiers),
    }, indent=2, sort_keys=True) + "\n")
    print(f"Verified {count} passing native cases with {len(REQUIRED)} required identifiers.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--minimum-tests", type=int, default=118)
    args = parser.parse_args()
    check(args.bundle, args.minimum_tests, args.output)


if __name__ == "__main__":
    main()
