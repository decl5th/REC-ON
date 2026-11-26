import Foundation
import Network

nonisolated final class TLVFramingProtocol: NWProtocolFramerImplementation {
    static let label = "RECOnTLV"
    static let definition = NWProtocolFramer.Definition(implementation: TLVFramingProtocol.self)

    required init(framer: NWProtocolFramer.Instance) {}

    func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult { .ready }
    func wakeup(framer: NWProtocolFramer.Instance) {}
    func stop(framer: NWProtocolFramer.Instance) -> Bool { true }
    func cleanup(framer: NWProtocolFramer.Instance) {}

    func handleInput(framer: NWProtocolFramer.Instance) -> Int {
        while true {
            var parsedHeader: Header?
            let headerSize = Header.encodedSize
            let parsed = framer.parseInput(
                minimumIncompleteLength: headerSize,
                maximumLength: headerSize
            ) { buffer, _ in
                guard let buffer, buffer.count >= headerSize else { return 0 }
                parsedHeader = Header(buffer)
                return headerSize
            }

            guard parsed, let header = parsedHeader else { return headerSize }

            let message = NWProtocolFramer.Message(definition: Self.definition)
            message["messageKind"] = header.kind

            guard framer.deliverInputNoCopy(
                length: Int(header.length),
                message: message,
                isComplete: true
            ) else {
                return 0
            }
        }
    }

    func handleOutput(
        framer: NWProtocolFramer.Instance,
        message: NWProtocolFramer.Message,
        messageLength: Int,
        isComplete: Bool
    ) {
        let kind = message["messageKind"] as? UInt32 ?? 0
        let header = Header(kind: kind, length: UInt32(messageLength))
        framer.writeOutput(data: header.encodedData)
        try? framer.writeOutputNoCopy(length: messageLength)
    }
}

private extension TLVFramingProtocol {
    struct Header {
        static let encodedSize = MemoryLayout<UInt32>.size * 2

        let kind: UInt32
        let length: UInt32

        init(kind: UInt32, length: UInt32) {
            self.kind = kind.bigEndian
            self.length = length.bigEndian
        }

        init(_ buffer: UnsafeMutableRawBufferPointer) {
            let raw = UnsafeRawBufferPointer(buffer)
            let kindValue = raw.loadUnaligned(fromByteOffset: 0, as: UInt32.self)
            let lengthValue = raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
            kind = UInt32(bigEndian: kindValue)
            length = UInt32(bigEndian: lengthValue)
        }

        var encodedData: Data {
            var kind = kind
            var length = length
            var data = Data(bytes: &kind, count: MemoryLayout<UInt32>.size)
            data.append(Data(bytes: &length, count: MemoryLayout<UInt32>.size))
            return data
        }
    }
}

extension NWProtocolFramer.Message {
    convenience init(kind: MessageKind) {
        self.init(definition: TLVFramingProtocol.definition)
        self["messageKind"] = kind.rawValue
    }

    var reconMessageKind: MessageKind? {
        guard let rawValue = self["messageKind"] as? UInt32 else { return nil }
        return MessageKind(rawValue: rawValue)
    }
}
