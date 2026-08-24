import SwiftUI

// MARK: - WhatsApp Main View
struct WhatsAppView: View {
    @ObservedObject private var vm = WhatsAppViewModel.shared
    @State private var selectedChat: WAChatItem?

    var body: some View {
        NavigationSplitView {
            mainList
                .navigationTitle("WhatsApp")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if vm.isLoading {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Button { Task { await vm.fetchPending() } } label: {
                                Image(systemName: "arrow.clockwise").foregroundColor(.ncSage)
                            }
                        }
                    }
                }
                .refreshable { await vm.fetchPending() }
        } detail: {
            if let chat = selectedChat {
                WhatsAppChatDetailView(chat: chat)
            } else {
                Text("Chat auswahlen").foregroundColor(.ncMuted)
            }
        }
        .warmBackground()
        .task {
            vm.startAutoRefresh()
            await vm.fetchPending()
            await vm.fetchStatus()
        }
        .onDisappear { vm.stopAutoRefresh() }
    }

    @ViewBuilder
    private var mainList: some View {
        if let err = vm.lastError, vm.pendingBusiness.isEmpty, vm.pendingPrivat.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundColor(.ncRed)
                Text("WhatsApp nicht verbunden").font(.headline).foregroundColor(.ncDark)
                Text(err).font(.subheadline).foregroundColor(.ncMuted).multilineTextAlignment(.center)
                Button("Erneut versuchen") {
                    Task { await vm.fetchPending() }
                }
                .buttonStyle(.bordered).tint(.ncGreen)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                if vm.allDone {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").font(.title).foregroundColor(.ncGreen)
                        Text("Alles erledigt").font(.headline).foregroundColor(.ncDark)
                        Text("Keine unbeantworteten Nachrichten.").font(.subheadline).foregroundColor(.ncMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                // Business section
                if !vm.pendingBusiness.isEmpty {
                    Section {
                        let unrepliedBusiness = vm.pendingBusiness.filter { !$0.replied }
                        let sortedBusiness = unrepliedBusiness.sorted { $0.lastIncomingTs < $1.lastIncomingTs }
                        ForEach(sortedBusiness) { chat in
                            let item = WAChatItem(
                                remoteJid: chat.remoteJid ?? chat.id,
                                contact: chat.contact,
                                lastIncomingTs: chat.lastIncomingTs,
                                lastIncomingText: chat.lastIncomingText,
                                replied: chat.replied,
                                session: "business"
                            )
                            NavigationLink(value: item) {
                                ChatRowView(chat: item)
                            }
                        }
                    } header: {
                        Label("Geschaftlich", systemImage: "briefcase.fill")
                            .font(.headline).foregroundColor(.ncDark)
                    }
                }

                // Privat section
                if !vm.pendingPrivat.isEmpty {
                    Section {
                        let unrepliedPrivat = vm.pendingPrivat.filter { !$0.replied }
                        let sortedPrivat = unrepliedPrivat.sorted { $0.lastIncomingTs < $1.lastIncomingTs }
                        ForEach(sortedPrivat) { chat in
                            let item = WAChatItem(
                                remoteJid: chat.remoteJid ?? chat.id,
                                contact: chat.contact,
                                lastIncomingTs: chat.lastIncomingTs,
                                lastIncomingText: chat.lastIncomingText,
                                replied: chat.replied,
                                session: "privat"
                            )
                            NavigationLink(value: item) {
                                ChatRowView(chat: item)
                            }
                        }
                    } header: {
                        Label("Privat", systemImage: "person.fill")
                            .font(.headline).foregroundColor(.ncDark)
                    }
                }

                if vm.isLoading {
                    ForEach(0..<3) { _ in
                        ChatRowPlaceholder()
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationDestination(for: WAChatItem.self) { chat in
                WhatsAppChatDetailView(chat: chat)
            }
        }
    }
}

// MARK: - Chat Row
struct ChatRowView: View {
    let chat: WAChatItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.ncGreen.opacity(0.15)).frame(width: 44, height: 44)
                Text(initials).font(.system(size: 14, weight: .semibold)).foregroundColor(.ncGreen)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(chat.contact).font(.subheadline.weight(.semibold)).foregroundColor(.ncDark).lineLimit(1)
                    Spacer()
                    HStack(spacing: 4) {
                        if chat.urgency == .red {
                            Circle().fill(Color.ncRed).frame(width: 8, height: 8)
                        } else if chat.urgency == .yellow {
                            Circle().fill(Color.ncGold).frame(width: 8, height: 8)
                        }
                        Text(chat.timeAgo).font(.caption2).foregroundColor(.ncMuted)
                    }
                }
                if let text = chat.lastIncomingText {
                    Text(text)
                        .font(.caption).foregroundColor(.ncMuted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var initials: String {
        let words = chat.contact.split(separator: " ")
        let parts = words.prefix(2).map { String($0.prefix(1)) }
        return parts.joined()
    }
}

// MARK: - Placeholder (shimmer)
struct ChatRowPlaceholder: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Color.ncSand.opacity(0.3)).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color.ncSand.opacity(0.3)).frame(width: 120, height: 12)
                RoundedRectangle(cornerRadius: 4).fill(Color.ncSand.opacity(0.2)).frame(width: 200, height: 10)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Chat Detail View
struct WhatsAppChatDetailView: View {
    let chat: WAChatItem
    @ObservedObject private var vm = WhatsAppViewModel.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(Color.ncGreen.opacity(0.15)).frame(width: 56, height: 56)
                        Text(initials).font(.title3.weight(.semibold)).foregroundColor(.ncGreen)
                    }
                    Text(chat.contact).font(.headline).foregroundColor(.ncDark)
                    Text(chat.session == "business" ? "Geschaftlich" : "Privat")
                        .font(.caption).foregroundColor(.ncMuted)
                }
                .padding(.vertical, 16)

                Divider().padding(.horizontal, 16)

                // Messages
                let msgs = vm.getMessages(session: chat.session, remoteJid: chat.remoteJid)
                if msgs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right").font(.title).foregroundColor(.ncSand)
                        Text("Nachrichten werden geladen...").font(.subheadline).foregroundColor(.ncMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(msgs) { msg in
                            MessageBubble(message: msg)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .warmBackground()
        .navigationTitle(chat.contact)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.fetchMessages(session: chat.session, for: chat.remoteJid)
        }
    }

    private var initials: String {
        let words = chat.contact.split(separator: " ")
        let parts = words.prefix(2).map { String($0.prefix(1)) }
        return parts.joined()
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: WAMessage

    var body: some View {
        HStack {
            if message.outgoing { Spacer() }

            VStack(alignment: message.outgoing ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundColor(message.outgoing ? .white : .ncDark)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        message.outgoing
                            ? Color.ncGreen
                            : Color.white.opacity(0.7)
                    )
                    .cornerRadius(12)

                Text(message.formattedTime)
                    .font(.caption2)
                    .foregroundColor(.ncMuted)
                    .padding(.horizontal, 4)
            }

            if !message.outgoing { Spacer() }
        }
        .padding(.vertical, 2)
    }
}