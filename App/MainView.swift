import SwiftUI

struct MainView: View {
    @State private var showSettings = false
    @State private var hasFiles = false
    @State private var error = ""
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack {
            T.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Counter-Strike: Source")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(T.text)
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20))
                            .frame(width: 44, height: 44)
                            .background(T.panel)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(T.text)
                }
                .padding(16)

                Spacer(minLength: 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Rectangle().fill(hasFiles ? T.ok : T.bad).frame(width: 10, height: 10)
                            Text(hasFiles ? "GAME FILES FOUND" : "GAME FILES NOT FOUND")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(T.text)
                            Spacer()
                        }
                        .padding(14)
                        .background(T.panel)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("HOW TO ADD GAME FILES")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(T.dim)
                            step("1", "Open the Files app.")
                            step("2", "Go to On My iPhone > CS:Source > game.")
                            step("3", "Copy the folders cstrike and hl2 from your Android game files into game.")
                            step("4", "Return here and tap Launch Game.")
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(T.panel)
                    }
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 8)

                if !error.isEmpty {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(T.bad)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                Button(action: launch) {
                    Text("LAUNCH GAME")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(T.yellow)
                }
                .buttonStyle(.plain)
                .disabled(!hasFiles)
                .opacity(hasFiles ? 1 : 0.35)
                .padding(16)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear { Game.prepare(); hasFiles = Game.hasFiles }
        .onChange(of: phase) { _ in hasFiles = Game.hasFiles }
    }

    func step(_ n: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).foregroundColor(T.yellow).font(.system(size: 14, weight: .bold))
            Text(t).foregroundColor(T.text).font(.system(size: 14))
        }
    }

    func launch() {
        error = ""
        do { try Game.linkBin() } catch {
            self.error = "bin link: \(error.localizedDescription)"
            return
        }
        DispatchQueue.main.async {
            var cargs = Cfg.args().map { strdup($0) }
            let code = css_run(Game.root.path, Int32(cargs.count), &cargs)
            cargs.forEach { free($0) }
            if code == -1 { error = String(cString: css_last_error()) }
        }
    }
}
