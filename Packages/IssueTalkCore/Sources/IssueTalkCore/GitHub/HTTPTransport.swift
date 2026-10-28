import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public struct HTTPResponse: Sendable {
  public let status: Int
  public let headers: [String: String]
  public let data: Data

  public init(status: Int, headers: [String: String] = [:], data: Data = Data()) {
    self.status = status
    self.headers = Dictionary(
      headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
    self.data = data
  }
}

public protocol HTTPTransport: Sendable {
  func send(_ request: URLRequest) async throws -> HTTPResponse
}

/// Tokens and authorization codes must never follow a redirect to another origin.
private final class RejectRedirects: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

public struct URLSessionTransport: HTTPTransport {
  private let session: URLSession

  public init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 30
    session = URLSession(
      configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
  }

  public func send(_ request: URLRequest) async throws -> HTTPResponse {
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw IssueTalkError.invalidResponse }
    let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
      result[String(describing: field.key)] = String(describing: field.value)
    }
    return HTTPResponse(status: response.statusCode, headers: headers, data: data)
  }
}
