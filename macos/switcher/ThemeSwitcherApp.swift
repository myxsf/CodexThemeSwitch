import SwiftUI
import AppKit

private func compactTaskError(_ raw: String, fallback: String = "任务执行失败") -> String {
    let cleaned = raw.replacingOccurrences(
        of: "\u{001B}\\[[0-9;]*[A-Za-z]",
        with: "",
        options: .regularExpression
    )
    let ignoredPrefixes = ["Switching...", "CDP not ready", "Ready:", "Done:"]
    let lines = cleaned
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .filter { line in !ignoredPrefixes.contains(where: line.hasPrefix) }
    let summary = lines.suffix(2).joined(separator: " · ")
    let value = summary.isEmpty ? fallback : summary
    return String(value.prefix(240))
}

private func appendWardrobeDiagnostic(_ raw: String) {
    guard !raw.isEmpty else { return }
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexDreamSkinStudio", isDirectory: true)
    let log = root.appendingPathComponent("wardrobe-error.log")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let entry = "\n[\(ISO8601DateFormatter().string(from: Date()))]\n\(raw)\n"
    guard let data = entry.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: log.path), let handle = try? FileHandle(forWritingTo: log) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.close()
    } else {
        try? data.write(to: log, options: .atomic)
    }
}

private struct RuntimeStatus: Decodable {
    let session: String
    let port: Int
    let injectorAlive: Bool
    let cdpOk: Bool
    let codexRunning: Bool
    let themeName: String
    let themeId: String
    let desiredThemeId: String?
    let liveThemeId: String?
    let themeApplied: Bool?
    let appIntegrityOk: Bool?
    let appIntegrityMessage: String?

    var resolvedThemeId: String {
        if session == "paused" { return "original" }
        if let liveThemeId, !liveThemeId.isEmpty { return liveThemeId }
        return themeId
    }

    var hasThemeMismatch: Bool {
        guard session != "paused", themeApplied == false else { return false }
        return !(desiredThemeId ?? themeId).isEmpty || !(liveThemeId ?? "").isEmpty
    }
}

private struct ThemeCatalog: Decodable {
    let schemaVersion: Int
    let themes: [ThemeDescriptor]
}

private struct ThemeColors: Decodable {
    let background: String?
    let panel: String?
    let panelAlt: String?
    let accent: String?
    let accentAlt: String?
    let secondary: String?
    let highlight: String?
    let text: String?
    let muted: String?
}

private struct ThemeDescriptor: Decodable, Identifiable {
    let id: String
    let kind: String?
    let name: String
    let description: String?
    let subtitle: String?
    let tagline: String?
    let preview: String?
    let profile: String?
    let image: String?
    let order: Int?
    let enabled: Bool?
    let experimental: Bool?
    let colors: ThemeColors?

    var summary: String {
        subtitle ?? description ?? tagline ?? (kind == "original" ? "取消所有注入，恢复 Codex 官方外观。" : "保留真实 Codex 项目、对话和输入功能。")
    }

    var isOriginal: Bool { kind == "original" || id == "original" }
}

private extension Color {
    static func catalogRGB(_ value: String?) -> (red: Double, green: Double, blue: Double)? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let number = UInt64(cleaned, radix: 16) else { return nil }
        return (
            Double((number >> 16) & 0xff) / 255,
            Double((number >> 8) & 0xff) / 255,
            Double(number & 0xff) / 255
        )
    }

    init(catalogHex value: String?, fallback: Color = .blue) {
        guard let rgb = Self.catalogRGB(value) else { self = fallback; return }
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    static func accessibleForeground(forCatalogHex value: String?) -> Color {
        guard let rgb = catalogRGB(value) else { return .white }
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
        return luminance > 0.42 ? Color(red: 0.05, green: 0.08, blue: 0.12) : .white
    }
}

@MainActor
private final class ThemeStore: ObservableObject {
    @Published var themes: [ThemeDescriptor] = []
    @Published var currentTheme = ""
    @Published var themeName = "正在检测…"
    @Published var codexRunning = false
    @Published var injectorAlive = false
    @Published var cdpReady = false
    @Published var isSwitching = false
    @Published var message = ""
    @Published var installedVersion = ""
    @Published var appIntegrityOk = false

    private let engineRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/codex-dream-skin-studio")

    private var pendingApply: DispatchWorkItem?
    private var activeProcess: Process?
    private var activeTaskToken: UUID?
    private var activeTimeout: DispatchWorkItem?
    private var activeOutputHandle: FileHandle?
    private var activeErrorHandle: FileHandle?
    private var activeOutputURL: URL?
    private var activeErrorURL: URL?
    private var securityIntegrityOk: Bool?
    private var statusIntegrityOk: Bool?
    private var statusIntegrityMessage: String?
    private var integrityCheckInFlight = false

