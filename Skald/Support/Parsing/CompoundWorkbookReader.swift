import Foundation

/// Bounded MS-CFB version 3/4 reader for the root Workbook stream, including
/// regular FAT, extended DIFAT, and mini-FAT chains.
nonisolated final class CompoundWorkbookReader {
    private static let endOfChain: UInt32 = 0xFFFFFFFE
    private static let freeSector: UInt32 = 0xFFFFFFFF
    private let bytes: Data
    private let maximumStreamBytes: Int
    private let maximumDirectoryEntries: Int
    private let sectorSize: Int
    private let miniSectorSize: Int
    private let sectorCount: Int
    private let fat: [UInt32]
    private let miniFatStart: UInt32
    private let miniFatCount: Int
    private let directoryStart: UInt32

    init(_ bytes: Data, maximumStreamBytes: Int = 64 * 1_024 * 1_024,
         maximumDirectoryEntries: Int = 1_000) throws {
        guard maximumStreamBytes > 0, maximumDirectoryEntries > 0, maximumDirectoryEntries <= 10_000,
              bytes.count >= 512,
              bytes.prefix(8) == Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) else {
            throw InputDiagnostic(code: "invalidCompoundFile", stage: "container", summary: "XLS compound-file header is missing or invalid.")
        }
        let version = Self.u16(bytes, 26)
        guard version == 3 || version == 4, Self.u16(bytes, 28) == 0xFFFE else {
            throw InputDiagnostic(code: "cfbVariantUnsupported", stage: "container", summary: "Compound-file version or byte order is unsupported.")
        }
        let shift = Int(Self.u16(bytes, 30))
        let miniShift = Int(Self.u16(bytes, 32))
        guard shift == (version == 3 ? 9 : 12), miniShift == 6,
              bytes.count >= 1 << shift, bytes.count.isMultiple(of: 1 << shift) else {
            throw InputDiagnostic(code: "invalidCompoundFile", stage: "container", summary: "Compound-file sector sizes are invalid.")
        }
        self.bytes = bytes
        self.maximumStreamBytes = maximumStreamBytes
        self.maximumDirectoryEntries = maximumDirectoryEntries
        self.sectorSize = 1 << shift
        self.miniSectorSize = 1 << miniShift
        self.sectorCount = (bytes.count - (1 << shift)) / (1 << shift)
        self.directoryStart = Self.u32(bytes, 48)
        self.miniFatStart = Self.u32(bytes, 60)
        self.miniFatCount = Int(Self.u32(bytes, 64))
        guard Self.u32(bytes, 56) == 4_096 else {
            throw InputDiagnostic(code: "invalidCompoundFile", stage: "container", summary: "Compound-file mini-stream cutoff is invalid.")
        }
        let fatCount = Int(Self.u32(bytes, 44))
        let difatStart = Self.u32(bytes, 68)
        let difatCount = Int(Self.u32(bytes, 72))
        guard fatCount <= max(1, sectorCount), difatCount <= sectorCount,
              miniFatCount <= sectorCount, directoryStart < UInt32(sectorCount) else {
            throw InputDiagnostic(code: "cfbSectorLimitExceeded", stage: "container", summary: "Compound-file allocation tables exceed file bounds.")
        }
        var fatSectors: [UInt32] = []
        for index in 0..<109 {
            let id = Self.u32(bytes, 76 + index * 4)
            if id != Self.freeSector { fatSectors.append(id) }
        }
        var difatSector = difatStart
        var seenDIFAT = Set<UInt32>()
        for _ in 0..<difatCount {
            guard difatSector < UInt32(sectorCount), seenDIFAT.insert(difatSector).inserted else {
                throw InputDiagnostic(code: "cfbChainInvalid", stage: "container", summary: "Compound-file DIFAT chain is invalid.")
            }
            let offset = (Int(difatSector) + 1) * sectorSize
            for index in 0..<(sectorSize / 4 - 1) {
                let id = Self.u32(bytes, offset + index * 4)
                if id != Self.freeSector { fatSectors.append(id) }
            }
            difatSector = Self.u32(bytes, offset + sectorSize - 4)
        }
        guard fatSectors.count == fatCount, difatSector == Self.endOfChain || difatCount == 0 else {
            throw InputDiagnostic(code: "cfbChainInvalid", stage: "container", summary: "Compound-file DIFAT and FAT counts disagree.")
        }
        var table: [UInt32] = []
        table.reserveCapacity(fatCount * sectorSize / 4)
        var seenFAT = Set<UInt32>()
        for id in fatSectors {
            guard id < UInt32(sectorCount), seenFAT.insert(id).inserted else {
                throw InputDiagnostic(code: "cfbChainInvalid", stage: "container", summary: "Compound-file FAT sector is invalid or duplicated.")
            }
            let offset = (Int(id) + 1) * sectorSize
            for index in 0..<(sectorSize / 4) { table.append(Self.u32(bytes, offset + index * 4)) }
        }
        self.fat = table
    }

    func workbookStream() throws -> Data {
        let directory = try regularChain(directoryStart, maximumBytes: maximumDirectoryEntries * 128 + sectorSize)
        guard directory.count >= 128 else {
            throw InputDiagnostic(code: "invalidCompoundFile", stage: "container", summary: "Compound-file directory is empty.")
        }
        let entries = directory.count / 128
        guard entries <= maximumDirectoryEntries else {
            throw InputDiagnostic(code: "cfbDirectoryLimitExceeded", stage: "container", summary: "Compound-file directory exceeds the entry limit.")
        }
        guard directory[66] == 5 else {
            throw InputDiagnostic(code: "invalidCompoundFile", stage: "container", summary: "Compound-file root directory entry is invalid.")
        }
        var workbook: (start: UInt32, size: Int)?
        for index in 1..<entries {
            if Task.isCancelled { throw OutputPublicationError.cancelled }
            let offset = index * 128
            guard directory[offset + 66] == 2 else { continue }
            let nameLength = Int(Self.u16(directory, offset + 64))
            guard nameLength >= 2, nameLength <= 64, nameLength.isMultiple(of: 2) else {
                throw InputDiagnostic(code: "invalidCompoundFile", stage: "container", summary: "Compound-file stream name is malformed.")
            }
            let name = String(data: directory[offset..<(offset + nameLength - 2)], encoding: .utf16LittleEndian)
            if name == "Workbook" || name == "Book" {
                guard workbook == nil else {
                    throw InputDiagnostic(code: "cfbWorkbookCollision", stage: "container", summary: "Compound file has more than one Workbook stream.")
                }
                guard Self.u32(directory, offset + 124) == 0 else {
                    throw InputDiagnostic(code: "cfbStreamLimitExceeded", stage: "container", summary: "Workbook stream exceeds the supported byte range.")
                }
                workbook = (Self.u32(directory, offset + 116), Int(Self.u32(directory, offset + 120)))
            }
        }
        guard let workbook, workbook.size > 0, workbook.size <= maximumStreamBytes else {
            throw InputDiagnostic(code: "invalidXLS", stage: "container", summary: "XLS Workbook stream is missing or exceeds the byte limit.")
        }
        if workbook.size >= 4_096 {
            let stream = try regularChain(workbook.start, maximumBytes: workbook.size + sectorSize)
            guard stream.count >= workbook.size else {
                throw InputDiagnostic(code: "cfbChainInvalid", stage: "container", summary: "Workbook stream sector chain is shorter than its size.")
            }
            return Data(stream.prefix(workbook.size))
        }
        guard miniFatCount > 0, miniFatStart != Self.endOfChain else {
            throw InputDiagnostic(code: "cfbChainInvalid", stage: "container", summary: "Small Workbook stream has no mini-FAT.")
        }
        let miniTableBytes = try regularChain(miniFatStart, maximumBytes: miniFatCount * sectorSize + sectorSize)
        guard miniTableBytes.count >= miniFatCount * sectorSize else {
            throw InputDiagnostic(code: "cfbChainInvalid", stage: "container", summary: "Mini-FAT chain is shorter than declared.")
        }
        var miniTable: [UInt32] = []
        for offset in stride(from: 0, to: miniFatCount * sectorSize, by: 4) {
            miniTable.append(Self.u32(miniTableBytes, offset))
        }
        let rootStart = Self.u32(directory, 116)
        let rootSize = Int(Self.u32(directory, 120))
        guard Self.u32(directory, 124) == 0, rootSize > 0, rootSize <= maximumStreamBytes else {
            throw InputDiagnostic(code: "cfbChainInvalid", stage: "container", summary: "Compound-file mini stream is missing or oversized.")
        }
        let miniStream = try regularChain(rootStart, maximumBytes: rootSize + sectorSize)
        guard miniStream.count >= rootSize else {
            throw InputDiagnostic(code: "cfbChainInvalid", stage: "container", summary: "Compound-file mini stream is truncated.")
        }
        var result = Data()
        var id = workbook.start
        var visited = Set<UInt32>()
        while id != Self.endOfChain, result.count < workbook.size {
            if Task.isCancelled { throw OutputPublicationError.cancelled }
            guard id < UInt32(miniTable.count), visited.insert(id).inserted,
                  Int(id) * miniSectorSize <= rootSize - miniSectorSize else {
                throw InputDiagnostic(code: "cfbChainInvalid", stage: "container", summary: "Workbook mini-stream chain is invalid.")
            }
            let offset = Int(id) * miniSectorSize
            result.append(miniStream[offset..<(offset + miniSectorSize)])
            id = miniTable[Int(id)]
        }
        guard result.count >= workbook.size else {
            throw InputDiagnostic(code: "cfbChainInvalid", stage: "container", summary: "Workbook mini-stream chain is truncated.")
        }
        return Data(result.prefix(workbook.size))
    }

    private func regularChain(_ start: UInt32, maximumBytes: Int) throws -> Data {
        var result = Data()
        var id = start
        var visited = Set<UInt32>()
        while id != Self.endOfChain {
            if Task.isCancelled { throw OutputPublicationError.cancelled }
            guard id < UInt32(sectorCount), id < UInt32(fat.count), visited.insert(id).inserted,
                  sectorSize <= maximumBytes - result.count else {
                throw InputDiagnostic(code: "cfbChainInvalid", stage: "container", summary: "Compound-file sector chain loops, escapes, or exceeds its limit.")
            }
            let offset = (Int(id) + 1) * sectorSize
            result.append(bytes[offset..<(offset + sectorSize)])
            id = fat[Int(id)]
        }
        return result
    }

    private static func u16(_ bytes: Data, _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func u32(_ bytes: Data, _ offset: Int) -> UInt32 {
        UInt32(u16(bytes, offset)) | UInt32(u16(bytes, offset + 2)) << 16
    }
}
