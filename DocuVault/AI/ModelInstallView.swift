import SwiftUI
import Network
import DocuVaultCore

/// The built-in paragraph for "Try it" (checkpoint 18 Q4): never one of Evan's documents.
enum ModelTrial {
    static let sample = "甲方同意将位于上海市静安区南京西路一千号十二楼的办公室出租给乙方，租期自二〇二六年十一月一日起，为期两年。月租金为人民币三万元，每三个月支付一次。乙方须于签约时支付三个月租金作为押金，租期届满且无违约时全额退还。"
}

/// Introduce the Chinese model before a 2.5 GB download (checkpoint 18 frames 2 and 3): what it is, how
/// big, that nothing leaves the phone, then a check of space, connection and battery.
struct ModelInstallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var models = LocalModelManager.shared
    @State private var step = 0
    @State private var connection: InstallCheck.Connection = .none
    @State private var monitor: NWPathMonitor?

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 { intro } else { checks }
            }
            .background(Theme.Colors.canvas)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { models.offerAnswered = true; dismiss() } } }
        }
        .onAppear(perform: startMonitor)
        .onDisappear { monitor?.cancel() }
    }

    // MARK: Step 1 · what it is

    private var intro: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    Text("中").font(.system(size: 32, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 76, height: 76).accentSheen(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.top, 8)
                    Text("Chinese summaries on this iPhone").font(.system(size: 24, weight: .bold)).multilineTextAlignment(.center)
                    Text("A language model that reads Chinese documents and writes the summary. It runs on the phone itself.")
                        .font(.system(size: 16)).foregroundStyle(Theme.Colors.ink2).multilineTextAlignment(.center)
                    CardSection {
                        point("lock.fill", "Nothing leaves your iPhone", "Your documents are never sent anywhere. It works in flight mode.")
                        point("arrow.down.circle", "\(InstallCheck.gigabytes(models.totalBytes, digits: 1)), downloaded once",
                              "From Hugging Face, the public library for open AI models. Delete it any time in Settings.")
                        point("checkmark.shield", "Apple's model stays as a backup", "If this one is off or missing, summaries still work, in plainer Chinese.")
                    }
                }
                .padding(20)
            }
            primary("Continue") { withAnimation { step = 1 } }
        }
    }

    private func point(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Colors.accent)
                .frame(width: 32, height: 32).background(Theme.Colors.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 14)).foregroundStyle(Theme.Colors.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: Step 2 · the phone is ready

    private var items: [InstallCheck.Item] {
        let device = UIDevice.current
        let level = device.batteryLevel
        return InstallCheck.items(freeBytes: freeBytes, connection: connection,
                                  battery: level < 0 ? nil : Double(level),
                                  charging: device.batteryState == .charging || device.batteryState == .full,
                                  downloadBytes: models.totalBytes)
    }

    private var checks: some View {
        let list = items
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Before you download").font(.system(size: 24, weight: .bold))
                    CardSection(title: "Checked on this iPhone now") {
                        ForEach(list, id: \.label) { i in
                            HStack {
                                Text(i.label).font(.system(size: 17, weight: .semibold))
                                Spacer()
                                Text(i.value).font(.system(size: 16, weight: i.tone == .ok ? .regular : .semibold))
                                    .foregroundStyle(color(i.tone)).multilineTextAlignment(.trailing)
                                if i.tone == .ok { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.Colors.verified) }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                        }
                    }
                    Text("You can leave DocuVault while it downloads. It finishes in the background and tells you when it is ready.")
                        .font(.system(size: 15)).foregroundStyle(Theme.Colors.ink2).padding(.horizontal, 4)
                }
                .padding(20)
            }
            if !InstallCheck.canStart(list) {
                Text("Free up some space, then come back.").font(.system(size: 15)).foregroundStyle(Theme.Colors.danger).padding(.bottom, 30)
            } else if connection == .cellular {
                primary("Download on mobile data") { start(cellular: true) }
                Button("Wait for Wi-Fi") { start(cellular: false) }
                    .font(.system(size: 17, weight: .semibold)).padding(.bottom, 24)
            } else {
                primary("Download \(InstallCheck.gigabytes(models.totalBytes, digits: 1))") { start(cellular: false) }
            }
        }
    }

    private func color(_ t: InstallCheck.Tone) -> Color {
        switch t { case .ok: Theme.Colors.ink2; case .warn: Theme.Colors.warning; case .stop: Theme.Colors.danger }
    }

    private func start(cellular: Bool) {
        UserDefaults.standard.set(cellular, forKey: "mlx.allowCellular")
        models.offerAnswered = true
        Task { await models.download(allowCellular: cellular) }
        dismiss()
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .accentSheen(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressScale)
        .padding(.horizontal, 20).padding(.bottom, 12)
    }

    private var freeBytes: Int64 {
        let v = try? URL.homeDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func startMonitor() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let m = NWPathMonitor()
        m.pathUpdateHandler = { path in
            let c: InstallCheck.Connection = path.status != .satisfied ? .none : (path.usesInterfaceType(.wifi) && !path.isExpensive ? .wifi : .cellular)
            Task { @MainActor in connection = c }
        }
        m.start(queue: DispatchQueue(label: "docuvault.path"))
        monitor = m
    }
}

