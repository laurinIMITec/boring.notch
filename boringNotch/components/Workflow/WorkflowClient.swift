//
//  WorkflowClient.swift
//  boringNotch
//
//  HTTP-Zugriff auf die lokale Workflow-App (API-Vertrag siehe brief.md).
//

import Foundation

// MARK: - Endpoint

struct WorkflowEndpoint: Equatable, Sendable {
    let port: Int
    let token: String

    /// Echtes Home ermitteln; die App ist sandboxed und sieht sonst den Container.
    static var fileURL: URL {
        let home: String
        if let passwordEntry = getpwuid(getuid()) {
            home = String(cString: passwordEntry.pointee.pw_dir)
        } else {
            home = NSHomeDirectory()
        }
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".leitstand", isDirectory: true)
            .appendingPathComponent("endpoint", isDirectory: false)
    }

    /// Liest `port=` und `token=` aus `~/.leitstand/endpoint`.
    static func load() -> WorkflowEndpoint? {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        var port: Int?
        var token: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  !line.hasPrefix("#"),
                  let separator = line.firstIndex(of: "=") else { continue }

            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)

            switch key {
            case "port":
                port = Int(value)
            case "token":
                token = value
            default:
                break
            }
        }

        guard let port = port, (1...65535).contains(port),
              let token = token, !token.isEmpty else {
            return nil
        }
        return WorkflowEndpoint(port: port, token: token)
    }
}

// MARK: - Errors

enum WorkflowClientError: Error, Equatable, Sendable {
    case notRunning
    case unauthorized
    case http(Int)
    case decoding
    case transport
}

// MARK: - Client

final class WorkflowClient: @unchecked Sendable {
    private let session: URLSession
    private(set) var endpoint: WorkflowEndpoint?

    init(endpoint: WorkflowEndpoint? = WorkflowEndpoint.load(), session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    /// Port und Token aendern sich bei jedem Neustart der Workflow-App.
    func refreshEndpoint() {
        endpoint = WorkflowEndpoint.load()
    }

    /// `GET /api/state`; ohne `since`/`wait` ein normaler GET, sonst Long-Poll.
    func fetchState(since: Int? = nil, wait: Int? = nil) async throws -> WorkflowState {
        let endpoint = try endpointOrLoad()

        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = endpoint.port
        components.path = "/api/state"

        var queryItems: [URLQueryItem] = []
        if let since = since {
            queryItems.append(URLQueryItem(name: "since", value: String(since)))
        }
        if let wait = wait {
            queryItems.append(URLQueryItem(name: "wait", value: String(wait)))
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else { throw WorkflowClientError.transport }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(endpoint.token, forHTTPHeaderField: "x-leitstand-token")

        let data = try await perform(request)
        do {
            return try JSONDecoder().decode(WorkflowState.self, from: data)
        } catch {
            throw WorkflowClientError.decoding
        }
    }

    /// `POST /api/action` mit einem frei zusammengesetzten JSON-Objekt.
    func send(action: [String: Any]) async throws -> WorkflowActionResult {
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: action, options: [])
        } catch {
            throw WorkflowClientError.decoding
        }
        return try await send(body: body)
    }

    /// `POST /api/action` mit einem `Encodable`-Body.
    func send<Action: Encodable>(action: Action) async throws -> WorkflowActionResult {
        let body: Data
        do {
            body = try JSONEncoder().encode(action)
        } catch {
            throw WorkflowClientError.decoding
        }
        return try await send(body: body)
    }

    // MARK: Private

    private func send(body: Data) async throws -> WorkflowActionResult {
        let endpoint = try endpointOrLoad()
        guard let url = URL(string: "http://127.0.0.1:\(endpoint.port)/api/action") else {
            throw WorkflowClientError.transport
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = body
        request.setValue(endpoint.token, forHTTPHeaderField: "x-leitstand-token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data = try await perform(request)
        do {
            return try JSONDecoder().decode(WorkflowActionResult.self, from: data)
        } catch {
            throw WorkflowClientError.decoding
        }
    }

    private func endpointOrLoad() throws -> WorkflowEndpoint {
        if let endpoint = endpoint {
            return endpoint
        }
        guard let loaded = WorkflowEndpoint.load() else {
            throw WorkflowClientError.notRunning
        }
        endpoint = loaded
        return loaded
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw WorkflowClientError.transport
            }

            switch httpResponse.statusCode {
            case 200..<300:
                return data
            case 401, 403:
                refreshEndpoint()
                throw WorkflowClientError.unauthorized
            default:
                throw WorkflowClientError.http(httpResponse.statusCode)
            }
        } catch let error as WorkflowClientError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            // Verbindungsfehler: Endpoint-Datei kann sich geaendert haben.
            refreshEndpoint()
            throw WorkflowClientError.transport
        }
    }
}