    var engineInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: switchScript.path)
    }

    private var switchScript: URL { engineRoot.appendingPathComponent("scripts/theme-macos.sh") }
    private var statusScript: URL { engineRoot.appendingPathComponent("scripts/status-dream-skin-macos.sh") }
    private var bundledStatusScript: URL? { Bundle.main.resourceURL?.appendingPathComponent("Engine/scripts/status-dream-skin-macos.sh") }
    private var effectiveStatusScript: URL {
        if engineNeedsUpdate, let bundledStatusScript, FileManager.default.isExecutableFile(atPath: bundledStatusScript.path) {
            return bundledStatusScript
        }
        return statusScript
    }
    private var startScript: URL { engineRoot.appendingPathComponent("scripts/start-dream-skin-macos.sh") }
    private var bundledInstaller: URL? { Bundle.main.resourceURL?.appendingPathComponent("Engine/scripts/install-dream-skin-macos.sh") }
    private var catalogCandidates: [URL] {
        let installed = engineRoot.appendingPathComponent("themes/catalog.json")
        guard let bundled = Bundle.main.url(forResource: "ThemeCatalog", withExtension: "json") else {
            return [installed]
        }
        return engineNeedsUpdate ? [bundled, installed] : [installed, bundled]
    }
    private var bundledVersion: String {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Engine/VERSION") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var bundledEngineDiffers: Bool {
        guard let bundledRoot = Bundle.main.resourceURL?.appendingPathComponent("Engine") else { return false }
        let manifest = ".engine-manifest.sha256"
        guard let bundledData = try? Data(contentsOf: bundledRoot.appendingPathComponent(manifest)),
              let installedData = try? Data(contentsOf: engineRoot.appendingPathComponent(manifest)) else { return true }
        return bundledData != installedData
    }

    var engineNeedsUpdate: Bool {
        !bundledVersion.isEmpty && (installedVersion != bundledVersion || bundledEngineDiffers)
    }

    var versionSummary: String {
        "衣橱 \(bundledVersion.isEmpty ? "未知" : bundledVersion) · 引擎 \(installedVersion.isEmpty ? "未安装" : installedVersion)"
    }

    init() {
        refreshInstalledVersion()
        loadCatalog()
        refreshAppIntegrity()
        refresh()
    }

    private func refreshAppIntegrity() {
        guard !integrityCheckInFlight else { return }
        integrityCheckInFlight = true
        securityIntegrityOk = nil
        reconcileAppIntegrity()
        let candidates = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            URL(fileURLWithPath: "/Applications/Codex.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/ChatGPT.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Codex.app"),
        ]
        guard let appURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            integrityCheckInFlight = false
            securityIntegrityOk = false
            reconcileAppIntegrity(message: "未找到官方 Codex 应用，请先安装")
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            process.arguments = ["--verify", "--deep", "--strict", appURL.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let valid: Bool
            do {
                try process.run()
                process.waitUntilExit()
                valid = process.terminationStatus == 0
            } catch {
                valid = false
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.integrityCheckInFlight = false
                self.securityIntegrityOk = valid
                self.reconcileAppIntegrity(message: valid ? nil : "官方 Codex 应用签名无效，请从官方来源重新安装")
            }
        }
    }

    private func reconcileAppIntegrity(message integrityMessage: String? = nil) {
        appIntegrityOk = securityIntegrityOk == true && statusIntegrityOk != false
        if !appIntegrityOk {
            message = integrityMessage
                ?? statusIntegrityMessage
                ?? (securityIntegrityOk == nil ? "正在验证官方 Codex 应用完整性…" : "官方 Codex 应用签名无效，请从官方来源重新安装")
        }
    }

    private func refreshInstalledVersion() {
        let versionURL = engineRoot.appendingPathComponent("VERSION")
        installedVersion = (try? String(contentsOf: versionURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func previewURL(for theme: ThemeDescriptor) -> URL? {
        if let image = theme.image, !image.hasPrefix("builtin://") {
            let relative = image.hasPrefix("macos/") ? String(image.dropFirst("macos/".count)) : image
            let installed = engineRoot.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: installed.path) { return installed }
        }
        return Bundle.main.url(forResource: "theme-art-\(theme.id)", withExtension: "jpg")
            ?? Bundle.main.url(forResource: "theme-art-\(theme.id)", withExtension: "png")
    }

    func loadCatalog() {
        for url in catalogCandidates {
            guard let data = try? Data(contentsOf: url),
                  let catalog = try? JSONDecoder().decode(ThemeCatalog.self, from: data),
                  catalog.schemaVersion == 1 else { continue }
            themes = catalog.themes
                .filter { $0.enabled != false }
                .sorted { ($0.order ?? 999) < ($1.order ?? 999) }
            return
        }
        message = "主题目录不可用，请重新安装衣橱"
    }

    func refresh(deep: Bool = true) {
        loadCatalog()
        guard FileManager.default.isExecutableFile(atPath: effectiveStatusScript.path) else {
            themeName = "尚未安装主题引擎"
            message = "请先安装 Codex Dream Skin Studio"
            return
        }
        let arguments = deep ? ["--deep", "--json"] : ["--json"]
        run(effectiveStatusScript, arguments, timeout: deep ? 6 : 2) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let output):
                guard let data = output.data(using: .utf8),
                      let status = try? JSONDecoder().decode(RuntimeStatus.self, from: data) else {
                    self.message = "状态数据无法解析"
                    return
                }
                self.currentTheme = status.resolvedThemeId
                self.themeName = self.themes.first(where: { $0.id == status.resolvedThemeId })?.name
                    ?? (status.themeName.isEmpty ? "未选择主题" : status.themeName)
                self.codexRunning = status.codexRunning
                self.injectorAlive = status.injectorAlive
                if deep {
                    self.cdpReady = status.cdpOk
                    self.statusIntegrityOk = status.appIntegrityOk
                    self.statusIntegrityMessage = status.appIntegrityMessage
                    self.reconcileAppIntegrity()
                }
                if deep && status.appIntegrityOk == false {
                    self.message = status.appIntegrityMessage ?? "官方 Codex 应用签名无效，请重新安装官方应用"
                } else if status.hasThemeMismatch && !self.isSwitching {
                    self.message = "主题状态不一致，正在等待实时界面完成应用"
                } else if self.appIntegrityOk && !self.isSwitching {
                    self.message = ""
                }
            case .failure(let error):
                self.message = error.localizedDescription
            }
        }
    }

    func refreshAndRecover() {
        cancelActiveTask(message: "已取消卡住的任务，正在重新检测…")
        refreshAppIntegrity()
        refresh(deep: true)
    }

    func refreshIfIdle() {
        guard !isSwitching, activeTaskToken == nil else { return }
        refreshInstalledVersion()
        refresh(deep: false)
    }

    func scheduleApply(_ id: String, delay: Double = 0.32) {
        pendingApply?.cancel()
        guard id != currentTheme else { return }
        let work = DispatchWorkItem { [weak self] in self?.apply(id) }
        pendingApply = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func apply(_ id: String) {
        guard !isSwitching else { return }
        cancelActiveTask(message: nil)
        ensureEngineReady { [weak self] ready in
            guard ready else { return }
            self?.applyReady(id)
        }
    }

    private func applyReady(_ id: String) {
        guard !isSwitching, engineInstalled else { return }
        pendingApply?.cancel()
        isSwitching = true
        let selectedName = themes.first(where: { $0.id == id })?.name ?? id
        message = id == "original" ? "正在恢复 Codex 原皮…" : "正在应用 \(selectedName)…"
        run(switchScript, [id], timeout: 120) { [weak self] result in
            guard let self else { return }
            self.isSwitching = false
            switch result {
            case .success:
                self.currentTheme = id
                self.message = id == "original" ? "已恢复 Codex 原皮" : "主题已应用"
                self.refresh()
            case .failure(let error):
                self.confirmAppliedTheme(id, fallback: error.localizedDescription)
            }
        }
    }

    private func confirmAppliedTheme(_ id: String, fallback: String) {
        isSwitching = true
        message = "正在确认主题状态…"
        run(effectiveStatusScript, ["--deep", "--json"], timeout: 6) { [weak self] result in
            guard let self else { return }
            self.isSwitching = false
            guard case .success(let output) = result,
                  let data = output.data(using: .utf8),
                  let status = try? JSONDecoder().decode(RuntimeStatus.self, from: data) else {
                self.message = compactTaskError(fallback)
                return
            }
            let actualTheme = status.resolvedThemeId
            let targetMatches = actualTheme == id
            let runtimeHealthy = id == "original"
                ? status.codexRunning
                : status.codexRunning && status.injectorAlive && status.cdpOk
            self.currentTheme = actualTheme
            self.themeName = status.themeName.isEmpty ? "未选择主题" : status.themeName
            self.codexRunning = status.codexRunning
            self.injectorAlive = status.injectorAlive
            self.cdpReady = status.cdpOk
            if targetMatches && runtimeHealthy {
                self.message = id == "original" ? "已恢复 Codex 原皮" : "主题已应用"
            } else {
                self.message = compactTaskError(fallback)
            }
        }
    }

    func openCodex() {
        guard !isSwitching, appIntegrityOk else {
            message = "官方 Codex 应用签名无效，请从官方来源重新安装"
            return
        }
        cancelActiveTask(message: nil)
        ensureEngineReady { [weak self] ready in
            guard ready else { return }
            self?.openCodexReady()
        }
    }

    private func openCodexReady() {
        guard FileManager.default.isExecutableFile(atPath: startScript.path) else { message = "主题启动器尚未安装"; return }
        isSwitching = true
        message = currentTheme == "original" ? "正在打开原版 Codex…" : "正在带当前主题启动 Codex…"
        run(startScript, ["--port", "9341", "--restart-existing"], timeout: 120) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.verifyOpenedCodex()
            case .failure(let error):
                self.verifyOpenedCodex(fallbackMessage: error.localizedDescription)
            }
        }
    }

    private func verifyOpenedCodex(fallbackMessage: String? = nil) {
        isSwitching = true
        message = "正在确认 Codex 连接状态…"
        run(effectiveStatusScript, ["--deep", "--json"], timeout: 6) { [weak self] result in
            guard let self else { return }
            self.isSwitching = false
            guard case .success(let output) = result,
                  let data = output.data(using: .utf8),
                  let status = try? JSONDecoder().decode(RuntimeStatus.self, from: data) else {
                self.message = fallbackMessage.map { compactTaskError($0) }
                    ?? "Codex 启动后状态无法读取，请查看启动日志"
                return
            }
            self.currentTheme = status.resolvedThemeId
            self.themeName = status.themeName.isEmpty ? "未选择主题" : status.themeName
            self.codexRunning = status.codexRunning
            self.injectorAlive = status.injectorAlive
            self.cdpReady = status.cdpOk
            self.statusIntegrityOk = status.appIntegrityOk
            self.statusIntegrityMessage = status.appIntegrityMessage
            self.reconcileAppIntegrity()
            if status.appIntegrityOk == false {
                self.message = status.appIntegrityMessage ?? "官方 Codex 应用签名无效，请重新安装官方应用"
                return
            }
            let themedHealthy = self.currentTheme == "original" || (status.injectorAlive && status.cdpOk)
            self.message = status.codexRunning && themedHealthy
                ? "检测到 Codex 正在运行，主题连接正常"
                : (fallbackMessage.map { compactTaskError($0) }
                    ?? "Codex 启动后未通过健康检查，请查看引擎日志")
        }
    }

    func installOrUpdateEngine() {
        guard !isSwitching else { return }
        cancelActiveTask(message: nil)
        let themeToRestore = currentTheme.isEmpty ? "original" : currentTheme
        ensureEngineReady(force: true) { [weak self] ready in
            guard ready else { return }
            self?.applyReady(themeToRestore)
        }
    }

    private func ensureEngineReady(force: Bool = false, completion: @escaping (Bool) -> Void) {
        refreshInstalledVersion()
        if !force && engineInstalled && !engineNeedsUpdate {
            completion(true)
            return
        }
        guard let installer = bundledInstaller, FileManager.default.isExecutableFile(atPath: installer.path) else {
            message = "应用内置主题引擎缺失，请重新安装衣橱"
            completion(false)
            return
        }
        isSwitching = true
        message = installedVersion.isEmpty ? "正在安装主题引擎…" : "正在更新主题引擎…"
        run(installer, ["--no-launchers", "--no-launch"], timeout: 45) { [weak self] result in
            guard let self else { completion(false); return }
            self.isSwitching = false
            switch result {
            case .success:
                self.refreshInstalledVersion()
                self.loadCatalog()
                self.message = "主题引擎已更新到 \(self.installedVersion)"
                completion(true)
            case .failure(let error):
                self.message = error.localizedDescription
                completion(false)
            }
        }
    }

    private func run(
        _ executable: URL,
        _ arguments: [String],
        timeout: TimeInterval,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard activeTaskToken == nil else {
            completion(.failure(NSError(domain: "CodexThemeSwitcher", code: 75, userInfo: [NSLocalizedDescriptionKey: "已有操作正在执行，请先取消或等待完成"])))
            return
        }
        let token = UUID()
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("codex-wardrobe-\(token.uuidString).out")
        let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent("codex-wardrobe-\(token.uuidString).err")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        guard let outputHandle = try? FileHandle(forWritingTo: outputURL),
              let errorHandle = try? FileHandle(forWritingTo: errorURL) else {
            completion(.failure(NSError(domain: "CodexThemeSwitcher", code: 74, userInfo: [NSLocalizedDescriptionKey: "无法创建任务日志文件"])))
            return
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        activeProcess = process
        activeTaskToken = token
        activeOutputHandle = outputHandle
        activeErrorHandle = errorHandle
        activeOutputURL = outputURL
        activeErrorURL = errorURL

        let finish: (Result<String, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.activeTaskToken == token else { return }
                self.activeTimeout?.cancel()
                self.activeTimeout = nil
                self.activeProcess = nil
                self.activeTaskToken = nil
                self.activeOutputHandle = nil
                self.activeErrorHandle = nil
                self.activeOutputURL = nil
                self.activeErrorURL = nil
                self.deferBusyStateReset()
                try? outputHandle.close()
                try? errorHandle.close()
                try? FileManager.default.removeItem(at: outputURL)
                try? FileManager.default.removeItem(at: errorURL)
                completion(result)
            }
        }

        process.terminationHandler = { process in
            try? outputHandle.close()
            try? errorHandle.close()
            let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
            let errorOutput = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
            if process.terminationStatus == 0 {
                finish(.success(output.trimmingCharacters(in: .whitespacesAndNewlines)))
            } else {
                let rawDetail = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                appendWardrobeDiagnostic(rawDetail)
                let detail = compactTaskError(rawDetail)
                finish(.failure(NSError(domain: "CodexThemeSwitcher", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: detail])))
            }
        }

        let timeoutWork = DispatchWorkItem { [weak self, weak process] in
            guard let self, self.activeTaskToken == token else { return }
            if process?.isRunning == true { process?.terminate() }
            finish(.failure(NSError(domain: "CodexThemeSwitcher", code: 124, userInfo: [NSLocalizedDescriptionKey: "操作超时，已自动取消并恢复主题切换"])))
        }
        activeTimeout = timeoutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

        do {
            try process.run()
        } catch {
            finish(.failure(error))
        }
    }

    private func cancelActiveTask(message newMessage: String?) {
        pendingApply?.cancel()
        pendingApply = nil
        activeTimeout?.cancel()
        activeTimeout = nil
        if activeProcess?.isRunning == true { activeProcess?.terminate() }
        activeProcess = nil
        activeTaskToken = nil
        try? activeOutputHandle?.close()
        try? activeErrorHandle?.close()
        activeOutputHandle = nil
        activeErrorHandle = nil
        if let activeOutputURL { try? FileManager.default.removeItem(at: activeOutputURL) }
        if let activeErrorURL { try? FileManager.default.removeItem(at: activeErrorURL) }
        activeOutputURL = nil
        activeErrorURL = nil
        deferBusyStateReset()
        if let newMessage { message = newMessage }
    }

    private func deferBusyStateReset() {
        isSwitching = false
    }
}

