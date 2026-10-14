import SwiftUI
import WebKit
import UIKit

struct RepostItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var author: String
    var caption: String
    var videoURL: String
    var status: Status = .pending

    enum Status: String, Codable {
        case pending, removed
    }
}

@MainActor
final class RepostStore: ObservableObject {
    @Published var items: [RepostItem] = [
        .init(author: "@example_creator", caption: "Пример репоста — замените после подключения источника данных", videoURL: "https://www.tiktok.com/"),
        .init(author: "@video_author", caption: "Демо-карточка. Это не реальный репост", videoURL: "https://www.tiktok.com/"),
        .init(author: "@creator_three", caption: "Здесь будут отображаться найденные репосты", videoURL: "https://www.tiktok.com/")
    ]
    @Published var showTikTok = false
    @Published var selectedItem: RepostItem?
    @Published var showConfirmRemoved = false
    @Published var notice: String?

    private let storageKey = "repostgrid.items.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([RepostItem].self, from: data),
           !saved.isEmpty {
            items = saved
        }
    }

    var removedCount: Int { items.filter { $0.status == .removed }.count }
    var remainingCount: Int { items.filter { $0.status == .pending }.count }

    func openTikTok(for item: RepostItem? = nil) {
        selectedItem = item
        showTikTok = true
    }

    func confirmRemoved(_ item: RepostItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].status = .removed
        persist()
    }

    func resetDemo() {
        items = [
            .init(author: "@example_creator", caption: "Демо-карточка — не реальный репост", videoURL: "https://www.tiktok.com/"),
            .init(author: "@video_author", caption: "Демо-карточка — не реальный репост", videoURL: "https://www.tiktok.com/"),
            .init(author: "@creator_three", caption: "Демо-карточка — не реальный репост", videoURL: "https://www.tiktok.com/")
        ]
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

struct ContentView: View {
    @StateObject private var store = RepostStore()
    @State private var showInfo = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    stats
                    HStack {
                        Text("Мои репосты")
                            .font(.title2.bold())
                        Spacer()
                        Button {
                            store.openTikTok()
                        } label: {
                            Label("TikTok", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.items) { item in
                            RepostCard(item: item) {
                                store.openTikTok(for: item)
                            } markRemoved: {
                                store.selectedItem = item
                                store.showConfirmRemoved = true
                            }
                        }
                    }

                    if store.items.isEmpty {
                        ContentUnavailableView("Пока пусто", systemImage: "square.grid.2x2",
                                               description: Text("Откройте TikTok и проверьте свои репосты."))
                    }

                    Text("Карточки сейчас демонстрационные. Приложение не получает реальные репосты и не удаляет их автоматически: у TikTok нет публичного API для этой операции.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color(red: 0.055, green: 0.06, blue: 0.08))
            .navigationBarHidden(true)
            .sheet(isPresented: $store.showTikTok) {
                TikTokWebSheet()
            }
            .confirmationDialog(
                "Подтвердить результат",
                isPresented: $store.showConfirmRemoved,
                titleVisibility: .visible
            ) {
                Button("Я снял(а) репост — отметить удалённым") {
                    if let item = store.selectedItem {
                        store.confirmRemoved(item)
                    }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Сначала снимите репост в TikTok. Счётчик изменится только после вашего подтверждения.")
            }
            .alert("Repost Grid", isPresented: Binding(
                get: { store.notice != nil },
                set: { if !$0 { store.notice = nil } }
            )) {
                Button("OK", role: .cancel) { store.notice = nil }
            } message: {
                Text(store.notice ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Сбросить демо-данные", systemImage: "arrow.counterclockwise") {
                            store.resetDemo()
                        }
                        Button("О приложении", systemImage: "info.circle") {
                            showInfo = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .tint(.white)
                }
            }
            .sheet(isPresented: $showInfo) {
                InfoView()
                    .presentationDetents([.medium])
            }
        }
        .tint(Color(red: 0.35, green: 0.85, blue: 0.78))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.2.squarepath")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(red: 0.35, green: 0.85, blue: 0.78))
                Text("Repost Grid")
                    .font(.largeTitle.bold())
            }
            Text("Управление репостами TikTok")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var stats: some View {
        HStack(spacing: 10) {
            StatCard(title: "Всего", value: "\(store.items.count)", symbol: "square.grid.2x2")
            StatCard(title: "Удалено", value: "\(store.removedCount)", symbol: "checkmark.circle")
            StatCard(title: "Осталось", value: "\(store.remainingCount)", symbol: "clock")
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Color(red: 0.35, green: 0.85, blue: 0.78))
            Text(value)
                .font(.title.bold().monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct RepostCard: View {
    let item: RepostItem
    let open: () -> Void
    let markRemoved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Color.purple.opacity(0.55), Color.cyan.opacity(0.25)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: item.status == .removed ? "checkmark.circle.fill" : "play.rectangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.9))
                if item.status == .removed {
                    Text("ОТМЕЧЕНО")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.6))
                        .clipShape(Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(8)
                }
            }
            .frame(height: 130)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)

            Text(item.author)
                .font(.subheadline.bold())
                .lineLimit(1)
            Text(item.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(height: 45, alignment: .topLeading)

            Button(action: open) {
                Label("Открыть TikTok", systemImage: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if item.status == .pending {
                Button(action: markRemoved) {
                    Label("Отметить удалённым", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Учтено в статистике")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct TikTokWebSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TikTokWebView(url: URL(string: "https://www.tiktok.com/")!)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("TikTok")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Закрыть") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            UIApplication.shared.open(URL(string: "https://www.tiktok.com/")!)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .accessibilityLabel("Открыть в Safari")
                    }
                }
        }
    }
}

struct TikTokWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct InfoView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Что работает в этой сборке") {
                    Label("Нативная сетка карточек", systemImage: "square.grid.2x2")
                    Label("Счётчик и сохранение отметок", systemImage: "chart.bar")
                    Label("Открытие TikTok внутри приложения", systemImage: "safari")
                }
                Section("Ограничения") {
                    Text("Данные в сетке демонстрационные. Вход в WKWebView может быть отдельным от приложения TikTok. Удаление нужно выполнить в TikTok вручную и подтвердить в Repost Grid.")
                    Text("Не вводите пароль TikTok в сторонние формы. Авторизуйтесь только на официальном домене tiktok.com.")
                }
            }
            .navigationTitle("О приложении")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
