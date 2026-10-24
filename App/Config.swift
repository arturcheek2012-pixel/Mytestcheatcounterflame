import UIKit

enum Cfg {
    static let resolutions = ["Native", "960x540", "1280x720", "1600x720", "1920x1080"]
    static let quality = ["High", "Medium", "Low"]
    static let aa = ["Off", "2x", "4x"]

    static func int(_ k: String, _ d: Int) -> Int {
        UserDefaults.standard.object(forKey: k) == nil ? d : UserDefaults.standard.integer(forKey: k)
    }
    static func str(_ k: String, _ d: String) -> String {
        UserDefaults.standard.string(forKey: k) ?? d
    }
    static func bool(_ k: String, _ d: Bool) -> Bool {
        UserDefaults.standard.object(forKey: k) == nil ? d : UserDefaults.standard.bool(forKey: k)
    }

    static func resolution() -> (Int, Int) {
        let r = str("res", "Native")
        let p = r.split(separator: "x").compactMap { Int($0) }
        if p.count == 2 { return (p[0], p[1]) }
        let b = UIScreen.main.nativeBounds
        return (Int(max(b.width, b.height)), Int(min(b.width, b.height)))
    }

    static func args() -> [String] {
        let (w, h) = resolution()
        var a = ["css", "-game", "cstrike", "-w", "\(w)", "-h", "\(h)"]
        if bool("console", true) { a.append("-console") }
        a += ["+fps_max", "\(int("fps", 60))"]
        if bool("showfps", false) { a += ["+cl_showfps", "1"] }
        a += ["+mat_picmip", "\(quality.firstIndex(of: str("tex", "High")) ?? 0)"]
        let aaIdx = aa.firstIndex(of: str("aa", "Off")) ?? 0
        a += ["+mat_antialias", "\([0, 2, 4][aaIdx])"]
        a += ["+volume", String(format: "%.1f", Double(int("vol", 100)) / 100)]
        a += ["+sensitivity", String(format: "%.1f", Double(int("sens", 5)) / 2)]
        a += str("extra", "").split(separator: " ").map(String.init)
        return a
    }
}

enum Game {
    static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var root: URL { docs.appendingPathComponent("game") }

    static func prepare() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    static var hasFiles: Bool {
        var d: ObjCBool = false
        let fm = FileManager.default
        let cs = fm.fileExists(atPath: root.appendingPathComponent("cstrike").path, isDirectory: &d) && d.boolValue
        let hl = fm.fileExists(atPath: root.appendingPathComponent("hl2").path, isDirectory: &d) && d.boolValue
        return cs && hl
    }

    static func linkBin() throws {
        let fm = FileManager.default
        let link = root.appendingPathComponent("bin")
        try? fm.removeItem(at: link)
        try fm.createSymbolicLink(at: link, withDestinationURL: Bundle.main.bundleURL.appendingPathComponent("bin"))
    }
}