private struct StatusPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let activeLabel: String
    let inactiveLabel: String
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active
                    ? Color(red: 0.11, green: 0.68, blue: 0.48)
                    : (colorScheme == .dark ? Color.white.opacity(0.34) : Color.secondary.opacity(0.55)))
                .frame(width: 8, height: 8)
            Text(active ? activeLabel : inactiveLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    colorScheme == .dark
                        ? Color.white.opacity(active ? 0.92 : 0.60)
                        : (active ? Color.primary : Color.secondary)
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            colorScheme == .dark
                ? Color.white.opacity(active ? 0.10 : 0.055)
                : Color.white.opacity(active ? 0.72 : 0.46),
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(
                colorScheme == .dark
                    ? Color.white.opacity(active ? 0.18 : 0.09)
                    : Color.white.opacity(active ? 0.8 : 0.48),
                lineWidth: 1
            )
        )
    }
}

private struct PreviewImage: View {
    let theme: ThemeDescriptor
    let url: URL?
    let accent: Color

    private var background: Color { Color(catalogHex: theme.colors?.background, fallback: accent.opacity(0.16)) }
    private var panel: Color { Color(catalogHex: theme.colors?.panel, fallback: .white) }
    private var panelAlt: Color { Color(catalogHex: theme.colors?.panelAlt, fallback: accent.opacity(0.10)) }
    private var accentAlt: Color { Color(catalogHex: theme.colors?.accentAlt, fallback: accent) }
    private var secondary: Color { Color(catalogHex: theme.colors?.secondary, fallback: accentAlt) }
    private var textColor: Color { Color(catalogHex: theme.colors?.text, fallback: .primary) }
    private var mutedColor: Color { Color(catalogHex: theme.colors?.muted, fallback: textColor.opacity(0.58)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [background, panelAlt], startPoint: .topLeading, endPoint: .bottomTrailing)
            if theme.isOriginal {
                VStack(spacing: 10) {
                    Image(systemName: "app.dashed").font(.system(size: 42, weight: .light))
                    Text("CODEX ORIGINAL").font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(2)
                }
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                LinearGradient(
                    colors: [.black.opacity(0.05), .clear, .black.opacity(0.22)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else if theme.profile == "qq2007" {
                qqPreview
            } else {
                workspacePreview
            }
            Text("主题素材预览")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(url == nil ? textColor.opacity(0.80) : Color.white.opacity(0.96))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(url == nil ? panel.opacity(0.82) : Color.black.opacity(0.42), in: Capsule())
                .overlay(Capsule().stroke(url == nil ? accent.opacity(0.28) : Color.white.opacity(0.28), lineWidth: 1))
                .padding(9)
        }
        .frame(height: 178)
        .clipped()
    }

    private var workspacePreview: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).fill(accent).frame(width: 28, height: 6)
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(index == 1 ? accent.opacity(0.25) : mutedColor.opacity(0.18))
                        .frame(height: index == 1 ? 16 : 7)
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 92)
            .background(panel.opacity(0.94))

