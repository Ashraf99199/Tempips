import Foundation
import Observation

/// يدير الإيميل الحالي والرسائل، ويحفظ الحساب عشان يرجع لك نفس الإيميل لما تفتح التطبيق.
@MainActor
@Observable
final class InboxViewModel {
    private(set) var address: String?
    private(set) var messages: [MessageSummary] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private var accountId: String?
    private var password: String?
    private var token: String?
    private var pollTask: Task<Void, Never>?
    private let api = MailTMClient.shared
    private let store = UserDefaults.standard

    init() {
        address   = store.string(forKey: "address")
        accountId = store.string(forKey: "accountId")
        password  = store.string(forKey: "password")
    }

    // MARK: - Lifecycle

    func start() async {
        if address == nil {
            await createNewAddress()
        } else {
            await login()
        }
        startPolling()
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: - Actions

    func createNewAddress() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // احذف الحساب القديم (لو موجود) عشان ما نخلي حسابات معلقة
            if let id = accountId, let token {
                try? await api.deleteAccount(id: id, token: token)
            }

            guard let domain = try await api.domains().first?.domain else {
                throw MailTMError.noDomains
            }
            let newAddress = "\(Self.randomString(10))@\(domain)"
            let newPassword = Self.randomString(16)

            let account = try await api.createAccount(address: newAddress, password: newPassword)
            let newToken = try await api.token(address: newAddress, password: newPassword)

            address = account.address
            accountId = account.id
            password = newPassword
            token = newToken
            messages = []

            store.set(address, forKey: "address")
            store.set(accountId, forKey: "accountId")
            store.set(password, forKey: "password")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard let token else { return }
        do {
            messages = try await api.messages(token: token)
        } catch MailTMError.http(401, _) {
            await login()
        } catch {
            // نتجاهل أخطاء التحديث التلقائي المؤقتة
        }
    }

    func loadMessage(_ id: String) async throws -> MessageDetail {
        guard let token else { throw MailTMError.http(401, "غير مسجل") }
        return try await api.message(id: id, token: token)
    }

    func delete(_ message: MessageSummary) async {
        guard let token else { return }
        messages.removeAll { $0.id == message.id }
        try? await api.deleteMessage(id: message.id, token: token)
    }

    // MARK: - Helpers

    private func login() async {
        guard let address, let password else { return await createNewAddress() }
        do {
            token = try await api.token(address: address, password: password)
        } catch {
            // الحساب انحذف من عندهم؟ نسوي واحد جديد
            await createNewAddress()
        }
    }

    private static func randomString(_ length: Int) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}
