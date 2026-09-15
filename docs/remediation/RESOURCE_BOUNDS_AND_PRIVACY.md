# Resource bounds and privacy

P06 introduces one validated `ResourceLimits` configuration at the production manager. Every value must be positive. An exceeded limit is a failed file or run with a stable code; no converter marks a known oversized file as unsupported or silently truncates it. Limits can be reduced in native tests without changing the shipped defaults. P07 enforces archive, XML-part, and workbook ceilings through the named-format readers.

| Resource | Default production ceiling |
|---|---:|
| Plain/source/INI input | 16 MiB per file |
| JSON/plist/XML input | 16 MiB per file |
| HTML input | 8 MiB per file |
| CSV/TSV input | 64 MiB per file |
| PDF/attributed package input | 64 MiB per file |
| Image source input | 64 MiB per file |
| CSV/TSV records, columns, cells, field scalars | 100,000; 1,024; 250,000; 1,000,000 |
| Structured nesting and value nodes | 64 levels; 100,000 nodes |
| Source image pixels and OCR thumbnail | 40 million per frame; 2,048 pixel edge |
| Source worklist, batch input bytes, output bytes | 10,000 items; 512 MiB; 128 MiB per file |
| Archive entries, expanded bytes, nesting | 1,000; 256 MiB; depth 2 |
| XLSX/XLS/ODS sheets, rows, columns, populated cells | 128; 100,000; 1,024; 250,000 |

Readers check file size before allocating and read in 64 KiB cancellable chunks. RTFD packages are walked before `NSAttributedString` import, rejecting links and packages beyond the byte/member ceilings. PDFKit and ImageIO open the URL only after byte preflight; OCR/page/frame/pixel limits remain in their converters. CSV/TSV decoding now validates bytes in the bounded `Data` buffer without constructing a second full-size byte array and payload copy. The parser limits records, columns, total cells, and field scalars while consuming text. JSON syntax nesting is preflighted outside strings before `JSONSerialization`; JSON/plist normalization checks depth, node count, and cancellation at each node. XML and HTML keep their P05 structural/resource restrictions. The manager caps the source snapshot, cumulative file bytes, and rendered output before publication. OutputWriter's temporary files are removed on failed/cancelled publication.

Typed `InputDiagnostic` includes a stable code, stage, optional file/page/record, safe visible summary, and an underlying error retained in memory for troubleshooting. CSV/TSV retains its typed offset and field diagnostics. Unexpected framework errors show a generic visible failure instead of echoing file contents or private paths. Native `Logger` records stage/code without interpolating source paths, document values, `.env` contents, external resource URLs, or passwords. A signed P08 Release run exposed only `File failed at convert with conversionFailure` for an externally linked HTML fixture in the default macOS log; Xcode's privileged Debug console had exposed path interpolations before this repair. Untrusted document text is data: no converter invokes a shell or external application, HTML rejects tags/attributes with resource access, and Markdown renders regular source text with markup escaped. Verbatim source code uses a fence longer than source backtick runs. P07 ZIP/workbook safety and provenance are described in [NAMED_FORMAT_READERS.md](NAMED_FORMAT_READERS.md).

The final native P06 Debug run processed the 2,000-record padding corpus into **131,139 Markdown bytes in 0.030 seconds** and a 100-file JSON batch in **0.041 seconds** on macOS 26.6.2/Xcode 26.6 arm64. `getrusage(RUSAGE_SELF)` reported **233,684,992 bytes peak resident memory** for the entire native test host, including Xcode test startup and prior test allocations; this is an observed process high-water mark, not per-conversion memory. The corpus remained below the 1 MiB output gate with every record present. A 100-file batch reported bounded progress and exactly 100 completed artifacts. Limits, malformed causes, inert markup, and cancelled reads have native boundary tests. These measurements describe this toolchain and fixture, not every maximum-size input.
