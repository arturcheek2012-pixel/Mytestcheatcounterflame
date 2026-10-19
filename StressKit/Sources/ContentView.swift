import SwiftUI
import Foundation

struct ContentView: View {
    @State private var target = ""
    @State private var requests = "500"
    @State private var delay = "10"
    @State private var running = false
    @State private var sent = 0
    @State private var success = 0
    @State private var failed = 0
    @State private var avgLatency = 0.0
    @State private var latencies: [Double] = []
    @State private var tasks: [Task<Void, Never>] = []
    @State private var pulse = false
    @State private var showSettings = false
    @State private var threads = "10"
    @State private var method = "GET"

    let methods = ["GET", "POST", "HEAD"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                Canvas { ctx, size in
                    let spacing: CGFloat = 32
                    var x: CGFloat = 0
                    while x < size.width {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(path, with: .color(.white.opacity(0.04)), lineWidth: 1)
                        x += spacing
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(path, with: .color(.white.opacity(0.04)), lineWidth: 1)
                        y += spacing
                    }
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("STRESSKIT")
                            .font(.system(size: 22, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                        Text("HTTP LOAD TESTER")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            showSettings.toggle()
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(showSettings ? .green : .white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 24)

                if showSettings {
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            ForEach(methods, id: \.self) { m in
                                Button {
                                    withAnimation { method = m }
                                } label: {
                                    Text(m)
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(method == m ? .black : .white.opacity(0.5))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(method == m ? Color.green : Color.white.opacity(0.05))
                                }
                            }
                        }
                        HStack(spacing: 12) {
                            FieldView(label: "THREADS", text: $threads, kb: .numberPad)
                            FieldView(label: "DELAY MS", text: $delay, kb: .numberPad)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("TARGET")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                    TextField("https://example.com", text: $target)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .padding(14)
                        .background(Color.white.opacity(0.05))
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(running ? .green.opacity(0.8) : .white.opacity(0.1)),
                            alignment: .bottom
                        )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

                VStack(alignment: .leading, spacing: 6) {
                    Text("REQUESTS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                    TextField("500", text: $requests)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .keyboardType(.numberPad)
                        .padding(14)
                        .background(Color.white.opacity(0.05))
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(.white.opacity(0.1)),
                            alignment: .bottom
                        )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)

                HStack(spacing: 0) {
                    StatBox(label: "SENT", value: "\(sent)", color: .white)
                    StatBox(label: "OK", value: "\(success)", color: .green)
                    StatBox(label: "FAIL", value: "\(failed)", color: .red.opacity(0.8))
                    StatBox(label: "AVG MS", value: avgLatency > 0 ? String(format: "%.0f", avgLatency) : "--", color: .cyan)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)

                if running {
                    let total = Double(Int(requests) ?? 1)
                    let progress = min(Double(sent) / total, 1.0)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .foregroundColor(.white.opacity(0.05))
                                .frame(height: 2)
                            Rectangle()
                                .foregroundColor(.green)
                                .frame(width: geo.size.width * progress, height: 2)
                                .animation(.linear(duration: 0.1), value: progress)
                        }
                    }
                    .frame(height: 2)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .transition(.opacity)
                }

                Spacer()

                Button {
                    running ? stop() : start()
                } label: {
                    ZStack {
                        if running {
                            Circle()
                                .stroke(Color.green.opacity(0.2), lineWidth: 1)
                                .frame(width: 88, height: 88)
                                .scaleEffect(pulse ? 1.4 : 1.0)
                                .opacity(pulse ? 0 : 0.6)
                                .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: pulse)
                        }
                        Circle()
                            .foregroundColor(running ? Color.white.opacity(0.05) : Color.green)
                            .frame(width: 72, height: 72)
                        Image(systemName: running ? "stop.fill" : "bolt.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(running ? .green : .black)
                    }
                }
                .padding(.bottom, 60)
                .onAppear { pulse = true }
            }
        }
        .preferredColorScheme(.dark)
    }

    func start() {
        guard let url = URL(string: target), let total = Int(requests), total > 0 else { return }
        let threadCount = Int(threads) ?? 10
        let delayMs = UInt64(Int(delay) ?? 10) * 1_000_000
        sent = 0; success = 0; failed = 0; avgLatency = 0; latencies = []
        withAnimation { running = true }

        let actor = StatsActor()
        let perThread = total / threadCount

        for _ in 0..<threadCount {
            let t = Task {
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 10
                let session = URLSession(configuration: config)
                for _ in 0..<perThread {
                    if Task.isCancelled { break }
                    var req = URLRequest(url: url)
                    req.httpMethod = method
                    let t0 = Date()
                    do {
                        let (_, resp) = try await session.data(for: req)
                        let ms = Date().timeIntervalSince(t0) * 1000
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                        await actor.record(latency: ms, ok: code < 400)
                    } catch {
                        await actor.record(latency: 0, ok: false)
                    }
                    let stats = await actor.get()
                    await MainActor.run {
                        sent = stats.sent
                        success = stats.ok
                        failed = stats.fail
                        avgLatency = stats.avg
                    }
                    if delayMs > 0 { try? await Task.sleep(nanoseconds: delayMs) }
                }
            }
            tasks.append(t)
        }

        Task {
            for t in tasks { await t.value }
            await MainActor.run { withAnimation { running = false } }
        }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        withAnimation { running = false }
    }
}

actor StatsActor {
    var sent = 0; var ok = 0; var fail = 0; var latencies: [Double] = []
    func record(latency: Double, ok isOk: Bool) {
        sent += 1
        if isOk { ok += 1 } else { fail += 1 }
        if latency > 0 { latencies.append(latency) }
    }
    func get() -> (sent: Int, ok: Int, fail: Int, avg: Double) {
        let avg = latencies.isEmpty ? 0 : latencies.reduce(0,+) / Double(latencies.count)
        return (sent, ok, fail, avg)
    }
}

struct StatBox: View {
    let label: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundColor(color)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity)
    }
}

struct FieldView: View {
    let label: String
    @Binding var text: String
    var kb: UIKeyboardType = .default
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
            TextField("", text: $text)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .keyboardType(kb)
                .padding(10)
                .background(Color.white.opacity(0.05))
        }
    }
}
