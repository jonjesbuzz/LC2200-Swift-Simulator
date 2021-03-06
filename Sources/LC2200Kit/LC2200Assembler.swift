import Foundation

public struct LC2200Assembler {

    public let source: String
    fileprivate var labels = [String: UInt16]()

    public init(source: String) {
        self.source = source
    }

    public mutating func assemble() throws -> [UInt16] {
        var lines = preprocess()
        processCommentsAndLabels(&lines)
        try changeOffsetFormat(&lines)
        return try assemble(lines)
    }

    fileprivate func preprocess() -> [String] {
        return source.split(separator: "\n").map(String.init)
    }

    fileprivate mutating func processCommentsAndLabels(_ lines: inout [String]) {
        for (index, line) in lines.enumerated() {
            let comment = line.components(separatedBy: LanguageMap.commentCharacterSet)
            if comment.count > 1 {
                lines[index] = comment[0]
            }
        }
        lines = lines.map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }.filter { $0 != "" }
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let labeledLine = line.components(separatedBy: LanguageMap.labelCharacterSet)
            if labeledLine.count > 2 {
                fatalError("Multiple labels on same line")
            } else if labeledLine.count == 1 {
                lines[index] = labeledLine[0].trimmingCharacters(in: CharacterSet.whitespaces)
            } else if labeledLine.count > 1 {
                labels[labeledLine[0].trimmingCharacters(in: CharacterSet.whitespaces)] = UInt16(index)
                lines[index] = labeledLine[1].trimmingCharacters(in: CharacterSet.whitespaces)
            }
            if lines[index] == "" {
                lines.remove(at: index)
                continue
            }
            let instr = lines[index].components(separatedBy: LanguageMap.delimiterSet).filter { $0 != "" }
            if instr[0].lowercased() == "la" {
                lines.remove(at: index)
                lines.insert(".word \(instr[2])", at: index)
                lines.insert("beq $zero, $zero, 1", at: index)
                lines.insert("lw \(instr[1]) 2(\(instr[1]))", at: index)
                lines.insert("jalr \(instr[1]), \(instr[1])", at: index)
            }
            if instr[0].lowercased() == ".orig" || instr[0].lowercased() == ".blkw" {
                print(".orig and .blkw are not supported.")
            }
            index += 1
        }
    }

    /**
     * Makes offsets for BEQ from labels, and switches LW/SW into easier to parse syntax
     */
    fileprivate mutating func changeOffsetFormat(_ lines: inout [String]) throws {
        for (index, line) in lines.enumerated() {
            let instr: [String] = line.components(separatedBy: LanguageMap.delimiterSet).filter { $0 != "" }
            if instr.count == 4 && instr[0].lowercased() == "beq" {
                if let labelAddr = labels[instr[3]] {
                    let offset = Int8(Int(labelAddr) - index) - 1
                    if (offset >= 16 || offset < -16) {
                        throw AssemblerError.offsetTooLarge(offset: Int(offset), instruction: line)
                    }
                    lines[index] = "\(instr[0]) \(instr[1]), \(instr[2]), \(offset)"
                }
            } else if instr.count == 3 && (instr[0].lowercased() == "lw" || instr[0].lowercased() == "sw") {
                let offsetInformation = instr[2].components(separatedBy: CharacterSet(charactersIn: "()")).map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
                lines[index] = "\(instr[0]) \(instr[1]), \(offsetInformation[1]), \(offsetInformation[0])"
                let offset = Int8(offsetInformation[0], radix: 10)!
                if (offset >= 16 || offset < -16) {
                    throw AssemblerError.offsetTooLarge(offset: Int(offset), instruction: line)
                }
            }
        }
    }

    fileprivate mutating func assemble(_ lines: [String]) throws -> [UInt16] {
        var memory = [UInt16]()
        for line in lines {
            let instr = line.components(separatedBy: LanguageMap.delimiterSet).filter { $0 != "" }
            if let psop = LanguageMap.pseudoops[line] {
                memory.append(UInt16(psop))
            } else if instr[0] == ".word"  && instr.count == 2 {
                if let label = labels[instr[1]] {
                    memory.append(label)
                } else {
                    var num = instr[1]
                    if num.hasPrefix("0x") {
                        num = String(num.dropFirst(2))
                    }
                    if let addr16 = UInt16(num, radix: 16) {
                        memory.append(addr16)
                    } else {
                        throw AssemblerError.notANumber(instruction: line)
                    }
                }
            } else {
                let instr = try Instruction(string: line)
                memory.append(instr.assembledInstruction)
            }
        }
        return memory
    }

}

public enum AssemblerError: Error {
    case offsetTooLarge(offset: Int, instruction: String)
    case unrecognizedInstruction(string: String)
    case notANumber(instruction: String)
}

internal struct LanguageMap {

    static let labelCharacterSet = CharacterSet(charactersIn: ":")
    static let commentCharacterSet = CharacterSet(charactersIn: "!")
    static let delimiterSet = CharacterSet(charactersIn: ", ")

    static let pseudoops = [
        "noop": 0x0000,
        "halt": 0xE000
    ]
}
