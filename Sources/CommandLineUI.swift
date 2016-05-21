import Foundation

extension LC2200Processor {

    public func printRegisters() {
        print(self.registers)
    }

    public func printMemory() {
        print("Mem\tDec\tHex\tInstr")
        for (i, v) in memory.enumerated() {
            if v != 0 {
                print(stringForAddress(addr: i))
            }
        }
    }

}

public struct CommandLineUI {

    private var processor = LC2200Processor(shouldPrint: true)
    private var arguments: [String]
    public init(arguments: [String]) {
        self.arguments = arguments
        initializeProcessor()
    }

    private mutating func initializeProcessor() {
        if arguments.count == 1 || (arguments.count == 2 && arguments[1] == "--debug") {
            print("Loaded default/compiled program")
            processor.setupMemory(words: Program.program)
        } else if arguments.count >= 2 && arguments[1].hasSuffix(".s") {
            let filename = arguments[1]
            do {
                let instructions = try String(contentsOfFile: filename, encoding: NSUTF8StringEncoding)
                var assembler = LC2200Assembler(source: instructions)
                print("Assembling \(filename)")
                let assembled = try assembler.assemble()
                let str = assembled.reduce("") { "\($0) \(String(format: "%04X", $1))" }
                let lcFile = "\(filename.substring(to: filename.index(filename.endIndex, offsetBy: -2))).lc"
                print("Writing output to \(lcFile)")
                try str.write(toFile: lcFile, atomically: true, encoding: NSUTF8StringEncoding)
                print("Loaded \(filename) into memory, via assembler.")
                processor.setupMemory(words: assembled)
            } catch AssemblerError.OffsetTooLarge(let offset, let instruction) {
                print("Offset \(offset) is too large on line \(instruction)")
                exit(1)
            } catch AssemblerError.UnrecognizedInstruction(let line) {
                print("Unrecognized instruction on line \(line)")
                exit(1)
            } catch {
                print(error)
                exit(1)
            }
        } else {
            do {
                let memory = try String(contentsOfFile: arguments[1], encoding: NSUTF8StringEncoding)
                let vals = memory.characters.split { $0 == " " || $0 == "\n" }.map(String.init)
                let things = vals.map { (s) -> (UInt16) in
                    if let data = UInt16(s, radix: 16) {
                        return data
                    }
                    print("File \(Process.arguments[1]) is not a valid LC2200 file.")
                    exit(1)
                }
                processor.setupMemory(words: things)
                print("Loaded \(Process.arguments[1])")
            } catch {
                print(error)
                exit(1)
            }
        }
    }

    public mutating func start() {
        if Process.arguments.contains("--debug") {
            self.runDebugMode()
        } else {
            self.run()
        }
    }

    private mutating func run() {
        processor.run()
    }

    private mutating func runDebugMode() {
        var command: String = ""
        var commandArg: String = ""
        while true {

            print("(LC2200) ", separator: "", terminator: "")

            let readCommand = readLine(strippingNewline: true)?.lowercased()

            // Parse out the argument (used in breakpoint)
            if let readCommand = readCommand where readCommand != "" {
                let args = readCommand.characters.split { $0 == " " }.map(String.init)
                command = args[0]
                commandArg = args.last ?? ""
                if commandArg.contains("0x") {
                    commandArg = commandArg.substring(from: commandArg.index(commandArg.startIndex, offsetBy: 2))
                }
            }

            switch command {
            case "run", "r":
                processor.reset()
                processor.run()
            case "step", "s":
                processor.step()
            case "continue", "cont", "c":
                processor.run()
            case "back", "b":
                if !processor.rewind() {
                    print("Nothing to rewind.")
                }
            case "register", "reg":
                processor.printRegisters()
            case "reset":
                processor.reset()
            case "memory", "mem":
                processor.printMemory()
            case "break", "br":
                if let addr = UInt16(commandArg, radix: 16) {
                    processor.setBreakpoint(location: addr)
                } else {
                    print("Invalid address: \(commandArg)")
                }
            case "list", "l":
                var start = processor.currentAddress
                if start <= 5 {
                    start -= start
                } else {
                    start -= 5
                }
                let end = (start + 10 < 16 * 1024) ? start + 10 : 16 * 1024

                for i in start..<end {
                    if i == processor.currentAddress {
                        print("-> ", separator: "", terminator: "")
                    }
                    print("\t\(processor.stringForAddress(addr: Int(i)))")
                }
            case "print", "p":
                if let addr = UInt16(commandArg, radix: 16) {
                    print(processor.stringForAddress(addr: Int(addr)))
                } else if let register = RegisterFile.Register(symbol: commandArg) {
                    let regValue = processor.registers[register]
                    print(processor.stringForAddress(addr: Int(regValue)))
                } else {
                    print("Invalid address/register: \(commandArg)")
                }
            case "exit", "quit", "q":
                exit(0)
            case "help", "h":
                print()
                print("LC-2200 Simulator")
                print("Debug Mode")
                print()
                print("[r]un\t\t\tReset the processor and start the program.  All breakpoints are reset.")
                print("[s]tep\t\t\tGo forward 1 instruction.")
                print("[b]ack\t\t\tGo back 1 instruction.")
                print("[l]ist\t\t\tPrint the current memory address, with 5 lines before and after.")
                print("[p]rint (0xFFFF)\tPrint the memory location.")
                print("[p]rint ($reg)\tPrint the memory location of the value of a register.")
                print("[c]ontinue\t\tResume execution, after stopping/setting a breakpoint.")
                print("[br]eak (0xFFFF)\tAdd a breakpoint at a memory location.")
                print("[reg]ister\t\tPrint out the registers.")
                print("[mem]ory\t\tPrint out non-zero locations in the memory bank.")
                print("[q]uit\t\t\tQuit the simulator.")
                print()
            default:
                print("Invalid command: \(command)")
            }
        }
    }

}
