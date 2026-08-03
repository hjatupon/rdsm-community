import Foundation
import Logging

/// Owns the live rosbridge v2 connection: WebSocket channel, topic discovery,
/// per-topic delivery, parameters via /rosapi, and the reconnect state machine.
///
/// All mutable state is actor-isolated. The receive loop runs in a detached task.
actor RosbridgeConnectionActor {
    private let connector: any WebSocketConnecting
    private let config: TransportConfig
    private let logger: any LoggerProtocol
    private let stateContinuation: AsyncStream<TransportState>.Continuation

    private var url: URL?
    private var channel: (any WebSocketChannel)?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var isShuttingDown = false
    /// Tracks the last emitted state so callers can query it without a stream subscription.
    private(set) var lastKnownState: TransportState = .disconnected

    /// Topic name → ROS message type (populated from /rosapi/topics).
    private var topicsCache: [String: String] = [:]
    private var topicsDiscovered = false
    private var topicsDiscoveryId: String?

    private struct Subscription {
        let id: String
        let continuation: AsyncStream<TopicMessage>.Continuation
    }
    private var subscriptionsByTopic: [String: Subscription] = [:]
    private var nextSubId = 0

    /// Pending /rosapi service calls awaiting their service_response.
    private var pendingServiceCalls: [String: CheckedContinuation<[String: Any], Error>] = [:]

    init(
        connector: any WebSocketConnecting,
        config: TransportConfig,
        logger: any LoggerProtocol,
        stateContinuation: AsyncStream<TransportState>.Continuation)
    {
        self.connector = connector
        self.config = config
        self.logger = logger
        self.stateContinuation = stateContinuation
    }

    // MARK: - State helper

    private func emitState(_ s: TransportState) {
        lastKnownState = s
        stateContinuation.yield(s)
    }

    // MARK: - Connect / disconnect

    func connect(url: URL) async throws {
        self.url = url
        isShuttingDown = false
        emitState(.connecting)
        do {
            let ch = try await connector.connect(url: url, subprotocols: [])
            // Probe: attempt a send to confirm the server is listening.
            // Connection refused surfaces here as an error before the 2s timeout.
            try await connectionProbe(ch)
            channel = ch
            startReceiveLoop(on: ch)
            emitState(.connected)
            let reqId = UUID().uuidString
            topicsDiscoveryId = reqId
            topicsDiscovered = false
            try? await ch.send(.text(RosbridgeProtocol.getTopicsFrame(requestId: reqId)))
        } catch let te as TransportError {
            emitState(.failed(te))
            throw te
        } catch {
            let wrapped = TransportError.handshakeFailed(reason: error.localizedDescription)
            emitState(.failed(wrapped))
            throw wrapped
        }
    }

    /// Probes the connection by attempting to send a harmless frame.
    /// Throws immediately if the server is not listening (connection refused).
    /// Uses send() instead of receive() so Swift task cancellation works correctly —
    /// URLSessionWebSocketTask.receive() does not cooperate with cooperative cancellation.
    private func connectionProbe(_ ch: any WebSocketChannel) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                // set_level is a no-op from the server's perspective: no response frame.
                try await ch.send(.text("{\"op\":\"set_level\",\"level\":\"none\",\"id\":\"probe\"}"))
            }
            group.addTask { try await Task.sleep(for: .seconds(2)) }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    func disconnect() async {
        isShuttingDown = true
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        await channel?.close()
        channel = nil
        for sub in subscriptionsByTopic.values { sub.continuation.finish() }
        subscriptionsByTopic.removeAll()
        for (_, cont) in pendingServiceCalls { cont.resume(throwing: TransportError.notConnected) }
        pendingServiceCalls.removeAll()
        emitState(.disconnected)
    }

    // MARK: - Topics

    func listTopics() async -> [TopicDescriptor] {
        if !topicsDiscovered, channel != nil {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while !topicsDiscovered, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        return topicsCache
            .map { TopicDescriptor(name: $0.key, schemaName: $0.value, schemaEncoding: "json", schema: nil) }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Subscribe / unsubscribe

    func subscribe(_ topic: String) async throws -> AsyncStream<TopicMessage> {
        guard channel != nil else { throw TransportError.notConnected }

        // Wait for initial topic discovery so we can include the type.
        if !topicsDiscovered {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while !topicsDiscovered, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }

        // Idempotent: tear down existing sub and let the newest caller win.
        if let existing = subscriptionsByTopic[topic] {
            existing.continuation.finish()
        }

        let subId = "sub_\(nextSubId)"
        nextSubId += 1
        let type = topicsCache[topic] ?? ""

        let (stream, continuation) = AsyncStream.makeStream(
            of: TopicMessage.self,
            bufferingPolicy: .bufferingNewest(config.topicBufferSize))
        subscriptionsByTopic[topic] = Subscription(id: subId, continuation: continuation)

        guard let ch = channel else { throw TransportError.notConnected }
        let frame = RosbridgeProtocol.subscribeFrame(id: subId, topic: topic, type: type, throttleMs: config.subscribeThrottleMs)
        try await ch.send(.text(frame))
        return stream
    }

    func unsubscribe(_ topic: String) async throws {
        guard let sub = subscriptionsByTopic.removeValue(forKey: topic) else { return }
        sub.continuation.finish()
        let frame = RosbridgeProtocol.unsubscribeFrame(id: sub.id)
        try await channel?.send(.text(frame))
    }

    // MARK: - Receive loop

    private func startReceiveLoop(on ch: any WebSocketChannel) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let frame = try await ch.receive()
                    await self?.handleFrame(frame)
                } catch is CancellationError {
                    return  // intentional cancel — don't reconnect
                } catch {
                    await self?.handleDrop(error)
                    return
                }
            }
        }
    }

    private func handleFrame(_ frame: WebSocketFrame) {
        guard case let .text(text) = frame else { return }
        guard let msg = RosbridgeProtocol.parseServerMessage(text) else {
            logger.warning("dropping unparseable rosbridge frame")
            return
        }
        switch msg {
        case let .publish(topic, msgDict):
            deliver(topic: topic, msg: msgDict)
        case let .serviceResponse(id, _, result, values):
            if let continuation = pendingServiceCalls.removeValue(forKey: id) {
                if result {
                    continuation.resume(returning: values)
                } else {
                    let reason = (values["message"] as? String) ?? "service returned result:false"
                    continuation.resume(throwing: TransportError.serviceCallFailed(reason: reason))
                }
            } else if id == topicsDiscoveryId {
                if result { applyTopicsResponse(values) }
                topicsDiscoveryId = nil
            }
        case let .status(level, text):
            if level == "error" || level == "warning" {
                logger.warning("rosbridge status", fields: [
                    LogField(key: "level", value: level),
                    LogField(key: "msg", value: text),
                ])
            }
        case .other:
            break
        }
    }

    private func applyTopicsResponse(_ values: [String: Any]) {
        guard let topics = values["topics"] as? [String],
              let types = values["types"] as? [String] else { return }
        topicsCache.removeAll()
        for (i, topic) in topics.enumerated() {
            topicsCache[topic] = i < types.count ? types[i] : ""
        }
        topicsDiscovered = true
    }

    private func deliver(topic: String, msg: [String: Any]) {
        guard let sub = subscriptionsByTopic[topic] else { return }
        guard let payload = try? JSONSerialization.data(withJSONObject: msg) else { return }
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        let message = TopicMessage(
            topic: topic,
            timestamp: timestamp,
            schemaName: topicsCache[topic] ?? "",
            payload: payload)
        let result = sub.continuation.yield(message)
        if case .dropped = result {
            logger.warning("topic buffer full, dropped oldest", fields: [LogField(key: "topic", value: topic)])
        }
    }

    // MARK: - Parameters (via /rosapi services)

    func listNodes() async throws -> [String] {
        let reqId = UUID().uuidString
        let frame = RosbridgeProtocol.getNodesFrame(requestId: reqId)
        let values = try await callServiceAsync(frame: frame, requestId: reqId)
        return ((values["nodes"] as? [String]) ?? []).sorted()
    }

    func getParameters(node: String) async throws -> [Parameter] {
        // Step 1: List parameter names via the standard ROS2 /{node}/list_parameters service.
        // This is faster and more reliable than /rosapi/get_param_names (which queries ALL nodes).
        let listId = UUID().uuidString
        let listFrame = RosbridgeProtocol.listNodeParametersFrame(requestId: listId, node: node)
        let listValues = try await callServiceAsync(frame: listFrame, requestId: listId)

        // Response: { "result": { "names": [...], "prefixes": [...] } }
        guard let resultDict = listValues["result"] as? [String: Any],
              let names = resultDict["names"] as? [String],
              !names.isEmpty else { return [] }

        // Step 2: Fetch all parameter values in a single batch call via /{node}/get_parameters.
        let getParamsId = UUID().uuidString
        let getParamsFrame = RosbridgeProtocol.getNodeParametersFrame(requestId: getParamsId, node: node, names: names)
        let getParamsValues = try await callServiceAsync(frame: getParamsFrame, requestId: getParamsId)

        // Response: { "values": [ { "type": N, "bool_value": ..., ... }, ... ] }
        guard let rawValues = getParamsValues["values"] as? [[String: Any]] else { return [] }

        var parameters: [Parameter] = []
        for (index, name) in names.enumerated() {
            guard index < rawValues.count,
                  let paramValue = RosbridgeProtocol.parameterValueFromROS2(rawValues[index])
            else { continue }
            // Store parameters with a qualified name "{node}:{param_name}" so that
            // setParameter can reconstruct the node and call the right service.
            let qualifiedName = node + ":" + name
            parameters.append(Parameter(name: qualifiedName, value: paramValue))
        }
        return parameters
    }

    func setParameter(_ parameter: Parameter) async throws {
        // Parameter names are stored as "{node}:{param_name}" (colon separator).
        // Split to get node and unqualified name for the standard ROS2 set_parameters service.
        if let colonIndex = parameter.name.firstIndex(of: ":") {
            let node = String(parameter.name[parameter.name.startIndex ..< colonIndex])
            let unqualifiedName = String(parameter.name[parameter.name.index(after: colonIndex)...])
            let reqId = UUID().uuidString
            let frame = RosbridgeProtocol.setNodeParameterFrame(
                requestId: reqId, node: node,
                name: unqualifiedName, value: parameter.value)
            let values = try await callServiceAsync(frame: frame, requestId: reqId)
            // set_parameters response body: {"results": [{"successful": bool, "reason": "..."}]}
            if let results = values["results"] as? [[String: Any]],
               let first = results.first,
               let successful = first["successful"] as? Bool,
               !successful {
                let reason = (first["reason"] as? String) ?? "parameter rejected by node"
                throw TransportError.serviceCallFailed(reason: reason)
            }
        } else {
            // Fallback: no node prefix — use legacy /rosapi/set_param
            let reqId = UUID().uuidString
            let frame = RosbridgeProtocol.setParamFrame(requestId: reqId, name: parameter.name, value: parameter.value)
            _ = try await callServiceAsync(frame: frame, requestId: reqId)
        }
    }

    private func callServiceAsync(frame: String, requestId: String) async throws -> [String: Any] {
        guard let ch = channel else { throw TransportError.notConnected }
        return try await withCheckedThrowingContinuation { continuation in
            pendingServiceCalls[requestId] = continuation
            Task {
                do {
                    try await ch.send(.text(frame))
                } catch {
                    if let cont = pendingServiceCalls.removeValue(forKey: requestId) {
                        cont.resume(throwing: error)
                    }
                    return
                }
                // Configurable timeout: if handleFrame hasn't already claimed the continuation, expire it.
                try? await Task.sleep(for: config.serviceTimeout)
                if let cont = pendingServiceCalls.removeValue(forKey: requestId) {
                    cont.resume(throwing: TransportError.timeout)
                }
            }
        }
    }

    /// Calls an arbitrary ROS 2 service with pre-encoded JSON args.
    /// Thread-safe: serialized through the actor.
    func callService(service: String, argsJSON: Data) async throws -> Data {
        let requestId = "srv_\(UUID().uuidString.prefix(8))"
        let argsString = String(data: argsJSON, encoding: .utf8) ?? "{}"
        let frame = RosbridgeProtocol.callServiceFrame(requestId: requestId, service: service, argsJSON: argsString)
        let result = try await callServiceAsync(frame: frame, requestId: requestId)
        return try JSONSerialization.data(withJSONObject: result)
    }

    // MARK: - Capabilities & publish

    func capabilities() -> [String] { ["clientPublish"] }

    func publish(topic: String, payload: Data) async throws {
        guard let ch = channel else { throw TransportError.notConnected }
        guard let frame = RosbridgeProtocol.publishFrame(topic: topic, msgData: payload) else {
            throw TransportError.protocolViolation("publish payload is not valid JSON")
        }
        try await ch.send(.text(frame))
    }

    // MARK: - Reconnect

    private func handleDrop(_ error: Error) {
        logger.warning("transport dropped: \(error)", fields: [LogField(key: "error", value: "\(error)")])
        guard !isShuttingDown else { return }
        receiveTask = nil
        channel = nil
        reconnectTask = Task { [weak self] in
            await self?.runReconnect()
        }
    }

    private func runReconnect() async {
        guard let url else { return }
        for attempt in 1 ... config.maxReconnectAttempts {
            if isShuttingDown { return }
            emitState(.reconnecting(attempt: attempt))
            try? await Task.sleep(for: config.backoffDelay(forAttempt: attempt))
            if isShuttingDown { return }
            do {
                let ch = try await connector.connect(url: url, subprotocols: [])
                try await connectionProbe(ch)
                channel = ch
                topicsDiscovered = false
                startReceiveLoop(on: ch)
                emitState(.connected)
                let reqId = UUID().uuidString
                topicsDiscoveryId = reqId
                try? await ch.send(.text(RosbridgeProtocol.getTopicsFrame(requestId: reqId)))
                try await resubscribeAll()
                return
            } catch {
                logger.warning("reconnect attempt failed",
                               fields: [LogField(key: "attempt", value: String(attempt))])
            }
        }
        emitState(.failed(TransportError.maxReconnectExceeded))
        for sub in subscriptionsByTopic.values { sub.continuation.finish() }
        subscriptionsByTopic.removeAll()
        stateContinuation.finish()
    }

    private func resubscribeAll() async throws {
        for (topic, sub) in subscriptionsByTopic {
            let type = topicsCache[topic] ?? ""
            let frame = RosbridgeProtocol.subscribeFrame(id: sub.id, topic: topic, type: type, throttleMs: config.subscribeThrottleMs)
            try await channel?.send(.text(frame))
        }
    }
}