            VStack(spacing: 9) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [panel, panelAlt], startPoint: .leading, endPoint: .trailing))
                    if let url, let image = NSImage(contentsOf: url) {
                        HStack(spacing: 0) {
                            Spacer(minLength: 90)
                            Image(nsImage: image).resizable().scaledToFill().frame(maxWidth: 160).clipped().opacity(0.82)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    LinearGradient(colors: [panel.opacity(0.98), panel.opacity(0.72), .clear], startPoint: .leading, endPoint: .trailing)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(textColor.opacity(0.82)).frame(width: 76, height: 8)
                        RoundedRectangle(cornerRadius: 3).fill(mutedColor.opacity(0.42)).frame(width: 112, height: 5)
                        RoundedRectangle(cornerRadius: 5).fill(accent).frame(width: 54, height: 14)
                    }
                    .padding(13)
                }
                .frame(height: 88)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.24), lineWidth: 1))

                HStack(spacing: 8) {
                    ForEach([accent, accentAlt, secondary], id: \.self) { color in
                        RoundedRectangle(cornerRadius: 7).fill(panel.opacity(0.94))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.42), lineWidth: 1))
                    }
                }
                .frame(height: 28)
                RoundedRectangle(cornerRadius: 9).fill(panel.opacity(0.96))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(accent.opacity(0.62), lineWidth: 1.2))
                    .frame(height: 27)
            }
            .padding(11)
        }
    }

    private var qqPreview: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color(red: 0.51, green: 0.72, blue: 0.90), Color(red: 0.20, green: 0.49, blue: 0.76)], startPoint: .top, endPoint: .bottom)
                .frame(height: 28)
                .overlay(Text("CODEX QQ 2007").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
            HStack(spacing: 1) {
                VStack(spacing: 7) {
                    Circle().fill(Color.white.opacity(0.95)).frame(width: 34, height: 34)
                    ForEach(0..<5, id: \.self) { _ in RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.18)).frame(height: 6) }
                    Spacer()
                }.padding(9).frame(width: 82).background(Color(red: 0.90, green: 0.96, blue: 1.0))
                VStack(spacing: 7) {
                    ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 4).fill(.white).frame(height: 20).overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.blue.opacity(0.18))) }
                    Spacer()
                }.padding(9).frame(width: 92).background(Color(red: 0.96, green: 0.985, blue: 1.0))
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 5).fill(.white).frame(height: 72).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.blue.opacity(0.22)))
                    RoundedRectangle(cornerRadius: 5).fill(.white).frame(height: 28).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.blue.opacity(0.45)))
                    Spacer()
                }.padding(9).background(Color(red: 0.92, green: 0.96, blue: 0.99))
            }
        }
        .overlay(Rectangle().stroke(Color(red: 0.18, green: 0.44, blue: 0.68), lineWidth: 1))
    }
}

