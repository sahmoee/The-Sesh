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

nonisolated enum SeshRealtimeFramePolicy {
    static let maximumBytes = 64 * 1024
    nonisolated private struct Event: Decodable { let type: String }

    static func eventType(in data: Data) -> String? {
        guard !data.isEmpty, data.count <= maximumBytes,
              let event = try? JSONDecoder().decode(Event.self, from: data),
              ["welcome", "pong", "changed"].contains(event.type) else { return nil }
        return event.type
    }
}

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
    private var notificationTask: Task<Void, Never>?
    private var generation = UUID()
    private let maximumFrameBytes = SeshRealtimeFramePolicy.maximumBytes
    private var backoff: Double = 1
    private let log = Logger(subsystem: "com.sowens.The-SESH-", category: "realtime")

    /// Connect (or reconnect) using the current session token.
    func connect() {
        guard connectTask == nil else { return }
        let connectionGeneration = UUID()
        generation = connectionGeneration
        connectTask = Task { [weak self] in
            defer {
                if self?.generation == connectionGeneration { self?.connectTask = nil }
            }
            await self?.runLoop(generation: connectionGeneration)
        }
    }

    func disconnect() {
        generation = UUID()
        connectTask?.cancel(); connectTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        notificationTask?.cancel(); notificationTask = nil
        task?.cancel(with: .goingAway, reason: nil); task = nil
        backoff = 1
        setState(.disconnected)
    }

    private func setState(_ s: State) {
        guard state != s else { return }
        state = s
        onStateChange?(s)
    }

    private func runLoop(generation connectionGeneration: UUID) async {
        while !Task.isCancelled && generation == connectionGeneration {
            guard let token = SeshAuth.shared.token,
                  let url = SeshUnifiedWorker.webSocketURL(token: token) else {
                guard await pause(seconds: 5, generation: connectionGeneration) else { return }
                continue
            }

            setState(.connecting)
            let ws = URLSession.shared.webSocketTask(with: url)
            ws.maximumMessageSize = maximumFrameBytes
            task = ws
            ws.resume()
            startHeartbeat(ws, generation: connectionGeneration)

            // Receive until the socket dies.
            var alive = true
            while alive && !Task.isCancelled && generation == connectionGeneration {
                do {
                    let message = try await ws.receive()
                    guard !Task.isCancelled, generation == connectionGeneration, task === ws else { break }
                    if let data = frameData(message), let event = SeshRealtimeFramePolicy.eventType(in: data) {
                        setState(.connected)
                        backoff = 1
                        if event == "changed" { scheduleChange(generation: connectionGeneration) }
                    }
                } catch {
                    alive = false
                }
            }
            ws.cancel(with: .goingAway, reason: nil)
            // Old receive-loop cleanup may run after disconnect + a new connect.
            // It must never clear the new connection or cancel its heartbeat.
            guard generation == connectionGeneration, task === ws else { return }
            heartbeatTask?.cancel(); heartbeatTask = nil
            notificationTask?.cancel(); notificationTask = nil
            task = nil
            setState(.disconnected)
            guard !Task.isCancelled else { return }

            // Exponential backoff with jitter before reconnecting.
            let delay = backoff + Double.random(in: 0...1)
            log.info("realtime reconnect in \(delay, privacy: .public)s")
            guard await pause(seconds: delay, generation: connectionGeneration) else { return }
            backoff = min(backoff * 2, 60)
        }
    }

    /// Periodic heartbeat over the socket keeps presence fresh server-side.
    private func startHeartbeat(_ ws: URLSessionWebSocketTask, generation connectionGeneration: UUID) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor in
            while !Task.isCancelled {
                guard await pause(seconds: 30, generation: connectionGeneration), task === ws else { return }
                do {
                    try await ws.send(.string(#"{"type":"heartbeat"}"#))
                } catch {
                    ws.cancel(with: .goingAway, reason: nil)
                    return
                }
            }
        }
    }

    private func pause(seconds: Double, generation connectionGeneration: UUID) async -> Bool {
        do { try await Task.sleep(for: .seconds(seconds)) }
        catch { return false }
        return !Task.isCancelled && generation == connectionGeneration
    }

    private func frameData(_ message: URLSessionWebSocketTask.Message) -> Data? {
        switch message {
        case .string(let text):
            guard text.utf8.count <= maximumFrameBytes else { return nil }
            return text.data(using: .utf8)
        case .data(let data): return data.count <= maximumFrameBytes ? data : nil
        @unknown default: return nil
        }
    }

    /// At most one snapshot invalidation every 250 ms during a mutation burst.
    private func scheduleChange(generation connectionGeneration: UUID) {
        guard notificationTask == nil else { return }
        notificationTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            guard let self, !Task.isCancelled, self.generation == connectionGeneration else { return }
            self.notificationTask = nil
            self.onChange?()
        }
    }
}
