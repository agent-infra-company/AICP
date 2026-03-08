import AppKit
import Foundation
import os.log

enum WebAIService: String, CaseIterable {
    case chatGPT = "chatgpt"
    case claude = "claude"
    case gemini = "gemini"

    var displayName: String {
        switch self {
        case .chatGPT: "ChatGPT"
        case .claude: "Claude"
        case .gemini: "Gemini"
        }
    }

    var urlPatterns: [String] {
        switch self {
        case .chatGPT: ["chatgpt.com", "chat.openai.com"]
        case .claude: ["claude.ai"]
        case .gemini: ["gemini.google.com"]
        }
    }

    /// Suffix to strip from tab titles to extract the conversation name.
    var titleSuffix: String? {
        switch self {
        case .chatGPT: nil // ChatGPT uses the conversation name as-is
        case .claude: " - Claude"
        case .gemini: " - Gemini"
        }
    }

    /// Extract a stable conversation ID from the URL path.
    func conversationId(from url: String) -> String {
        guard let parsed = URL(string: url) else { return "new" }
        let path = parsed.path
        switch self {
        case .chatGPT:
            // chatgpt.com/c/{id} or chatgpt.com/g/{id}
            let segments = path.split(separator: "/")
            if segments.count >= 2, (segments[0] == "c" || segments[0] == "g") {
                return String(segments[1])
            }
        case .claude:
            // claude.ai/chat/{uuid}
            let segments = path.split(separator: "/")
            if segments.count >= 2, segments[0] == "chat" {
                return String(segments[1])
            }
        case .gemini:
            // gemini.google.com/app/{id}
            let segments = path.split(separator: "/")
            if segments.count >= 2, segments[0] == "app" {
                return String(segments[1])
            }
        }
        return "new"
    }

    func parseTitle(from rawTitle: String) -> String {
        var title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suffix = titleSuffix, title.hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count))
        }
        if title.isEmpty || title == displayName {
            return "New conversation"
        }
        return title
    }

    static func matchingService(for url: String) -> WebAIService? {
        let lowered = url.lowercased()
        for service in allCases {
            for pattern in service.urlPatterns {
                if lowered.contains(pattern) {
                    return service
                }
            }
        }
        return nil
    }
}

struct BrowserTarget {
    let name: String
    let bundleIdentifier: String
    let appleScriptAppName: String
    let isChromium: Bool

    static let allKnown: [BrowserTarget] = [
        BrowserTarget(
            name: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            appleScriptAppName: "Google Chrome",
            isChromium: true
        ),
        BrowserTarget(
            name: "Arc",
            bundleIdentifier: "company.thebrowser.Browser",
            appleScriptAppName: "Arc",
            isChromium: true
        ),
        BrowserTarget(
            name: "Brave Browser",
            bundleIdentifier: "com.brave.Browser",
            appleScriptAppName: "Brave Browser",
            isChromium: true
        ),
        BrowserTarget(
            name: "Microsoft Edge",
            bundleIdentifier: "com.microsoft.edgemac",
            appleScriptAppName: "Microsoft Edge",
            isChromium: true
        ),
        BrowserTarget(
            name: "Safari",
            bundleIdentifier: "com.apple.Safari",
            appleScriptAppName: "Safari",
            isChromium: false
        ),
    ]

    func appleScript() -> String {
        if isChromium {
            return """
                tell application "\(appleScriptAppName)"
                    set output to ""
                    set winIdx to 0
                    repeat with w in windows
                        set winIdx to winIdx + 1
                        set tabIdx to 0
                        repeat with t in tabs of w
                            set tabIdx to tabIdx + 1
                            set tabURL to URL of t
                            set tabTitle to title of t
                            set output to output & winIdx & "\t" & tabIdx & "\t" & tabURL & "\t" & tabTitle & linefeed
                        end repeat
                    end repeat
                    return output
                end tell
                """
        } else {
            return """
                tell application "\(appleScriptAppName)"
                    set output to ""
                    set winIdx to 0
                    repeat with w in windows
                        set winIdx to winIdx + 1
                        set tabIdx to 0
                        repeat with t in tabs of w
                            set tabIdx to tabIdx + 1
                            set tabURL to URL of t
                            set tabTitle to name of t
                            set output to output & winIdx & "\t" & tabIdx & "\t" & tabURL & "\t" & tabTitle & linefeed
                        end repeat
                    end repeat
                    return output
                end tell
                """
        }
    }
}

