import SwiftUI
import Foundation
import Network

// MARK: - Stats Actor
actor StatsActor {
    var sent = 0; var ok = 0; var fail = 0
    var latencies: [Double] = []
    var rpsHistory: [Double] = []
    var lastSecondCount = 0
    var lastTick = Date()

    func record(latency: Double, ok isOk: Bool) {
        sent += 1
        if isOk { ok += 1 } else { fail += 1 }
        if latency > 0 { latencies.append(latency) }
        lastSecondCount += 1
        let now = Date()
        if now.timeIntervalSince(lastTick) >= 1.0 {
            rpsHistory.append(Double(lastSecondCount))
            if rpsHistory.count > 30 { rpsHistory.removeFirst() }
            lastSecondCount = 0
            lastTick = now
        }
    }

    func get() -> (sent: Int, ok: Int, fail: Int, avg: Double, min: Double, max: Double, rps: Double, rpsHistory: [Double]) {
        let avg = latencies.isEmpty ? 0 : latencies.reduce(0,+) / Double(latencies.count)
        let mn = latencies.min() ?? 0
        let mx = latencies.max() ?? 0
        let rps = rpsHistory.last ?? 0
        return (sent, ok, fail, avg, mn, mx, rps, rpsHistory)
    }
}

// MARK: - Attack Mode
enum AttackMode: String, CaseIterable {
    case http = "HTTP"
    case slowloris = "SLOW"
    case ping = "PING"

    var icon: String {
        switch self {
        case .http: return "bolt.fill"
        case .slowloris: return "tortoise.fill"
        case .ping: return "dot.radiowaves.left.and.right"
        }
    }
    var description: String {
        switch self {
        case .http: return "HTTP FLOOD"
        case .slowloris: return "SLOWLORIS"
        case .ping: return "ICMP PING"
        }
    }
}

enum PowerPreset: String, CaseIterable {
    case low = "LOW"
    case mid = "MID"
    case high = "HIGH"
    case nuke = "NUKE"

    var color: Color {
        switch self {
        case .low: return .cyan
        case .mid: return .green
        case .high: return .orange
        case .nuke: return .red
        }
    }
    var threads: Int {
        switch self {
        case .low: return 5
        case .mid: return 20
        case .high: return 50
        case .nuke: return 100
        }
    }
    var delay: Int {
        switch self {
        case .low: return 50
        case .mid: return 10
        case .high: return 2
        case .nuke: return 0
        }
    }
    var requests: Int {
        switch self {
        case .low: return 200
        case .mid: return 1000
        case .high: return 5000
        case .nuke: return 99999
        }
    }
}

// MARK: - Main View
struct ContentView: View {
    @State private var target = ""
    @State private var requests = "1000"
    @State private var delay = "10"
    @State private var threads = "20"
    @State private var method = "GET"
    @State private var mode: AttackMode = .http
    @State private var power: PowerPreset = .mid
    @State private var running = false
    @State private var sent = 0
    @State private var success = 0
    @State private var failed = 0
    @State private var avgLatency = 0.0
    @State private var minLatency = 0.0
    @State private var maxLatency = 0.0
    @State private var currentRPS = 0.0
    @State private var rpsHistory: [Double] = Array(repeating: 0, count: 30)
    @State private var tasks: [Task<Void, Never>] = []
    @State private var pulse = false
    @State private var glitch = false
    @State private var scanLine: CGFloat = 0
    @State private var showAdvanced = false
    @State private var nukeShake = false
    @State private var startTime: Date? = nil
    @State private var elapsed = 0.0
    @State private var timer: Timer? = nil
    @State private var randomNoise: [CGFloat] = (0..<20).map { _ in CGFloat.random(in: 0...1) }

    let methods = ["GET", "POST", "HEAD", "PUT"]

    var progress: Double {
        let total = Double(Int(requests) ?? 1)
        return min(Double(sent) / total, 1.0)
    }

