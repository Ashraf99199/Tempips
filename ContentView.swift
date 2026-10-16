import SwiftUI

struct ContentView: View {
    @State private var vm = InboxViewModel()
    @State private var copied = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                addressSection

                Section("الرسائل") {
                    if vm.messages.isEmpty {
                        ContentUnavailableView("ما فيه رسائل",
                                               systemImage: "tray",
                                               description: Text("الرسائل الجديدة تظهر هنا تلقائياً"))
                    } else {
                        ForEach(vm.messages) { msg in
                            NavigationLink(value: msg) { MessageRow(message: msg) }
                        }
                        .onDelete { idx in
                            let toDelete = idx.map { vm.messages[$0] }
                            Task { for m in toDelete { await vm.delete(m) } }
                        }
                    }
                }

                // شرط استخدام mail.tm: ذكر المصدر
                Section {
                    Link("مدعوم من Mail.tm", destination: URL(string: "https://mail.tm")!)
                        .font(.footnote)
                }
            }
            .navigationTitle("إيميل مؤقت")
            .navigationDestination(for: MessageSummary.self) { msg in
                MessageDetailView(summary: msg, vm: vm)
            }
            .refreshable { await vm.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await vm.createNewAddress() }
                    } label: {
                        Label("إيميل جديد", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(vm.isLoading)
                }
            }
            .alert("صار خطأ", isPresented: .constant(vm.errorMessage != nil)) {
                Button("تمام") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .task { await vm.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await vm.start() } }
            else { vm.stopPolling() }
        }
    }

    private var addressSection: some View {
        Section {
            if let address = vm.address, !vm.isLoading {
                VStack(spacing: 12) {
                    Text(address)
                        .font(.system(.title3, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .environment(\.layoutDirection, .leftToRight)

                    Button {
                        UIPasteboard.general.string = address
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                    } label: {
                        Label(copied ? "تم النسخ" : "انسخ الإيميل",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                HStack { Spacer(); ProgressView("جاري تجهيز الإيميل…"); Spacer() }
                    .padding(.vertical, 20)
            }
        }
    }
}

struct MessageRow: View {
    let message: MessageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.from.display)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(message.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(message.subject.isEmpty ? "(بدون عنوان)" : message.subject)
                .font(.subheadline)
                .fontWeight(message.seen ? .regular : .semibold)
                .lineLimit(1)
            if let intro = message.intro, !intro.isEmpty {
                Text(intro)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview { ContentView() }
