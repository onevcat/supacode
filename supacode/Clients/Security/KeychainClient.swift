import ComposableArchitecture
import Foundation
import Security

struct KeychainClient: Sendable {
  var savePassword: @Sendable (_ password: String, _ key: String) async throws -> Void
  var loadPassword: @Sendable (_ key: String) async throws -> String?
  var deletePassword: @Sendable (_ key: String) async throws -> Void
}

extension KeychainClient: DependencyKey {
  static let liveValue = KeychainClient(
    savePassword: { password, key in
      let deleteStatus = SecItemDelete(keychainQuery(for: key) as CFDictionary)
      guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
        throw KeychainClientError(operation: .delete, status: deleteStatus)
      }

      var query = keychainQuery(for: key)
      query[kSecValueData as String] = Data(password.utf8)
      let status = SecItemAdd(query as CFDictionary, nil)
      guard status == errSecSuccess else {
        throw KeychainClientError(operation: .save, status: status)
      }
    },
    loadPassword: { key in
      var query = keychainQuery(for: key)
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne

      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      switch status {
      case errSecSuccess:
        guard let data = item as? Data else {
          throw KeychainClientError(operation: .load, status: errSecInternalError)
        }
        return String(data: data, encoding: .utf8)
      case errSecItemNotFound:
        return nil
      default:
        throw KeychainClientError(operation: .load, status: status)
      }
    },
    deletePassword: { key in
      let status = SecItemDelete(keychainQuery(for: key) as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw KeychainClientError(operation: .delete, status: status)
      }
    }
  )

  static let testValue = KeychainClient(
    savePassword: { _, _ in },
    loadPassword: { _ in nil },
    deletePassword: { _ in }
  )
}

extension DependencyValues {
  var keychainClient: KeychainClient {
    get { self[KeychainClient.self] }
    set { self[KeychainClient.self] = newValue }
  }
}

private nonisolated let keychainService = "com.onevcat.prowl.ssh"

private nonisolated func keychainQuery(for key: String) -> [String: Any] {
  [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: keychainService,
    kSecAttrAccount as String: key,
  ]
}

private nonisolated struct KeychainClientError: LocalizedError {
  enum Operation: String {
    case save
    case load
    case delete
  }

  let operation: Operation
  let status: OSStatus

  var errorDescription: String? {
    let statusMessage = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
    return "Keychain \(operation.rawValue) failed: \(statusMessage)"
  }
}