private struct ThemeCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let theme: ThemeDescriptor
    let previewURL: URL?
    let selected: Bool
    let focused: Bool
    let disabled: Bool
    let apply: () -> Void

    private var accent: Color { Color(catalogHex: theme.colors?.accent, fallback: theme.isOriginal ? .gray : .blue) }
    private var accentForeground: Color { Color.accessibleForeground(forCatalogHex: theme.colors?.accent) }
    private var cardSurface: Color { colorScheme == .dark ? Color(red: 0.09, green: 0.11, blue: 0.15) : .white.opacity(0.92) }
    private var cardText: Color { colorScheme == .dark ? .white : .primary }
    private var cardMuted: Color { colorScheme == .dark ? .white.opacity(0.68) : .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                PreviewImage(theme: theme, url: previewURL, accent: accent)
                HStack(spacing: 6) {
                    if theme.experimental == true {
                        Text("实验性").foregroundStyle(.black).background(.white.opacity(0.86), in: Capsule())
                    }
                    if selected {
                        Text("当前主题").foregroundStyle(accentForeground).background(accent, in: Capsule())
                    }
                }
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .padding(10)
                VStack {
                    Spacer()
                    HStack {
                        Text("© myxsf · 禁止转卖 / 盗版")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.34), in: Capsule())
                        Spacer()
                    }
                    .padding(10)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(theme.name).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(cardText)
                Text(theme.summary).font(.system(size: 12)).foregroundStyle(cardMuted).lineLimit(2).frame(height: 34, alignment: .top)
                if selected {
                    Label("当前正在使用", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Button(action: apply) {
                        Text(theme.isOriginal ? "取消皮肤" : "应用此主题")
                            .foregroundStyle(accentForeground)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.large)
                    .disabled(disabled)
                    .opacity(disabled ? 0.68 : 1)
                }
            }
            .padding(16)
        }
        .background(cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(selected ? accent : (focused ? accent.opacity(0.58) : (colorScheme == .dark ? .white.opacity(0.13) : .white.opacity(0.9))), lineWidth: selected ? 3 : (focused ? 2 : 1)))
        .shadow(color: .black.opacity(focused ? 0.15 : 0.08), radius: focused ? 22 : 13, y: focused ? 10 : 6)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.easeOut(duration: 0.22), value: focused)
    }
}