    var successRate: Double {
        guard sent > 0 else { return 0 }
        return Double(success) / Double(sent) * 100
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            gridBackground
            scanlineEffect

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    modeSelector
                    powerSelector
                    targetSection
                    statsGrid
                    rpsChart
                    if showAdvanced { advancedSection }
                    fireButton
                    Spacer(minLength: 40)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            pulse = true
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                scanLine = 1
            }
        }
    }

    // MARK: - Background
    var gridBackground: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 28
            var x: CGFloat = 0
            while x < size.width {
                var p = Path(); p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: size.height))
                ctx.stroke(p, with: .color(.white.opacity(0.03)), lineWidth: 1)
                x += spacing
            }
            var y: CGFloat = 0
            while y < size.height {
                var p = Path(); p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y))
                ctx.stroke(p, with: .color(.white.opacity(0.03)), lineWidth: 1)
                y += spacing
            }
        }
        .ignoresSafeArea()
    }

    var scanlineEffect: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear, .white.opacity(0.015), .clear],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(height: 80)
                .offset(y: scanLine * geo.size.height - 40)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Header
    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("STRESSKIT")
                        .font(.system(size: 26, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .offset(x: glitch ? CGFloat.random(in: -2...2) : 0)
                    if running {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(power.color)
                    }
                }
                Text("NETWORK STRESS TESTER v2.0")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if running {
                    Text(timeString(elapsed))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(power.color)
                }
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        showAdvanced.toggle()
                    }
                } label: {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 20))
                        .foregroundColor(showAdvanced ? power.color : .white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 64)
        .padding(.bottom, 20)
        .onChange(of: running) { r in
            if r {
                withAnimation(.easeInOut(duration: 0.05).repeatCount(3)) { glitch = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { glitch = false }
            }
        }
    }

    // MARK: - Mode Selector
    var modeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ATTACK MODE")
            HStack(spacing: 8) {
                ForEach(AttackMode.allCases, id: \.self) { m in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { mode = m }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: m.icon)
                                .font(.system(size: 18))
                            Text(m.description)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(mode == m ? .black : .white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(mode == m ? power.color : Color.white.opacity(0.04))
                        .overlay(
                            Rectangle()
                                .stroke(mode == m ? power.color : Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    // MARK: - Power Selector
    var powerSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("POWER PRESET")
            HStack(spacing: 6) {
                ForEach(PowerPreset.allCases, id: \.self) { p in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            power = p
                            threads = "\(p.threads)"
                            delay = "\(p.delay)"
                            requests = "\(p.requests)"
                        }
                        if p == .nuke {
                            withAnimation(.default) { nukeShake = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { nukeShake = false }
                        }
                    } label: {
                        Text(p.rawValue)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(power == p ? .black : p.color.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(power == p ? p.color : p.color.opacity(0.08))
                            .overlay(Rectangle().stroke(p.color.opacity(power == p ? 0 : 0.3), lineWidth: 1))
                    }
                    .scaleEffect(power == p ? 1.02 : 1.0)
                }
            }
            .offset(x: nukeShake ? CGFloat.random(in: -4...4) : 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    // MARK: - Target
    var targetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("TARGET")
            HStack(spacing: 0) {
                Text(mode == .ping ? "HOST  " : "URL   ")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(power.color.opacity(0.7))
                TextField(mode == .ping ? "192.168.1.1" : "https://example.com", text: $target)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .keyboardType(mode == .ping ? .numbersAndPunctuation : .URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .overlay(
                Rectangle().stroke(running ? power.color.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1)
            )

            // progress bar
            ZStack(alignment: .leading) {
                Rectangle().foregroundColor(.white.opacity(0.04)).frame(height: 2)
                Rectangle()
                    .foregroundColor(power.color)
                    .frame(width: UIScreen.main.bounds.width * 0.88 * progress, height: 2)
                    .animation(.linear(duration: 0.1), value: progress)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Stats
    var statsGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                BigStat(label: "SENT", value: formatNum(sent), color: .white, accent: power.color)
                BigStat(label: "RPS", value: String(format: "%.0f", currentRPS), color: power.color, accent: power.color)
            }
            HStack(spacing: 8) {
                SmallStat(label: "OK", value: "\(success)", color: .green)
                SmallStat(label: "FAIL", value: "\(failed)", color: .red.opacity(0.8))
                SmallStat(label: "AVG ms", value: avgLatency > 0 ? String(format: "%.0f", avgLatency) : "--", color: .cyan)
                SmallStat(label: "RATE %", value: sent > 0 ? String(format: "%.0f", successRate) : "--", color: .yellow)
            }
            HStack(spacing: 8) {
                SmallStat(label: "MIN ms", value: minLatency > 0 ? String(format: "%.0f", minLatency) : "--", color: .white.opacity(0.5))
                SmallStat(label: "MAX ms", value: maxLatency > 0 ? String(format: "%.0f", maxLatency) : "--", color: .white.opacity(0.5))
                SmallStat(label: "THREADS", value: threads, color: .white.opacity(0.5))
                SmallStat(label: "ELAPSED", value: sent > 0 ? timeString(elapsed) : "--", color: .white.opacity(0.5))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    // MARK: - RPS Chart
    var rpsChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("RPS HISTORY")
            GeometryReader { geo in
                let maxVal = rpsHistory.max() ?? 1
                let w = geo.size.width / CGFloat(rpsHistory.count)
                ZStack(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.02)).frame(maxWidth: .infinity, maxHeight: .infinity)
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(Array(rpsHistory.enumerated()), id: \.offset) { i, v in
                            let h = maxVal > 0 ? CGFloat(v / maxVal) * geo.size.height : 0
                            Rectangle()
                                .fill(power.color.opacity(0.6 + 0.4 * CGFloat(v / max(maxVal, 1))))
                                .frame(width: max(w - 2, 2), height: max(h, 1))
                                .animation(.easeOut(duration: 0.2), value: v)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 2)
                }
            }
            .frame(height: 60)
            .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    // MARK: - Advanced
    var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("ADVANCED")
            HStack(spacing: 10) {
                ForEach(methods, id: \.self) { m in
                    Button {
                        withAnimation { method = m }
                    } label: {
                        Text(m)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(method == m ? .black : .white.opacity(0.4))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(method == m ? power.color : Color.white.opacity(0.04))
                            .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 1))
                    }
                }
            }
            HStack(spacing: 10) {
                FieldView(label: "THREADS", text: $threads, kb: .numberPad)
                FieldView(label: "DELAY MS", text: $delay, kb: .numberPad)
                FieldView(label: "REQUESTS", text: $requests, kb: .numberPad)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Fire Button
    var fireButton: some View {
        Button {
            running ? stop() : start()
        } label: {
            ZStack {
                if running {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(power.color.opacity(0.15), lineWidth: 1)
                            .frame(width: CGFloat(80 + i * 24), height: CGFloat(80 + i * 24))
                            .scaleEffect(pulse ? 1.3 : 1.0)
                            .opacity(pulse ? 0 : 0.5)
                            .animation(
                                .easeOut(duration: 1.2 + Double(i) * 0.3)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.2),
                                value: pulse
                            )
                    }
                }
                Circle()
                    .fill(running ? Color.black : power.color)
                    .frame(width: 80, height: 80)
                    .overlay(Circle().stroke(running ? power.color : .clear, lineWidth: 2))
                VStack(spacing: 4) {
                    Image(systemName: running ? "stop.fill" : mode.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(running ? power.color : .black)
                    Text(running ? "STOP" : "FIRE")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(running ? power.color : .black)
                }
            }
        }
        .padding(.vertical, 20)
    }

    // MARK: - Logic
    func start() {
        guard !target.isEmpty else { return }
        let threadCount = Int(threads) ?? 20
        let delayMs = UInt64(Int(delay) ?? 0) * 1_000_000
        let total = Int(requests) ?? 1000
        sent = 0; success = 0; failed = 0; avgLatency = 0
        minLatency = 0; maxLatency = 0; currentRPS = 0
        rpsHistory = Array(repeating: 0, count: 30)
        startTime = Date(); elapsed = 0
        withAnimation { running = true }

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            elapsed = Date().timeIntervalSince(startTime ?? Date())
        }

        let statsActor = StatsActor()
        let perThread = max(total / threadCount, 1)
        let capturedTarget = target
        let capturedMethod = method
        let capturedMode = mode

        for _ in 0..<threadCount {
            let t = Task {
                switch capturedMode {
                case .http, .slowloris:
                    await runHTTP(url: capturedTarget, count: perThread, delayNs: delayMs,
                                  method: capturedMethod, slow: capturedMode == .slowloris, actor: statsActor)
                case .ping:
                    await runPing(host: capturedTarget, count: perThread, delayNs: delayMs, actor: statsActor)
                }
            }
            tasks.append(t)
        }

        Task {
            for t in tasks { await t.value }
            await MainActor.run {
                withAnimation { running = false }
                timer?.invalidate()
            }
        }

        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                let s = await statsActor.get()
                await MainActor.run {
                    sent = s.sent; success = s.ok; failed = s.fail
                    avgLatency = s.avg; minLatency = s.min; maxLatency = s.max
                    currentRPS = s.rps
                    if s.rpsHistory.count > 0 {
                        rpsHistory = Array(s.rpsHistory.suffix(30))
                        while rpsHistory.count < 30 { rpsHistory.insert(0, at: 0) }
                    }
                }
                if !running { break }
            }
        }
    }

    func runHTTP(url: String, count: Int, delayNs: UInt64, method: String, slow: Bool, actor: StatsActor) async {
        guard let u = URL(string: url) else { return }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = slow ? 60 : 10
        config.httpMaximumConnectionsPerHost = 6
        let session = URLSession(configuration: config)
        for _ in 0..<count {
            if Task.isCancelled { break }
            var req = URLRequest(url: u)
            req.httpMethod = method
            if slow {
                req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
                req.setValue("keep-alive", forHTTPHeaderField: "Connection")
                req.setValue("bytes=0-", forHTTPHeaderField: "Range")
            }
            let t0 = Date()
            do {
                let (_, resp) = try await session.data(for: req)
                let ms = Date().timeIntervalSince(t0) * 1000
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                await actor.record(latency: ms, ok: code < 500)
            } catch {
                await actor.record(latency: 0, ok: false)
            }
            if delayNs > 0 { try? await Task.sleep(nanoseconds: delayNs) }
        }
    }

    func runPing(host: String, count: Int, delayNs: UInt64, actor: StatsActor) async {
        // ICMP недоступен без entitlements в sandboxed app
        // используем TCP connect на порт 80 как замену ping
        for _ in 0..<count {
            if Task.isCancelled { break }
            let t0 = Date()
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: 80,
                using: .tcp
            )
            await withCheckedContinuation { cont in
                var done = false
                connection.stateUpdateHandler = { state in
                    guard !done else { return }
                    switch state {
                    case .ready, .failed, .cancelled:
                        done = true
                        let ms = Date().timeIntervalSince(t0) * 1000
                        Task { await actor.record(latency: ms, ok: state == .ready) }
                        connection.cancel()
                        cont.resume()
                    default: break
                    }
                }
                connection.start(queue: .global())
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    guard !done else { return }
                    done = true
                    Task { await actor.record(latency: 0, ok: false) }
                    connection.cancel()
                    cont.resume()
                }
            }
            if delayNs > 0 { try? await Task.sleep(nanoseconds: delayNs) }
        }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        timer?.invalidate()
        withAnimation { running = false }
    }

    func timeString(_ t: Double) -> String {
        let s = Int(t) % 60
        let m = Int(t) / 60
        return String(format: "%02d:%02d", m, s)
    }

    func formatNum(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fK", Double(n)/1000) }
        return "\(n)"
    }

    func sectionLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(.white.opacity(0.25))
    }
}

// MARK: - Subviews
struct BigStat: View {
    let label: String; let value: String; let color: Color; let accent: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 36, weight: .black, design: .monospaced))
                .foregroundColor(color)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.03))
        .overlay(Rectangle().stroke(accent.opacity(0.15), lineWidth: 1))
    }
}

struct SmallStat: View {
    let label: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundColor(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.02))
        .overlay(Rectangle().stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

struct FieldView: View {
    let label: String
    @Binding var text: String
    var kb: UIKeyboardType = .default
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
            TextField("", text: $text)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .keyboardType(kb)
                .padding(8)
                .background(Color.white.opacity(0.04))
                .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }
}
