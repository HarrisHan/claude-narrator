import Foundation
import Network

struct HookPayload: Decodable {
  let sessionID: String?
  let cwd: String?
  let hookEventName: String?
  let lastAssistantMessage: String?

  enum CodingKeys: String, CodingKey {
    case sessionID = "session_id"
    case cwd
    case hookEventName = "hook_event_name"
    case lastAssistantMessage = "last_assistant_message"
  }
}

final class HookServer {
  enum State: Equatable {
    case starting
    case ready
    case failed(String)
  }

  var onPayload: ((HookPayload) -> Void)?
  var onStateChange: ((State) -> Void)?

  private let port: UInt16
  private let queue = DispatchQueue(label: "com.harris.ClaudeNarrator.hook-server")
  private var listener: NWListener?

  init(port: UInt16) {
    self.port = port
  }

  func start() {
    guard listener == nil else { return }
    do {
      let parameters = NWParameters.tcp
      parameters.allowLocalEndpointReuse = true
      parameters.requiredLocalEndpoint = .hostPort(
        host: NWEndpoint.Host("127.0.0.1"),
        port: NWEndpoint.Port(rawValue: port)!
      )
      let listener = try NWListener(using: parameters)
      self.listener = listener
      listener.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        switch state {
        case .ready:
          self.onStateChange?(.ready)
        case .failed(let error):
          self.onStateChange?(.failed(error.localizedDescription))
          listener.cancel()
        case .cancelled:
          break
        default:
          self.onStateChange?(.starting)
        }
      }
      listener.newConnectionHandler = { [weak self] connection in
        self?.handle(connection)
      }
      listener.start(queue: queue)
    } catch {
      onStateChange?(.failed(error.localizedDescription))
    }
  }

  func stop() {
    listener?.cancel()
    listener = nil
  }

  private func handle(_ connection: NWConnection) {
    connection.start(queue: queue)
    receive(on: connection, buffer: Data())
  }

  private func receive(on connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
      [weak self] data, _, isComplete, error in
      guard let self else {
        connection.cancel()
        return
      }

      var updated = buffer
      if let data { updated.append(data) }
      if updated.count > 1_048_576 {
        self.respond(status: 413, body: #"{"error":"payload too large"}"#, on: connection)
        return
      }

      if let request = self.parseCompleteRequest(updated) {
        self.process(request, on: connection)
        return
      }

      if isComplete || error != nil {
        self.respond(status: 400, body: #"{"error":"invalid request"}"#, on: connection)
        return
      }

      self.receive(on: connection, buffer: updated)
    }
  }

  private struct Request {
    let method: String
    let path: String
    let body: Data
  }

  private func parseCompleteRequest(_ data: Data) -> Request? {
    let delimiter = Data("\r\n\r\n".utf8)
    guard let headerRange = data.range(of: delimiter),
      let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
    else {
      return nil
    }

    let lines = headerText.components(separatedBy: "\r\n")
    guard let requestLine = lines.first else { return nil }
    let requestParts = requestLine.split(separator: " ")
    guard requestParts.count >= 2 else { return nil }

    var contentLength = 0
    for line in lines.dropFirst() {
      let parts = line.split(separator: ":", maxSplits: 1)
      if parts.count == 2,
        parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length"
      {
        guard let length = Int(parts[1].trimmingCharacters(in: .whitespaces)),
          length >= 0, length <= 1_048_576 else { return nil }
        contentLength = length
      }
    }

    let bodyStart = headerRange.upperBound
    guard data.count >= bodyStart + contentLength else { return nil }
    let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
    return Request(method: String(requestParts[0]), path: String(requestParts[1]), body: body)
  }

  private func process(_ request: Request, on connection: NWConnection) {
    guard request.method == "POST", request.path == "/claude/finished" else {
      respond(status: 404, body: #"{"error":"not found"}"#, on: connection)
      return
    }

    do {
      let payload = try JSONDecoder().decode(HookPayload.self, from: request.body)
      onPayload?(payload)
      respond(status: 200, body: "{}", on: connection)
    } catch {
      respond(status: 400, body: #"{"error":"invalid JSON"}"#, on: connection)
    }
  }

  private func respond(status: Int, body: String, on connection: NWConnection) {
    let reason: String
    switch status {
    case 200: reason = "OK"
    case 400: reason = "Bad Request"
    case 404: reason = "Not Found"
    case 413: reason = "Payload Too Large"
    default: reason = "Error"
    }
    let bodyData = Data(body.utf8)
    let headers =
      "HTTP/1.1 \(status) \(reason)\r\n"
      + "Content-Type: application/json; charset=utf-8\r\n"
      + "Content-Length: \(bodyData.count)\r\n"
      + "Connection: close\r\n"
      + "\r\n"
    var response = Data(headers.utf8)
    response.append(bodyData)
    connection.send(
      content: response,
      completion: .contentProcessed { _ in
        connection.cancel()
      })
  }

  deinit {
    listener?.cancel()
  }
}