struct BrowserTab {
    let windowIndex: Int
    let tabIndex: Int
    let url: String
    let title: String
    let browser: BrowserTarget
    let service: WebAIService
}

final class WebAIChatTaskSource: TaskSource, @unchecked Sendable {
    let sourceKind: TaskSourceKind = .webAIChat

    private static let log = CompanionDiagnostics.logger(category: "WebAIChatTaskSource")

    private let pollInterval: TimeInterval
    private var isRunning = false
    private var failedBrowsers: Set<String> = []
    private var failureCounts: [String: Int] = [:]

    init(pollInterval: TimeInterval = 8.0) {
        self.pollInterval = pollInterval
    }

    func isAvailable() async -> Bool {
        // Reset failure tracking on availability refresh
        failedBrowsers = []
        failureCounts = [:]

        let anyBrowserRunning = BrowserTarget.allKnown.contains { browser in
            NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == browser.bundleIdentifier
            }
        }

        Self.log.debug("Availability anyBrowserRunning=\(anyBrowserRunning)")
        return anyBrowserRunning
    }

    func startMonitoring() async -> AsyncStream<[ExternalTaskSnapshot]> {
        isRunning = true
        return AsyncStream { [weak self] continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                while self.isRunning && !Task.isCancelled {
                    continuation.yield(self.scanBrowserTabs())
                    try? await Task.sleep(for: .seconds(self.pollInterval))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func stopMonitoring() async {
        isRunning = false
    }

    private func scanBrowserTabs() -> [ExternalTaskSnapshot] {
        var allTabs: [BrowserTab] = []

        for browser in BrowserTarget.allKnown {
            // Skip browsers we've repeatedly failed to query
            if failedBrowsers.contains(browser.bundleIdentifier) {
                continue
            }

            let isBrowserRunning = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == browser.bundleIdentifier
            }
            guard isBrowserRunning else { continue }

            let script = browser.appleScript()
            guard
                let output = ProcessProbe.run(
                    path: "/usr/bin/osascript",
                    arguments: ["-e", script],
                    logger: Self.log,
                    label: "osascript-\(browser.name)"
                )
            else {
                // Track failures — after 3 consecutive failures, skip this browser
                let count = (failureCounts[browser.bundleIdentifier] ?? 0) + 1
                failureCounts[browser.bundleIdentifier] = count
                if count >= 3 {
                    failedBrowsers.insert(browser.bundleIdentifier)
                    Self.log.info(
                        "Skipping \(browser.name, privacy: .public) after \(count) consecutive failures (likely missing Automation permission)"
                    )
                }
                continue
            }

            // Reset failure count on success
            failureCounts[browser.bundleIdentifier] = 0

            let tabs = parseOutput(output, browser: browser)
            allTabs.append(contentsOf: tabs)
        }

        Self.log.debug("Web AI scan complete matchingTabs=\(allTabs.count)")

        return allTabs.map { tab in
            let conversationId = tab.service.conversationId(from: tab.url)
            let title = tab.service.parseTitle(from: tab.title)
            let snapshotId = "\(tab.browser.bundleIdentifier)-\(tab.service.rawValue)-\(conversationId)"

            return ExternalTaskSnapshot(
                id: snapshotId,
                sourceKind: .webAIChat,
                title: title,
                workspace: nil,
                status: .running,
                progress: tab.service.displayName,
                needsInputPrompt: nil,
                lastError: nil,
                updatedAt: Date(),
                deepLinkURL: URL(string: tab.url),
                metadata: [
                    "service": tab.service.rawValue,
                    "browser": tab.browser.bundleIdentifier,
                    "browserName": tab.browser.name,
                    "windowIndex": String(tab.windowIndex),
                    "tabIndex": String(tab.tabIndex),
                ]
            )
        }
    }

    private func parseOutput(_ output: String, browser: BrowserTarget) -> [BrowserTab] {
        var tabs: [BrowserTab] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 4,
                let windowIndex = Int(parts[0]),
                let tabIndex = Int(parts[1])
            else { continue }

            let url = parts[2]
            let title = parts[3...].joined(separator: "\t") // title may contain tabs

            guard let service = WebAIService.matchingService(for: url) else { continue }

            tabs.append(
                BrowserTab(
                    windowIndex: windowIndex,
                    tabIndex: tabIndex,
                    url: url,
                    title: title,
                    browser: browser,
                    service: service
                )
            )
        }

        return tabs
    }
}
