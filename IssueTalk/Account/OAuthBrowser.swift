import AuthenticationServices
import CryptoKit
import Foundation
import IssueTalkCore
import UIKit

@MainActor
final class OAuthBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
  private var session: ASWebAuthenticationSession?

  func signIn(using account: GitHubSession) async throws {
    guard session == nil else { throw OAuthError.authorizationFailed }
    let configuration = try GitHubSession.configuration()
    let verifier = Self.randomValue()
    let state = Self.randomValue()
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    defer { session = nil }
    let callback: URL = try await withCheckedThrowingContinuation { continuation in
      let session = ASWebAuthenticationSession(
        url: configuration.authorizationURL(state: state, challenge: challenge),
        callbackURLScheme: "issuetalk"
      ) { url, _ in
        if let url {
          continuation.resume(returning: url)
        } else {
          continuation.resume(throwing: OAuthError.authorizationFailed)
        }
      }
      session.presentationContextProvider = self
      session.prefersEphemeralWebBrowserSession = true
      self.session = session
      if !session.start() {
        self.session = nil
        continuation.resume(throwing: OAuthError.authorizationFailed)
      }
    }
    let code = try configuration.code(from: callback, expectedState: state)
    try await account.authorize(code: code, verifier: verifier)
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
  }

  private static func randomValue() -> String {
    let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
    return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }
}
