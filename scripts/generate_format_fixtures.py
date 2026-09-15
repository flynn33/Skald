#!/usr/bin/env python3
"""Create deterministic hand-authored container fixtures for native format tests."""

from io import BytesIO
from pathlib import Path
from struct import pack, unpack_from
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile, ZipInfo


ROOT = Path(__file__).resolve().parents[1] / "SkaldTests" / "Corpus" / "formats"
ROOT.mkdir(parents=True, exist_ok=True)


def archive(entries):
    buffer = BytesIO()
    with ZipFile(buffer, "w") as output:
        for path, payload, method, mode in entries:
            info = ZipInfo(path, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = method
            info.external_attr = mode << 16
            output.writestr(info, payload)
    return buffer.getvalue()


nested = archive([("inner.txt", b"Nested archive text.\n", ZIP_STORED, 0o100644)])
collection = archive([
    ("table.csv", b"name,age\nAda,37\n", ZIP_STORED, 0o100644),
    ("records.json", b'{"source":"ZIP","count":2}', ZIP_DEFLATED, 0o100644),
    ("opaque.bin", b"\x00\x01\x02", ZIP_STORED, 0o100644),
    ("nested.zip", nested, ZIP_STORED, 0o100644),
])
(ROOT / "collection.zip").write_bytes(collection)
(ROOT / "path-traversal.zip").write_bytes(archive([
    ("../escape.txt", b"outside", ZIP_STORED, 0o100644)
]))
(ROOT / "absolute-path.zip").write_bytes(archive([
    ("/private/escape.txt", b"outside", ZIP_STORED, 0o100644)
]))
(ROOT / "symlink.zip").write_bytes(archive([
    ("link.txt", b"../../private", ZIP_STORED, 0o120777)
]))
(ROOT / "expansion-ratio.zip").write_bytes(archive([
    ("huge.txt", b"A" * (2 * 1024 * 1024), ZIP_DEFLATED, 0o100644)
]))
encrypted = bytearray(archive([("secret.txt", b"hidden", ZIP_STORED, 0o100644)]))
local = encrypted.index(b"PK\x03\x04")
central = encrypted.index(b"PK\x01\x02")
for position in (local + 6, central + 8):
    encrypted[position] |= 1
(ROOT / "encrypted-flag.zip").write_bytes(encrypted)
zip64 = bytearray(archive([("sample.txt", b"sample", ZIP_STORED, 0o100644)]))
end = zip64.index(b"PK\x05\x06")
zip64[end + 10:end + 12] = b"\xff\xff"
(ROOT / "zip64-marker.zip").write_bytes(zip64)

content_types = b'''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
</Types>'''
root_rels = b'''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rWorkbook" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>'''
workbook_xml = b'''<?xml version="1.0" encoding="UTF-8"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<workbookPr date1904="1"/><sheets><sheet name="Data" sheetId="1" r:id="rSheet1"/><sheet name="Second" sheetId="2" r:id="rSheet2"/></sheets>
</workbook>'''
workbook_rels = b'''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rSheet1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
<Relationship Id="rSheet2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
<Relationship Id="rShared" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
<Relationship Id="rStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>'''
shared_strings = b'''<?xml version="1.0" encoding="UTF-8"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="2" uniqueCount="2"><si><t>00123</t></si><si><t>Second sheet</t></si></sst>'''
styles = b'''<?xml version="1.0" encoding="UTF-8"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs></styleSheet>'''
sheet1 = b'''<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1"><v>9007199254740993</v></c><c r="D1" t="b"><v>1</v></c><c r="E1" t="e"><v>#DIV/0!</v></c><c r="F1" s="1"><v>44500.5</v></c></row>
<row r="2"><c r="B2"><f>A1*2</f><v>42</v></c></row><row r="3"><c r="C3" t="inlineStr"><is><t>Line A</t></is></c></row></sheetData>
<mergeCells count="1"><mergeCell ref="A1:B1"/></mergeCells></worksheet>'''
sheet2 = b'''<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="s"><v>1</v></c></row></sheetData></worksheet>'''
xlsx_entries = [
    ("[Content_Types].xml", content_types, ZIP_STORED, 0o100644),
    ("_rels/.rels", root_rels, ZIP_STORED, 0o100644),
    ("xl/workbook.xml", workbook_xml, ZIP_DEFLATED, 0o100644),
    ("xl/_rels/workbook.xml.rels", workbook_rels, ZIP_STORED, 0o100644),
    ("xl/sharedStrings.xml", shared_strings, ZIP_DEFLATED, 0o100644),
    ("xl/styles.xml", styles, ZIP_DEFLATED, 0o100644),
    ("xl/worksheets/sheet1.xml", sheet1, ZIP_DEFLATED, 0o100644),
    ("xl/worksheets/sheet2.xml", sheet2, ZIP_DEFLATED, 0o100644),
]
(ROOT / "semantic.xlsx").write_bytes(archive(xlsx_entries))
external_rels = workbook_rels.replace(b'Target="worksheets/sheet1.xml"',
                                      b'Target="https://example.org/sheet1.xml" TargetMode="External"')
(ROOT / "external-relationship.xlsx").write_bytes(archive([
    (path, external_rels if path == "xl/_rels/workbook.xml.rels" else payload, method, mode)
    for path, payload, method, mode in xlsx_entries
]))
bad_dtd = sheet1.replace(b'<worksheet ', b'<!DOCTYPE worksheet [<!ENTITY x SYSTEM "file:///private/secret">]><worksheet ', 1)
(ROOT / "entity-declaration.xlsx").write_bytes(archive([
    (path, bad_dtd if path == "xl/worksheets/sheet1.xml" else payload, method, mode)
    for path, payload, method, mode in xlsx_entries
]))

ods_mimetype = b"application/vnd.oasis.opendocument.spreadsheet"
ods_manifest = b'''<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">
<manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/>
<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
</manifest:manifest>'''
ods_content = b'''<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
<office:body><office:spreadsheet><table:null-date table:date-value="1899-12-30"/>
<table:table table:name="Data"><table:table-row>
<table:table-cell office:value-type="string" table:number-columns-spanned="2"><text:p>00123</text:p></table:table-cell><table:covered-table-cell/>
<table:table-cell office:value-type="float" office:value="9007199254740993"/><table:table-cell office:value-type="boolean" office:boolean-value="true"/>
</table:table-row><table:table-row><table:table-cell table:number-columns-repeated="2"/>
<table:table-cell office:value-type="float" office:value="42" table:formula="of:=[.A1]*2"/>
<table:table-cell office:value-type="date" office:date-value="2025-03-01T10:30:00"/></table:table-row></table:table>
<table:table table:name="Second"><table:table-row><table:table-cell office:value-type="string"><text:p>Second sheet</text:p></table:table-cell></table:table-row></table:table>
</office:spreadsheet></office:body></office:document-content>'''
ods_entries = [
    ("mimetype", ods_mimetype, ZIP_STORED, 0o100644),
    ("META-INF/manifest.xml", ods_manifest, ZIP_DEFLATED, 0o100644),
    ("content.xml", ods_content, ZIP_DEFLATED, 0o100644),
]
(ROOT / "semantic.ods").write_bytes(archive(ods_entries))
encrypted_manifest = ods_manifest.replace(b'</manifest:manifest>',
    b'<manifest:encryption-data manifest:checksum-type="SHA256"/></manifest:manifest>')
(ROOT / "encrypted-manifest.ods").write_bytes(archive([
    (path, encrypted_manifest if path == "META-INF/manifest.xml" else payload, method, mode)
    for path, payload, method, mode in ods_entries
]))
repeated_content = ods_content.replace(b'table:number-columns-repeated="2"',
                                       b'table:number-columns-repeated="1000000"')
(ROOT / "repeated-column-limit.ods").write_bytes(archive([
    (path, repeated_content if path == "content.xml" else payload, method, mode)
    for path, payload, method, mode in ods_entries
]))


def biff_record(identifier, payload=b""):
    return pack("<HH", identifier, len(payload)) + payload


def biff_sheet_name(name, offset):
    encoded = name.encode("ascii")
    return biff_record(0x0085, pack("<IBBB", offset, 0, 0, len(encoded)) + b"\x00" + encoded)


def biff_cell(row, column, style=0):
    return pack("<HHH", row, column, style)


def biff_workbook(version=0x0600, filepass=False):
    bof = biff_record(0x0809, pack("<HH", version, 0x0005))
    strings = [b"00123", b"Second sheet"]
    sst = biff_record(0x00FC, pack("<II", 2, 2) + b"".join(pack("<HB", len(item), 0) + item for item in strings))
    xf = biff_record(0x00E0, b"\x00\x00" + pack("<H", 0) + b"\x00" * 16)
    xf_date = biff_record(0x00E0, b"\x00\x00" + pack("<H", 14) + b"\x00" * 16)
    globals_tail = biff_record(0x0022, pack("<H", 1)) + xf + xf_date + sst
    if filepass:
        globals_tail += biff_record(0x002F, b"\x01\x00")
    globals_tail += biff_record(0x000A)
    sheet_bof = biff_record(0x0809, pack("<HH", version, 0x0010))
    formula_tokens = b"\x24" + pack("<HH", 0xFFFF, 0xFFFF) + b"\x1E" + pack("<H", 2) + b"\x05"
    formula = biff_record(0x0006, biff_cell(1, 1) + pack("<dHIH", 42.0, 0, 0, len(formula_tokens)) + formula_tokens)
    first = sheet_bof + b"".join([
        biff_record(0x00FD, biff_cell(0, 0) + pack("<I", 0)),
        biff_record(0x0203, biff_cell(0, 2) + pack("<d", 1.25)),
        biff_record(0x0205, biff_cell(0, 3) + b"\x01\x00"),
        biff_record(0x0205, biff_cell(0, 4) + b"\x07\x01"),
        biff_record(0x0203, biff_cell(0, 5, 1) + pack("<d", 44500.5)),
        formula,
        biff_record(0x00E5, pack("<H4H", 1, 0, 0, 0, 1)),
        biff_record(0x000A),
    ])
    second = sheet_bof + biff_record(0x00FD, biff_cell(0, 0) + pack("<I", 1)) + biff_record(0x000A)
    placeholders = biff_sheet_name("Data", 0) + biff_sheet_name("Second", 0)
    first_offset = len(bof) + len(placeholders) + len(globals_tail)
    second_offset = first_offset + len(first)
    globals_stream = bof + biff_sheet_name("Data", first_offset) + biff_sheet_name("Second", second_offset) + globals_tail
    workbook = globals_stream + first + second
    assert len(workbook) < 4096
    return workbook.ljust(4096, b"\x00")


def directory_entry(name, entry_type, child=0xFFFFFFFF, start=0xFFFFFFFE, size=0):
    encoded = name.encode("utf-16le") + b"\x00\x00"
    entry = bytearray(128)
    entry[:len(encoded)] = encoded
    entry[64:66] = pack("<H", len(encoded))
    entry[66] = entry_type
    entry[67] = 1
    entry[68:80] = pack("<III", 0xFFFFFFFF, 0xFFFFFFFF, child)
    entry[116:124] = pack("<II", start, size)
    return bytes(entry)


def compound_file(workbook):
    assert len(workbook) == 4096
    header = bytearray(512)
    header[:8] = bytes.fromhex("D0CF11E0A1B11AE1")
    header[24:34] = pack("<HHHHH", 0x003E, 3, 0xFFFE, 9, 6)
    header[44:52] = pack("<II", 1, 1)  # One FAT sector; directory starts at sector 1.
    header[56:76] = pack("<IIIII", 4096, 0xFFFFFFFE, 0, 0xFFFFFFFE, 0)
    header[76:80] = pack("<I", 0)
    header[80:512] = pack("<108I", *([0xFFFFFFFF] * 108))
    fat = [0xFFFFFFFD, 0xFFFFFFFE] + list(range(3, 10)) + [0xFFFFFFFE]
    fat.extend([0xFFFFFFFF] * (128 - len(fat)))
    directory = directory_entry("Root Entry", 5, child=1) + directory_entry("Workbook", 2, start=2, size=4096)
    return bytes(header) + pack("<128I", *fat) + directory.ljust(512, b"\x00") + workbook


(ROOT / "semantic.xls").write_bytes(compound_file(biff_workbook()))
(ROOT / "encrypted.xls").write_bytes(compound_file(biff_workbook(filepass=True)))
(ROOT / "biff4.xls").write_bytes(compound_file(biff_workbook(version=0x0400)))
loop = bytearray(compound_file(biff_workbook()))
loop[512 + 3 * 4:512 + 4 * 4] = pack("<I", 2)
(ROOT / "cfb-chain-loop.xls").write_bytes(loop)
(ROOT / "workbook-collection.zip").write_bytes(archive([
    ("books/semantic.xlsx", (ROOT / "semantic.xlsx").read_bytes(), ZIP_STORED, 0o100644),
    ("books/semantic.xls", (ROOT / "semantic.xls").read_bytes(), ZIP_DEFLATED, 0o100644),
    ("books/semantic.ods", (ROOT / "semantic.ods").read_bytes(), ZIP_STORED, 0o100644),
]))
(ROOT / "file-directory-collision.zip").write_bytes(archive([
    ("books", b"file", ZIP_STORED, 0o100644),
    ("books/item.csv", b"a\n1\n", ZIP_STORED, 0o100644),
]))
(ROOT / "reserved-name.zip").write_bytes(archive([
    ("CON.txt", b"reserved", ZIP_STORED, 0o100644),
]))
local_mismatch = bytearray(archive([("good.txt", b"hello", ZIP_STORED, 0o100644)]))
local_mismatch[14] ^= 0x01
(ROOT / "local-header-mismatch.zip").write_bytes(local_mismatch)
