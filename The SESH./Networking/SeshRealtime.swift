//
//  SeshRealtime.swift
//  The SESH
//
//  (#C3) WebSocket client for the Worker's SocialDO. Replaces the fixed
//  12-second REST polling loop: the server pushes a lightweight
//  {type:"changed"} frame whenever social state mutates and the store
//  re-pulls one snapshot — presence, cyphers, live, chat previews all update
//  in near-real-time with no idle traffic.
//
//  Reconnects with exponential backoff + jitter; while the socket is down the
//  owner (SocialStore) falls back to slow polling, so nothing breaks when the
//  network or the Worker misbehaves.
//

import Foundation
import os

@MainActor
final class SeshRealtime {
    enum State { case disconnected, connecting, connected }

    private(set) var state: State = .disconnected

    /// Called on the main actor whenever the server signals a change.
    var onChange: (() -> Void)?
    /// Called when the connection state flips (for connectivity UI).
    var onStateChange: ((State) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var connectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var backoff: Double = 1
    private let log = Logger(subsystem: "com.sowens.The-SESH-", category: "realtime")

    /// Connect (or reconnect) using the current session token.
    func connect() {
        guard connectTask == nil else { return }
        connectTask = Task { [weak self] in
            defer { self?.connectTask = nil }
            await self?.runLoop()
        }
    }

    func disconnect() {
        connectTask?.cancel(); connectTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        task?.cancel(with: .goingAway, reason: nil); task = nil
        setState(.disconnected)
    }

    private func setState(_ s: State) {
        guard state != s else { return }
        state = s
        onStateChange?(s)
    }

    private func runLoop() async {
        while !Task.isCancelled {
            guard let token = SeshAuth.shared.token,
                  var comps = URLComponents(string: BuildConfig.workerURL) else {
                try? await Task.sleep(for: .seconds(5)); continue
            }
            comps.scheme = comps.scheme == "http" ? "ws" : "wss"
            comps.path = "/api/ws"
            comps.queryItems = [URLQueryItem(name: "token", value: token)]
            guard let url = comps.url else { return }

            setState(.connecting)
            let ws = URLSession.shared.webSocketTask(with: url)
            task = ws
            ws.resume()
            startHeartbeat(ws)

            // Receive until the socket dies.
            var alive = true
            while alive && !Task.isCancelled {
                do {
                    let message = try await ws.receive()
                    setState(.connected)
                    backoff = 1
                    if case .string(let text) = message,
                       text.contains("\"changed\"") {
                        onChange?()
                    }
                } catch {
                    alive = false
                }
            }
            heartbeatTask?.cancel(); heartbeatTask = nil
            ws.cancel(with: .goingAway, reason: nil)
            setState(.disconnected)
            guard !Task.isCancelled else { return }

            // Exponential backoff with jitter before reconnecting.
            let delay = backoff + Double.random(in: 0...1)
            log.info("realtime reconnect in \(delay, privacy: .public)s")
            try? await Task.sleep(for: .seconds(delay))
            backoff = min(backoff * 2, 60)
        }
    }

    /// Periodic heartbeat over the socket keeps presence fresh server-side.
    private func startHeartbeat(_ ws: URLSessionWebSocketTask) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                let uid = SeshAuth.shared.uid ?? ""
                try? await ws.send(.string(#"{"type":"heartbeat","uid":"\#(uid)"}"#))
            }
        }
    }
}
