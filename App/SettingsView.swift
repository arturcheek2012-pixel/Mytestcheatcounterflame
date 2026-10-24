import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("res") private var res = "Native"
    @AppStorage("fps") private var fps = 60
    @AppStorage("showfps") private var showFPS = false
    @AppStorage("tex") private var tex = "High"
    @AppStorage("aa") private var aa = "Off"
    @AppStorage("vol") private var vol = 100
    @AppStorage("sens") private var sens = 5
    @AppStorage("console") private var console = true
    @AppStorage("extra") private var extra = ""

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Settings")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(T.text)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18))
                            .frame(width: 44, height: 44)
                            .background(T.panel)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(T.text)
                }
                .padding(16)

                ScrollView {
                    VStack(spacing: 2) {
                        Header("Video")
                        MenuRow(title: "Resolution", options: Cfg.resolutions, selection: $res)
                        StepRow(title: "FPS limit", value: $fps, range: 30...120, step: 30)
                        MenuRow(title: "Texture quality", options: Cfg.quality, selection: $tex)
                        MenuRow(title: "Anti-aliasing", options: Cfg.aa, selection: $aa)
                        ToggleRow(title: "Show FPS", on: $showFPS)

                        Header("Controls and audio")
                        StepRow(title: "Look sensitivity", value: $sens, range: 1...20, step: 1)
                        StepRow(title: "Volume", value: $vol, range: 0...100, step: 10, suffix: "%")

                        Header("Advanced")
                        ToggleRow(title: "Developer console", on: $console)
                        TextRow(title: "Extra arguments", text: $extra)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