/// The Chinese model on the Summaries page: every state of the download in one card (frames 4 to 6).
struct ChineseModelSection: View {
    @State private var models = LocalModelManager.shared
    @State private var showInstall = false
    @State private var trial: String?
    @State private var trying = false

    var body: some View {
        Group {
            switch models.state {
            case .unavailable(let why):
                CardSection(title: "中文") { CardRow(title: "Chinese model", subtitle: why, icon: "character.textbox") }
            case .notInstalled:
                CardSection(title: "中文") {
                    Button { showInstall = true } label: {
                        CardRow(title: "Chinese model", subtitle: "Not installed · \(InstallCheck.gigabytes(models.totalBytes, digits: 1))", icon: "character.textbox", value: "Get")
                    }
                    .buttonStyle(.plain)
                }
            case .downloading(let r, let t):
                progressCard(received: r, total: t, paused: false)
            case .paused(let r, let t):
                progressCard(received: r, total: t, paused: true)
            case .verifying:
                CardSection(title: "中文") {
                    HStack { CardRow(title: "Checking the download", subtitle: "Making sure every file is intact"); ProgressView().padding(.trailing, 16) }
                }
            case .installed, .loading, .ready:
                installed
            case .failed(let message):
                CardSection(title: "中文") {
                    CardRow(title: "Download stopped", subtitle: message, icon: "exclamationmark.triangle", tint: Theme.Colors.danger)
                    Button { resume() } label: { Text("Resume").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.Colors.accent).frame(maxWidth: .infinity).padding(.vertical, 14) }
                        .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showInstall) { ModelInstallSheet() }
    }

    private func progressCard(received: Int64, total: Int64, paused: Bool) -> some View {
        let fraction = total > 0 ? Double(received) / Double(total) : 0
        return CardSection(title: "中文") {
            VStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Theme.Colors.canvas, lineWidth: 12)
                    Circle().trim(from: 0, to: fraction)
                        .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.4), value: fraction)
                    VStack(spacing: 2) {
                        Text("\(Int(fraction * 100))%").font(.system(size: 32, weight: .bold)).contentTransition(.numericText())
                        Text(InstallCheck.progressLine(received: received, total: total)).font(.system(size: 12)).foregroundStyle(Theme.Colors.ink2)
                    }
                }
                .frame(width: 150, height: 150)
                Text(paused ? "Paused" : "Downloading the Chinese model").font(.system(size: 17, weight: .semibold))
                Text(paused ? "What has arrived is kept." : (InstallCheck.timeLeft(received: received, total: total, bytesPerSecond: models.rate) ?? "Working out the time left") + ". You can leave the app.")
                    .font(.system(size: 14)).foregroundStyle(Theme.Colors.ink2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
            Button { if paused { resume() } else { Task { await models.pause() } } } label: {
                Text(paused ? "Resume" : "Pause").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.Colors.accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
    }

    private var installed: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardSection(title: "中文") {
                CardRow(title: "Chinese model ready", subtitle: "\(InstallCheck.gigabytes(models.totalBytes, digits: 1)) · Works offline", icon: "checkmark", tint: Theme.Colors.verified)
                CardToggle(title: "Use it for Chinese", subtitle: "Apple's model is used when this is off",
                           isOn: Binding(get: { models.useForChinese }, set: { models.useForChinese = $0 }))
                ConfirmRow(title: "Delete Chinese model", subtitle: "Frees \(InstallCheck.gigabytes(models.totalBytes, digits: 1))",
                           question: "You can download it again later.", action: "Delete model") { Task { await models.delete() } }
            }
            CardSection(title: "Try it", note: trial == nil ? "A built-in sample paragraph, not one of your documents. The first run also loads the model, which takes a few seconds." : nil) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(ModelTrial.sample).font(.system(size: 15)).foregroundStyle(Theme.Colors.ink2).lineLimit(trial == nil ? 4 : 2)
                    if let trial {
                        Text(trial).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.Colors.verified)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                Button { Task { await runTrial() } } label: {
                    HStack(spacing: 8) {
                        if trying { ProgressView() }
                        Text(trying ? "Summarising" : (trial == nil ? "Summarise this paragraph" : "Run again"))
                    }
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.Colors.accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .disabled(trying)
            }
        }
    }

    private func resume() {
        let cellular = UserDefaults.standard.bool(forKey: "mlx.allowCellular")
        Task { await models.download(allowCellular: cellular) }
    }

    private func runTrial() async {
        trying = true
        defer { trying = false }
        let t0 = Date()
        do {
            let s = try await MLXSummarizer.pass(text: ModelTrial.sample, language: "zh-Hans", format: .paragraph, length: .short)
            let seconds = Int(Date().timeIntervalSince(t0).rounded())
            trial = "摘要：" + (s.body.isEmpty ? s.headline : s.body.joined()) + "  (\(seconds) s)"
        } catch {
            trial = "Could not run the model on this iPhone. Apple's model will keep doing Chinese summaries."
        }
    }
}
