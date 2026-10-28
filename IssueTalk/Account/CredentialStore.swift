import Foundation
import IssueTalkCore
import Security

actor CredentialStore {
  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Bundle.main.bundleIdentifier ?? "IssueTalk",
      kSecAttrAccount as String: "github-oauth",
    ]
  }

  func load() throws -> OAuthTokens? {
    var lookup = query
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw OAuthError.authorizationFailed
    }
    return try JSONDecoder().decode(OAuthTokens.self, from: data)
  }

  func save(_ tokens: OAuthTokens) throws {
    let data = try JSONEncoder().encode(tokens)
    let update: [String: Any] = [kSecValueData as String: data]
    let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      var item = query
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
        throw OAuthError.authorizationFailed
      }
    } else if status != errSecSuccess {
      throw OAuthError.authorizationFailed
    }
  }

  func clear() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw OAuthError.authorizationFailed
    }
  }
}