private struct ThemeCarousel: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: ThemeStore
    @Binding var index: Int

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = min(430.0, max(320.0, geometry.size.width * 0.52))
            ScrollViewReader { proxy in
                ZStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 18) {
                            ForEach(Array(store.themes.enumerated()), id: \.element.id) { offset, theme in
                                ThemeCard(
                                    theme: theme,
                                    previewURL: store.previewURL(for: theme),
                                    selected: store.currentTheme == theme.id,
                                    focused: index == offset,
                                    disabled: store.isSwitching || !store.engineInstalled,
                                    apply: {
                                        index = offset
                                        scroll(to: offset, proxy: proxy)
                                        store.apply(theme.id)
                                    }
                                )
                                .frame(width: cardWidth)
                                .id(theme.id)
                                .onTapGesture {
                                    index = offset
                                    scroll(to: offset, proxy: proxy)
                                }
                            }
                        }
                        .padding(.horizontal, max(24, (geometry.size.width - cardWidth) / 2))
                        .padding(.vertical, 18)
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 18).onEnded { value in
                        let threshold = max(34, cardWidth * 0.12)
                        if value.predictedEndTranslation.width < -threshold { move(1, proxy: proxy) }
                        else if value.predictedEndTranslation.width > threshold { move(-1, proxy: proxy) }
                        else { scroll(to: index, proxy: proxy) }
                    })

                    HStack {
                        arrow("chevron.left", enabled: index > 0) { move(-1, proxy: proxy) }
                        Spacer()
                        arrow("chevron.right", enabled: index + 1 < store.themes.count) { move(1, proxy: proxy) }
                    }
                    .padding(.horizontal, 8)
                }
                .onAppear { syncIndex(proxy: proxy) }
                .onChange(of: store.currentTheme) { _ in syncIndex(proxy: proxy) }
            }
        }
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        let foreground: Color = enabled
            ? (colorScheme == .dark ? .white : .primary)
            : (colorScheme == .dark ? .white.opacity(0.28) : .secondary.opacity(0.30))
        let background: Color = colorScheme == .dark
            ? .white.opacity(enabled ? 0.10 : 0.035)
            : .white.opacity(enabled ? 0.76 : 0.30)
        let border: Color = colorScheme == .dark
            ? .white.opacity(enabled ? 0.20 : 0.08)
            : .white.opacity(enabled ? 0.82 : 0.38)

        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 34, height: 44)
        }
            .buttonStyle(.plain)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay(Capsule().stroke(border, lineWidth: 1))
            .opacity(store.isSwitching ? 0.45 : 1)
            .disabled(!enabled || store.isSwitching)
    }

    private func move(_ delta: Int, proxy: ScrollViewProxy) {
        guard !store.themes.isEmpty else { return }
        index = min(max(index + delta, 0), store.themes.count - 1)
        scroll(to: index, proxy: proxy)
        store.scheduleApply(store.themes[index].id)
    }

    private func syncIndex(proxy: ScrollViewProxy) {
        guard let match = store.themes.firstIndex(where: { $0.id == store.currentTheme }) else {
            index = min(max(index, 0), max(0, store.themes.count - 1))
            return
        }
        index = match
        DispatchQueue.main.async {
            scroll(to: match, proxy: proxy)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                scroll(to: match, proxy: proxy)
            }
        }
    }

    private func scroll(to offset: Int, proxy: ScrollViewProxy) {
        guard store.themes.indices.contains(offset) else { return }
        withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.84, blendDuration: 0.16)) {
            proxy.scrollTo(store.themes[offset].id, anchor: .center)
        }
    }
}

private struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var store = ThemeStore()
    @State private var carouselIndex = 0

    private var brandHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [.blue, .mint], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("✦").font(.system(size: 25, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            .shadow(color: .blue.opacity(0.2), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 3) {
                Text("Codex 万能皮肤衣橱")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(colorScheme == .dark ? .white : .primary)
                HStack(spacing: 8) {
                    Text("左右滑动即可浏览并切换全部已安装主题")
                        .font(.system(size: 13))
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.68) : .secondary)
                    Text("作者 myxsf · 禁止开源转卖与盗版")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(colorScheme == .dark ? Color.yellow.opacity(0.92) : Color.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            colorScheme == .dark ? Color.yellow.opacity(0.10) : Color.orange.opacity(0.10),
                            in: Capsule()
                        )
                }
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            if store.engineNeedsUpdate || !store.engineInstalled {
                Button(action: store.installOrUpdateEngine) {
                    Label("安装/更新引擎", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isSwitching)
            }
            Button(action: { store.apply("original") }) {
                Label("恢复原皮", systemImage: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.bordered)
            .disabled(store.isSwitching || store.currentTheme == "original")

            Button(action: store.refreshAndRecover) {
                Label(store.isSwitching ? "取消并检测" : "重新检测", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button(action: store.openCodex) {
                Label("打开 Codex", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
            .disabled(store.isSwitching || !store.engineInstalled || !store.appIntegrityOk)
        }
    }

    private var themeStatusText: String {
        if store.currentTheme == "original" { return "当前：Codex 原皮" }
        let name = store.themeName.isEmpty ? "未选择主题" : store.themeName
        return store.injectorAlive && store.cdpReady ? "当前主题：\(name)" : "已选择：\(name)"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.035, green: 0.055, blue: 0.09), Color(red: 0.12, green: 0.075, blue: 0.12)]
                    : [Color(red: 0.95, green: 0.98, blue: 1.0), Color(red: 1.0, green: 0.96, blue: 0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()

            VStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        brandHeader
                        Spacer(minLength: 12)
                        headerActions
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        brandHeader
                        HStack {
                            Spacer()
                            headerActions
                        }
                    }
                }

                if store.themes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "paintpalette").font(.system(size: 42)).foregroundStyle(.secondary)
                        Text("没有可用主题").font(.title2.bold())
                        Text("请重新安装主题目录后再试。").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ThemeCarousel(store: store, index: $carouselIndex)
                    HStack(spacing: 5) {
                        ForEach(Array(store.themes.enumerated()), id: \.element.id) { offset, _ in
                            Circle()
                                .fill(
                                    offset == carouselIndex
                                        ? Color.accentColor
                                        : (colorScheme == .dark ? Color.white.opacity(0.28) : Color.secondary.opacity(0.24))
                                )
                                .frame(width: offset == carouselIndex ? 8 : 6, height: offset == carouselIndex ? 8 : 6)
                        }
                    }
                    .frame(height: 12)
                }

                HStack(spacing: 10) {
                    StatusPill(activeLabel: "Codex 运行中", inactiveLabel: "Codex 未运行", active: store.codexRunning)
                    StatusPill(activeLabel: "注入器正常", inactiveLabel: "注入器未运行", active: store.injectorAlive)
                    StatusPill(activeLabel: "主题已连接", inactiveLabel: "主题未连接", active: store.cdpReady)
                    Divider().frame(height: 22)
                    Text(themeStatusText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .primary)
                    Text(store.versionSummary)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.52) : .secondary)
                    Spacer()
                    if store.isSwitching { ProgressView().controlSize(.small) }
                    Text(store.message)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 380, alignment: .trailing)
                        .help(store.message)
                        .foregroundStyle(
                            store.message.contains("失败") || store.message.contains("签名无效") || store.message.contains("未找到官方")
                                ? .red
                                : (colorScheme == .dark ? Color.white.opacity(0.72) : .secondary)
                        )
                }
                .padding(12)
                .background(colorScheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.55), lineWidth: 1))
            }
            .padding(24)
        }
        .frame(minWidth: 820, idealWidth: 980, minHeight: 590, idealHeight: 660)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshIfIdle()
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            store.refreshIfIdle()
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
private struct CodexThemeSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Codex 万能皮肤衣橱") { ContentView() }
            .defaultSize(width: 980, height: 660)
    }
}
