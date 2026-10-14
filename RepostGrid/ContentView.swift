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

                    Text("Сканирование запрашивает список репостов через внутренний endpoint TikTok в авторизованной веб-сессии. Endpoint неофициальный и может перестать работать; снятие репоста пока выполняется вручную.")
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
    @State private var loginTrigger = 0
    @State private var profileTrigger = 0
    @State private var pageMessage = "Войдите в TikTok и откройте свой профиль. Сканирование запрашивает список репостов напрямую, без видимой вкладки репостов."
    let onScan: ([RepostItem]) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(pageMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                TikTokWebView(scanTrigger: $scanTrigger, loginTrigger: $loginTrigger, profileTrigger: $profileTrigger) { scanned, message in
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
                        loginTrigger += 1
                    } label: {
                        Label("Войти", systemImage: "person.crop.circle")
                    }
                    Button {
                        profileTrigger += 1
                    } label: {
                        Label("Профиль", systemImage: "person")
                    }
                    Button {
                        scanTrigger += 1
                    } label: {
                        Label("Сканировать", systemImage: "viewfinder")
                    }
                }
            }
        }
    }
}

struct TikTokWebView: UIViewRepresentable {
    @Binding var scanTrigger: Int
    @Binding var loginTrigger: Int
    @Binding var profileTrigger: Int
    let onScan: ([RepostItem], String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: URL(string: "https://www.tiktok.com/")!))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if loginTrigger != context.coordinator.lastLoginTrigger {
            context.coordinator.lastLoginTrigger = loginTrigger
            uiView.load(URLRequest(url: URL(string: "https://www.tiktok.com/login")!))
            return
        }
        if profileTrigger != context.coordinator.lastProfileTrigger {
            context.coordinator.lastProfileTrigger = profileTrigger
            uiView.evaluateJavaScript("""
              (() => {
                const candidates = Array.from(document.querySelectorAll('a,button,[role="button"]'));
                const profile = candidates.find(el => {
                  const label = ((el.innerText || '') + ' ' + (el.getAttribute('aria-label') || '')).trim();
                  const href = el.getAttribute('href') || '';
                  return /profile/i.test(label) || (href.startsWith('/@') && href.split('/').filter(Boolean).length === 1);
                });
                if (profile) { profile.click(); return 'profile-clicked'; }
                return 'profile-not-found';
              })()
            """) { result, error in
                DispatchQueue.main.async {
                    if error != nil || (result as? String) == "profile-not-found" {
                        self.onScan([], "Не удалось автоматически открыть профиль. Войдите в TikTok и нажмите на значок профиля вручную, затем откройте вкладку «Репосты».")
                    } else {
                        self.onScan([], "Открыл профиль. Теперь вручную выберите вкладку «Репосты» и нажмите «Сканировать».")
                    }
                }
            }
            return
        }
        guard scanTrigger != context.coordinator.lastScanTrigger else { return }
        context.coordinator.lastScanTrigger = scanTrigger

        let script = """
        (async () => {
          const fail = message => ({ ok: false, message, rows: [] });
          try {
            const path = window.location.pathname || '';
            const universal = window.__\$UNIVERSAL_DATA\$__;
            const scope = universal && universal.__DEFAULT_SCOPE__;
            const secUid = scope && scope['webapp.app-context'] && scope['webapp.app-context'].user && scope['webapp.app-context'].user.secUid;
            if (!path.startsWith('/@') || !secUid) {
              return fail('Сначала войдите в TikTok и откройте свой профиль. Не нужно открывать вкладку «Репосты»: список запрашивается напрямую у TikTok.');
            }
            const rows = [];
            const seen = new Set();
            let cursor = '0';
            let hasMore = true;
            let pages = 0;
            while (hasMore && pages < 20) {
              const params = new URLSearchParams({
                aid: '1988',
                count: '30',
                coverFormat: '2',
                cursor,
                needPinnedItemIds: 'true',
                post_item_list_request_type: '0',
                secUid
              });
              const response = await fetch('/api/repost/item_list/?' + params.toString(), {
                credentials: 'include',
                headers: { 'accept': 'application/json, text/plain, */*' }
              });
              if (response.status === 401 || response.status === 403 || response.status === 429) {
                return fail('TikTok отклонил запрос (' + response.status + '). Сканирование остановлено; проверьте вход и попробуйте позже.');
              }
              if (!response.ok) return fail('TikTok вернул ошибку HTTP ' + response.status + '.');
              const data = await response.json();
              if (data.status_code !== undefined && data.status_code !== 0) {
                return fail((data.status_msg || 'TikTok не разрешил получить список репостов.') + ' Код: ' + data.status_code);
              }
              const list = Array.isArray(data.itemList) ? data.itemList : [];
              for (const item of list) {
                const id = item && item.id ? String(item.id) : '';
                const author = item && item.author && item.author.uniqueId ? String(item.author.uniqueId) : '';
                if (!id || !author || seen.has(id)) continue;
                seen.add(id);
                rows.push({
                  url: 'https://www.tiktok.com/@' + author + '/video/' + id,
                  author: '@' + author,
                  caption: String(item.desc || 'Видео из репостов TikTok').replace(/\\s+/g, ' ').slice(0, 220),
                  thumbnail: (item.video && (item.video.cover || item.video.originCover)) || ''
                });
              }
              pages++;
              hasMore = Boolean(data.hasMore);
              const next = data.cursor == null ? cursor : String(data.cursor);
              if (!hasMore || next === cursor) break;
              cursor = next;
              if (hasMore) await new Promise(resolve => setTimeout(resolve, 1800));
            }
            return {
              ok: true,
              message: 'Получено ' + rows.length + ' репостов через запрос списка TikTok (' + pages + ' страниц).' +
                (hasMore ? ' Достигнут лимит одного сканирования; нажмите ещё раз позже, если список большой.' : ''),
              rows
            };
          } catch (error) {
            return fail('Не удалось запросить список репостов TikTok: ' + String(error && error.message || error));
          }
        })()
        """

        uiView.evaluateJavaScript(script) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.onScan([], "Не удалось прочитать страницу TikTok: \\(error.localizedDescription)")
                    return
                }
                let payload = result as? [String: Any] ?? [:]
                let rows = payload["rows"] as? [[String: Any]] ?? []
                if (payload["ok"] as? Bool) != true {
                    self.onScan([], payload["message"] as? String ?? "Не удалось определить вкладку репостов.")
                    return
                }
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
                    ? "На вкладке репостов не найдены ссылки на видео. Прокрутите страницу, чтобы загрузить карточки, и нажмите «Сканировать» ещё раз."
                    : "Сканирование вкладки репостов завершено: найдено видео — \\(items.count)."
                self.onScan(items, message)
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastScanTrigger = 0
        var lastLoginTrigger = 0
        var lastProfileTrigger = 0
        let onScan: ([RepostItem], String) -> Void

        init(onScan: @escaping ([RepostItem], String) -> Void) {
            self.onScan = onScan
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased() else {
                decisionHandler(.cancel)
                return
            }

            // Keep web-based TikTok login and navigation inside Repost Grid.
            if scheme == "https" || scheme == "http" {
                if navigationAction.targetFrame == nil {
                    webView.load(navigationAction.request)
                    decisionHandler(.cancel)
                } else {
                    decisionHandler(.allow)
                }
                return
            }

            // Do not launch TikTok/Safari or another app from a login deep link.
            decisionHandler(.cancel)
            DispatchQueue.main.async {
                self.onScan([], "Переход в другое приложение заблокирован, чтобы Repost Grid не сворачивался. На странице входа выберите вход по телефону, почте или доступным способом внутри TikTok — не нажимайте «Use TikTok app».")
            }
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
