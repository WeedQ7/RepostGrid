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
    @Published var pendingRemoval: RepostItem?
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

    func requestRemoval(_ item: RepostItem) {
        selectedItem = item
        pendingRemoval = item
        showTikTok = true
    }

    func confirmRemoved(_ item: RepostItem, verified: Bool, message: String) {
        if verified, let index = items.firstIndex(where: { $0.videoURL == item.videoURL }) {
            items[index].status = .removed
            persist()
        }
        pendingRemoval = nil
        notice = message
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
                            } removeRepost: {
                                store.requestRemoval(item)
                            }
                        }
                    }

                    if store.items.isEmpty {
                        EmptyStateView()
                    }

                    Text("Список и снятие репостов запрашиваются через веб-сессию TikTok внутри приложения. Используются неофициальные endpoints: TikTok может изменить их или заблокировать запросы. Счётчик меняется только после проверки, что репост исчез из списка.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color(red: 0.055, green: 0.06, blue: 0.08))
            .navigationBarHidden(true)
            .sheet(isPresented: $store.showTikTok) {
                TikTokWebSheet(deleteTarget: store.pendingRemoval, onScan: { scanned in
                    store.replaceWithScannedItems(scanned)
                }, onRemove: { item, verified, message in
                    store.confirmRemoved(item, verified: verified, message: message)
                    if verified { store.showTikTok = false }
                })
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
    let removeRepost: () -> Void

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
                Button(action: removeRepost) {
                    Label("Снять репост", systemImage: "arrow.uturn.backward")
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
    @State private var removeTrigger = 0
    @State private var pageMessage = "Войдите в TikTok один раз. Затем список и снятие репостов выполняются запросами внутри этой сессии."
    let deleteTarget: RepostItem?
    let onScan: ([RepostItem]) -> Void
    let onRemove: (RepostItem, Bool, String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(pageMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                TikTokWebView(scanTrigger: $scanTrigger, loginTrigger: $loginTrigger, profileTrigger: $profileTrigger, removeTrigger: $removeTrigger, removeTargetURL: deleteTarget?.videoURL ?? "") { scanned, message in
                    pageMessage = message
                    if !scanned.isEmpty {
                        onScan(scanned)
                    }
                } onRemove: { verified, message in
                    pageMessage = message
                    if let deleteTarget {
                        onRemove(deleteTarget, verified, message)
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                if deleteTarget != nil { removeTrigger += 1 }
            }
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
                        Label("Найти репосты", systemImage: "viewfinder")
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
    @Binding var removeTrigger: Int
    let removeTargetURL: String
    let onScan: ([RepostItem], String) -> Void
    let onRemove: (Bool, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onRemove: onRemove)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "repostGridScanResult")
        contentController.add(context.coordinator, name: "repostGridRemoveResult")
        configuration.userContentController = contentController
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
                        self.onScan([], "Не удалось открыть профиль автоматически. Для поиска не требуется открывать вкладку «Репосты» — попробуйте нажать «Найти репосты».")
                    } else {
                        self.onScan([], "Профиль открыт. Нажмите «Найти репосты» — приложение запросит список напрямую.")
                    }
                }
            }
            return
        }
        if removeTrigger != context.coordinator.lastRemoveTrigger {
            context.coordinator.lastRemoveTrigger = removeTrigger
            context.coordinator.queueRemoval(removeTargetURL, in: uiView)
            return
        }
        guard scanTrigger != context.coordinator.lastScanTrigger else { return }
        context.coordinator.lastScanTrigger = scanTrigger

        let script = """
        (async () => {
          const fail = message => ({ ok: false, message, rows: [] });
          try {
            const universal = window.__$UNIVERSAL_DATA$__ || window.__UNIVERSAL_DATA_FOR_REHYDRATION__;
            const scope = universal && universal.__DEFAULT_SCOPE__;
            const user = scope && scope['webapp.app-context'] && scope['webapp.app-context'].user;
            let secUid = user && (user.secUid || user.sec_uid || user.secUserId);
            if (!secUid) {
              try {
                const authResponse = await fetch('/passport/web/account/info/?aid=1988&app_language=en&app_name=tiktok_web', { credentials: 'include' });
                const authPayload = await authResponse.json();
                secUid = authPayload && authPayload.data && (authPayload.data.sec_user_id || authPayload.data.sec_user_id_str);
              } catch (_) {}
            }
            if (!secUid) {
              return fail('Не удалось определить авторизованный аккаунт TikTok. Войдите через официальную страницу tiktok.com внутри Repost Grid и повторите попытку.');
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
        .then(result => window.webkit.messageHandlers.repostGridScanResult.postMessage(result))
        .catch(error => window.webkit.messageHandlers.repostGridScanResult.postMessage({
          ok: false,
          message: 'Ошибка JavaScript при поиске: ' + String(error && error.message || error),
          rows: []
        }))
        """

        uiView.evaluateJavaScript(script) { _, error in
            if let error {
                DispatchQueue.main.async {
                    self.onScan([], "Не удалось запустить поиск TikTok: \\(error.localizedDescription)")
                }
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastScanTrigger = 0
        var lastLoginTrigger = 0
        var lastProfileTrigger = 0
        var lastRemoveTrigger = 0
        private var pendingRemovalURL: String?
        private var pageReady = false
        let onScan: ([RepostItem], String) -> Void
        let onRemove: (Bool, String) -> Void

        init(onScan: @escaping ([RepostItem], String) -> Void, onRemove: @escaping (Bool, String) -> Void) {
            self.onScan = onScan
            self.onRemove = onRemove
        }

        func queueRemoval(_ url: String, in webView: WKWebView) {
            guard !url.isEmpty else {
                onRemove(false, "Не удалось определить ID видео для снятия репоста.")
                return
            }
            pendingRemovalURL = url
            if pageReady && !webView.isLoading {
                performPendingRemoval(in: webView)
            } else {
                onScan([], "Подключаюсь к TikTok и проверяю авторизацию перед снятием репоста…")
            }
        }

        private func performPendingRemoval(in webView: WKWebView) {
            guard let targetURL = pendingRemovalURL else { return }
            pendingRemovalURL = nil
            let script = """
            (async () => {
              const fail = message => ({ ok: false, message });
              try {
                const target = new URL(\(String(reflecting: targetURL)));
                const match = target.pathname.match(/\\/video\\/(\\d+)/);
                if (!match) return fail('Не удалось извлечь ID видео из ссылки.');
                const itemID = match[1];
                const universal = window.__$UNIVERSAL_DATA$__ || window.__UNIVERSAL_DATA_FOR_REHYDRATION__;
                const scope = universal && universal.__DEFAULT_SCOPE__;
                const user = scope && scope['webapp.app-context'] && scope['webapp.app-context'].user;
                let secUid = user && (user.secUid || user.sec_uid || user.secUserId);
                const response = await fetch('/tiktok/v1/upvote/delete?aid=1988&item_id=' + encodeURIComponent(itemID), {
                  method: 'POST',
                  credentials: 'include',
                  headers: {
                    'accept': 'application/json, text/plain, */*',
                    'content-type': 'application/x-www-form-urlencoded',
                    'x-secsdk-csrf-request': '1'
                  },
                  body: ''
                });
                const raw = await response.text();
                if (!response.ok) return fail('TikTok отклонил снятие репоста: HTTP ' + response.status + '.');
                let result;
                try { result = JSON.parse(raw); } catch (_) { return fail('TikTok не вернул проверяемый JSON-ответ. Репост не отмечен удалённым.'); }
                if (result.status_code !== 0 && result.statusCode !== 0 && result.message !== 'success') {
                  return fail('TikTok не подтвердил снятие репоста: ' + (result.status_msg || result.message || 'неизвестный ответ'));
                }
                if (!secUid) {
                  try {
                    const authResponse = await fetch('/passport/web/account/info/?aid=1988&app_language=en&app_name=tiktok_web', { credentials: 'include' });
                    const authPayload = await authResponse.json();
                    secUid = authPayload && authPayload.data && (authPayload.data.sec_user_id || authPayload.data.sec_user_id_str);
                  } catch (_) {}
                }
                if (!secUid) return fail('TikTok ответил на запрос, но приложение не смогло проверить список репостов. Статус не изменён.');
                let cursor = '0', hasMore = true, pages = 0, stillPresent = false;
                while (hasMore && pages < 20) {
                  const params = new URLSearchParams({ aid:'1988', count:'30', coverFormat:'2', cursor, needPinnedItemIds:'true', post_item_list_request_type:'0', secUid });
                  const check = await fetch('/api/repost/item_list/?' + params.toString(), { credentials:'include', headers:{'accept':'application/json, text/plain, */*'} });
                  if (!check.ok) return fail('Запрос на снятие отправлен, но проверка списка завершилась HTTP ' + check.status + '. Статус не изменён.');
                  const page = await check.json();
                  if (page.status_code !== undefined && page.status_code !== 0) return fail('Запрос отправлен, но TikTok не дал проверить список репостов. Статус не изменён.');
                  const list = Array.isArray(page.itemList) ? page.itemList : [];
                  if (list.some(item => String(item && item.id || '') === itemID)) { stillPresent = true; break; }
                  pages++;
                  const next = page.cursor == null ? cursor : String(page.cursor);
                  hasMore = Boolean(page.hasMore) && next !== cursor;
                  cursor = next;
                }
                if (stillPresent) return fail('TikTok пока всё ещё возвращает этот репост. Он не отмечен удалённым.');
                if (hasMore) return fail('Не удалось проверить весь список репостов за один проход. Статус не изменён.');
                return { ok:true, message:'Репост снят и проверен: видео больше нет в списке репостов TikTok.' };
              } catch (error) {
                return fail('Ошибка запроса TikTok: ' + String(error && error.message || error));
              }
            })()
            """;
            let bridgedScript = script + """
            .then(result => window.webkit.messageHandlers.repostGridRemoveResult.postMessage(result))
            .catch(error => window.webkit.messageHandlers.repostGridRemoveResult.postMessage({
              ok: false,
              message: 'Ошибка JavaScript при снятии репоста: ' + String(error && error.message || error)
            }))
            """
            webView.evaluateJavaScript(bridgedScript) { _, error in
                if let error {
                    DispatchQueue.main.async {
                        self.onRemove(false, "Не удалось запустить запрос снятия репоста: \\(error.localizedDescription)")
                    }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let payload = message.body as? [String: Any] else { return }
            DispatchQueue.main.async {
                if message.name == "repostGridScanResult" {
                    let rows = payload["rows"] as? [[String: Any]] ?? []
                    guard (payload["ok"] as? Bool) == true else {
                        self.onScan([], payload["message"] as? String ?? "TikTok не вернул список репостов.")
                        return
                    }
                    let items = rows.compactMap { row -> RepostItem? in
                        guard let url = row["url"] as? String, url.contains("/video/") else { return nil }
                        return RepostItem(
                            author: row["author"] as? String ?? "Автор TikTok",
                            caption: row["caption"] as? String ?? "Видео из TikTok",
                            videoURL: url
                        )
                    }
                    self.onScan(items, payload["message"] as? String ?? "Получено репостов: \\(items.count).")
                } else if message.name == "repostGridRemoveResult" {
                    self.onRemove((payload["ok"] as? Bool) == true,
                                  payload["message"] as? String ?? "TikTok не вернул подтверждение.")
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageReady = true
            if pendingRemovalURL != nil {
                performPendingRemoval(in: webView)
            }
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
