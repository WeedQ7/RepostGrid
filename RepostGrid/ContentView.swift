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
    @Published var items: [RepostItem] = []
    @Published var showTikTok = false
    @Published var selectedItem: RepostItem?
    @Published var showConfirmRemoved = false
    @Published var notice: String?

    private let storageKey = "repostgrid.items.v2"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([RepostItem].self, from: data) {
            items = saved
        }
    }

    var removedCount: Int { items.filter { $0.status == .removed }.count }
    var remainingCount: Int { items.filter { $0.status == .pending }.count }

    func openTikTok(for item: RepostItem? = nil) {
        selectedItem = item
        showTikTok = true
    }

    func replaceWithScannedItems(_ scanned: [RepostItem]) {
        var seen = Set<String>()
        items = scanned.filter { seen.insert($0.videoURL).inserted }
        persist()
        if items.isEmpty {
            notice = "На этой странице не удалось найти ссылки на видео. Убедитесь, что открыта вкладка репостов вашего профиля, прокрутите страницу и попробуйте снова."
        } else {
            notice = "Найдено видео: \\(items.count). Проверьте карточки: TikTok может показывать не все репосты сразу."
        }
    }

    func confirmRemoved(_ item: RepostItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].status = .removed
        persist()
    }

    func clearItems() {
        items = []
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
            ScrollView(.vertical, showsIndicators: true) {
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
                        EmptyStateView()
                    }

                    Text("Сканирование читает ссылки, доступные на открытой странице TikTok. Если видео не появились, откройте вкладку репостов профиля и попробуйте снова. Снятие репоста пока выполняется вручную в TikTok.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color(red: 0.055, green: 0.06, blue: 0.08))
            .navigationBarHidden(true)
            .sheet(isPresented: $store.showTikTok) {
                TikTokWebSheet { scanned in
                    store.replaceWithScannedItems(scanned)
                }
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
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            store.clearItems()
                        } label: {
                            Label("Очистить список", systemImage: "trash")
                        }
                        Button {
                            showInfo = true
                        } label: {
                            Label("О приложении", systemImage: "info.circle")
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

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Пока пусто")
                .font(.headline)
            Text("Откройте TikTok и проверьте свои репосты.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
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
    @State private var scanTrigger = 0
    @State private var pageMessage = "Войдите в TikTok, откройте свой профиль и вкладку репостов, затем нажмите «Сканировать»."
    let onScan: ([RepostItem]) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(pageMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                TikTokWebView(scanTrigger: $scanTrigger) { scanned, message in
                    pageMessage = message
                    if !scanned.isEmpty {
                        onScan(scanned)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("TikTok")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        scanTrigger += 1
                    } label: {
                        Label("Сканировать", systemImage: "viewfinder")
                    }
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
    @Binding var scanTrigger: Int
    let onScan: ([RepostItem], String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: URL(string: "https://www.tiktok.com/")!))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard scanTrigger != context.coordinator.lastScanTrigger else { return }
        context.coordinator.lastScanTrigger = scanTrigger

        let script = """
        (() => {
          const links = Array.from(document.querySelectorAll('a[href*="/video/"]'));
          const seen = new Set();
          const results = [];
          for (const link of links) {
            let href = link.href || '';
            if (!href || !href.includes('/video/')) continue;
            try {
              const u = new URL(href);
              href = u.origin + u.pathname;
            } catch (_) {}
            if (seen.has(href)) continue;
            seen.add(href);
            let card = link;
            for (let i = 0; i < 5 && card.parentElement; i++) {
              if ((card.innerText || '').trim().length > 20) card = card.parentElement;
            }
            const text = (card.innerText || link.innerText || link.getAttribute('aria-label') || '').trim();
            const authorLink = card.querySelector('a[href*="/@"]');
            const author = authorLink ? (authorLink.innerText || authorLink.getAttribute('href') || '').trim() : '';
            results.push({
              url: href,
              author: author.startsWith('@') ? author : (author.match(/@[^/\\s]+/) || ['Автор TikTok'])[0],
              caption: text.replace(/\\s+/g, ' ').slice(0, 220) || 'Видео из открытой страницы TikTok'
            });
          }
          return results;
        })()
        """

        uiView.evaluateJavaScript(script) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.onScan([], "Не удалось прочитать страницу TikTok: \\(error.localizedDescription)")
                    return
                }
                let rows = result as? [[String: Any]] ?? []
                let items = rows.compactMap { row -> RepostItem? in
                    guard let url = row["url"] as? String,
                          url.contains("/video/") else { return nil }
                    return RepostItem(
                        author: row["author"] as? String ?? "Автор TikTok",
                        caption: row["caption"] as? String ?? "Видео из TikTok",
                        videoURL: url
                    )
                }
                let message = items.isEmpty
                    ? "Не найдено ссылок на видео. Откройте вкладку репостов профиля, прокрутите её, чтобы загрузить карточки, и нажмите «Сканировать» ещё раз."
                    : "Сканирование завершено: найдено видео — \\(items.count)."
                self.onScan(items, message)
            }
        }
    }

    final class Coordinator {
        var lastScanTrigger = 0
        let onScan: ([RepostItem], String) -> Void

        init(onScan: @escaping ([RepostItem], String) -> Void) {
            self.onScan = onScan
        }
    }
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
                    Text("Сканирование пытается собрать ссылки на видео из текущей страницы TikTok и может пропустить часть карточек. Вход внутри приложения может быть отдельным от приложения TikTok. Снятие репоста пока нужно выполнить вручную.")
                    Text("Не вводите пароль TikTok в сторонние формы. Авторизуйтесь только на официальном домене tiktok.com.")
                }
            }
            .navigationTitle("О приложении")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
