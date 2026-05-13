import Foundation
import Combine

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func add(name: String, username: String, orgFilter: String, token: String) {
        guard accounts.count < 5 else { return }
        let account = Account(id: UUID(), name: name, username: username, orgFilter: orgFilter)
        KeychainHelper.save(key: account.keychainKey, value: token)
        accounts.append(account)
        save()
    }

    func update(account: Account, token: String?) {
        guard let idx = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[idx] = account
        if let token { KeychainHelper.save(key: account.keychainKey, value: token) }
        save()
    }

    func delete(account: Account) {
        KeychainHelper.delete(key: account.keychainKey)
        accounts.removeAll { $0.id == account.id }
        save()
    }

    func migrateIfNeeded() {
        guard defaults.data(forKey: "accounts") == nil else { return }
        guard let oldToken = KeychainHelper.load(key: "github_pat") else {
            save()
            return
        }
        let username = defaults.string(forKey: "github_username") ?? ""
        let orgFilter = defaults.string(forKey: "github_org_filter") ?? ""
        let account = Account(id: UUID(), name: "Account 1", username: username, orgFilter: orgFilter)
        KeychainHelper.save(key: account.keychainKey, value: oldToken)
        KeychainHelper.delete(key: "github_pat")
        defaults.removeObject(forKey: "github_username")
        defaults.removeObject(forKey: "github_org_filter")
        accounts = [account]
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: "accounts"),
              let decoded = try? JSONDecoder().decode([Account].self, from: data) else { return }
        accounts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: "accounts")
    }
}
