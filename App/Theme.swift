import SwiftUI

enum T {
    static let bg = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let panel = Color(red: 0.11, green: 0.11, blue: 0.11)
    static let text = Color(red: 0.85, green: 0.85, blue: 0.85)
    static let dim = Color(red: 0.50, green: 0.50, blue: 0.50)
    static let yellow = Color(red: 0.95, green: 0.72, blue: 0.0)
    static let ok = Color(red: 0.35, green: 0.55, blue: 0.35)
    static let bad = Color(red: 0.65, green: 0.30, blue: 0.30)
}

struct Row<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        HStack {
            Text(title).foregroundColor(T.text)
            Spacer()
            content
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(T.panel)
    }
}

struct MenuRow: View {
    let title: String
    let options: [String]
    @Binding var selection: String
    var body: some View {
        Row(title) {
            Menu {
                ForEach(options, id: \.self) { o in Button(o) { selection = o } }
            } label: {
                Text(selection).foregroundColor(T.yellow)
            }
        }
    }
}

struct StepRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    var suffix = ""
    var body: some View {
        Row(title) {
            HStack(spacing: 2) {
                sq("minus") { value = max(range.lowerBound, value - step) }
                Text("\(value)\(suffix)")
                    .frame(width: 70)
                    .foregroundColor(T.text)
                sq("plus") { value = min(range.upperBound, value + step) }
            }
        }
    }
    func sq(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 32, height: 32)
                .background(T.bg)
        }
        .buttonStyle(.plain)
        .foregroundColor(T.text)
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var on: Bool
    var body: some View {
        Row(title) {
            Button { on.toggle() } label: {
                ZStack(alignment: on ? .trailing : .leading) {
                    Rectangle().fill(on ? T.yellow : T.dim.opacity(0.4))
                        .frame(width: 44, height: 22)
                    Rectangle().fill(T.bg)
                        .frame(width: 16, height: 16)
                        .padding(3)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct TextRow: View {
    let title: String
    @Binding var text: String
    var body: some View {
        Row(title) {
            TextField("", text: $text)
                .multilineTextAlignment(.trailing)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .foregroundColor(T.yellow)
        }
    }
}

struct Header: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(T.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }
}
