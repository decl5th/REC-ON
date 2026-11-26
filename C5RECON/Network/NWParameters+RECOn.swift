import Network

extension NWParameters {
    nonisolated static var recOnTCP: NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 2
        tcp.connectionTimeout = 5

        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.serviceClass = .interactiveVideo
        // Allow nearby Apple devices to remain reachable even when the
        // infrastructure Wi-Fi blocks client-to-client multicast traffic.
        parameters.includePeerToPeer = true
        let framer = NWProtocolFramer.Options(definition: TLVFramingProtocol.definition)
        parameters.defaultProtocolStack.applicationProtocols.insert(framer, at: 0)
        return parameters
    }
}
