import Foundation
import IssueTalkCore

private struct BrokerResult: Decodable {
  let accessToken: String
  let refreshToken: String?
  let expiresIn: Double?
  let tokenType: String
  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresIn = "expires_in"
    case tokenType = "token_type"
  }
}

actor GitHubSession {
  let credentials = CredentialStore()
  private let transport = URLSessionTransport()
  private var refresh: Task<OAuthTokens, Error>?
  private var current: OAuthTokens?
  private var loaded = false
  private var generation = 0

  static func configuration() throws -> OAuthConfiguration {
    let bundle = Bundle.main
    guard let client = bundle.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String,
      let value = bundle.object(forInfoDictionaryKey: "GitHubOAuthBrokerURL") as? String,
      let url = URL(string: value)
    else { throw OAuthError.invalidConfiguration }
    return try OAuthConfiguration(
      clientID: client, redirectURI: URL(string: "issuetalk://oauth/callback")!, broker: url)
  }

  func token() async throws -> String {
    if !loaded {
      let saved = try await credentials.load()
      if !loaded {
        current = saved
        loaded = true
      }
    }
    guard let tokens = current else { throw IssueTalkError.authenticationRequired }
    guard let expiry = tokens.expiresAt, expiry < Date.now.addingTimeInterval(60) else {
      return tokens.accessToken
    }
    guard let value = tokens.refreshToken else { throw IssueTalkError.authenticationRequired }
    let epoch = generation
    let task =
      refresh
      ?? Task { try await self.exchange(["grant_type": "refresh_token", "refresh_token": value]) }
    refresh = task
    defer { if epoch == generation { refresh = nil } }
    do {
      let updated = try await task.value
      guard epoch == generation else { throw IssueTalkError.authenticationRequired }
      current = updated
      try await credentials.save(updated)
      return updated.accessToken
    } catch {
      if epoch == generation {
        current = nil
        try? await credentials.clear()
      }
      throw IssueTalkError.authenticationRequired
    }
  }

  func authorize(code: String, verifier: String) async throws {
    let epoch = generation
    let tokens = try await exchange([
      "grant_type": "authorization_code", "code": code, "code_verifier": verifier,
    ])
    guard epoch == generation else { throw IssueTalkError.authenticationRequired }
    try await credentials.save(tokens)
    current = tokens
    loaded = true
  }

  private func exchange(_ body: [String: String]) async throws -> OAuthTokens {
    let configuration = try Self.configuration()
    var request = URLRequest(url: configuration.broker.appendingPathComponent("token"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)
    let response = try await transport.send(request)
    guard response.status == 200 else { throw OAuthError.authorizationFailed }
    let result = try JSONDecoder().decode(BrokerResult.self, from: response.data)
    guard !result.accessToken.isEmpty, result.tokenType.lowercased() == "bearer",
      result.expiresIn == nil || result.expiresIn! > 0
    else { throw OAuthError.authorizationFailed }
    return OAuthTokens(
      accessToken: result.accessToken, refreshToken: result.refreshToken,
      expiresAt: result.expiresIn.map { Date.now.addingTimeInterval($0) })
  }

  func logout() async throws {
    generation += 1
    current = nil
    loaded = true
    refresh?.cancel()
    refresh = nil
    try await credentials.clear()
  }
}
