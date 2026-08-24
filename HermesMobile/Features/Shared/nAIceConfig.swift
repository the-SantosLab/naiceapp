import SwiftUI

// MARK: - nAIce Colors
extension Color {
    static let ncCream = Color(red: 0.984, green: 0.957, blue: 0.886)
    static let ncPaper = Color(red: 1.0, green: 0.973, blue: 0.906)
    static let ncSand = Color(red: 0.910, green: 0.863, blue: 0.769)
    static let ncSage = Color(red: 0.541, green: 0.608, blue: 0.478)
    static let ncGreen = Color(red: 0.239, green: 0.353, blue: 0.278)
    static let ncGreenLight = Color(red: 0.353, green: 0.478, blue: 0.396)
    static let ncDark = Color(red: 0.102, green: 0.078, blue: 0.051)
    static let ncMuted = Color(red: 0.541, green: 0.510, blue: 0.439)
    static let ncRed = Color(red: 0.761, green: 0.231, blue: 0.231)
    static let ncGold = Color(red: 0.769, green: 0.635, blue: 0.396)
}

// MARK: - Warm Card Style
struct WarmCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ncPaper)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.ncSand.opacity(0.4), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.03), radius: 3, y: 1)
    }
}

extension View {
    func warmCard() -> some View { modifier(WarmCardStyle()) }
    func warmBackground() -> some View { self.background(Color.ncCream.ignoresSafeArea()) }
}

// MARK: - Section Label
struct NAIceSectionLabel: View {
    let icon: String
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundColor(.ncSage)
            Text(title).font(.caption.weight(.semibold)).foregroundColor(.ncSage).textCase(.uppercase)
        }
        .padding(.horizontal, 4)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }
}

// MARK: - Shared Helpers
func timeGreeting() -> String {
    let h = Calendar.current.component(.hour, from: Date())
    if h < 6 { return "Nachtruhe?" }
    if h < 9 { return "Guten Morgen!" }
    if h < 12 { return "Guten Vormittag!" }
    if h < 14 { return "Mittagspause?" }
    if h < 17 { return "Nachmittag!" }
    if h < 21 { return "Feierabend!" }
    return "Gute Nacht!"
}

func recoveryColor(_ s: Int) -> Color {
    s >= 67 ? .ncGreen : s >= 34 ? .ncGold : .ncRed
}

func wm(_ i: String, _ v: String, _ l: String) -> some View {
    VStack(spacing: 4) {
        Image(systemName: i).font(.caption).foregroundColor(.ncSage)
        Text(v).font(.caption.weight(.bold)).foregroundColor(.ncDark)
        Text(l).font(.system(size: 8)).foregroundColor(.ncMuted)
    }.frame(maxWidth: .infinity)
}

func mini(_ i: String, _ v: String, _ l: String) -> some View {
    VStack(spacing: 4) {
        Image(systemName: i).font(.caption).foregroundColor(.ncSage)
        Text(v).font(.caption.weight(.bold)).foregroundColor(.ncDark)
        Text(l).font(.caption2).foregroundColor(.ncMuted)
    }.frame(maxWidth: .infinity)
}

func legend(_ l: String, _ c: Color) -> some View {
    HStack(spacing: 3) {
        Circle().fill(c).frame(width: 6, height: 6)
        Text(l).font(.system(size: 9)).foregroundColor(.ncMuted)
    }
}

func area(_ icon: String, _ title: String, _ color: Color, _ dest: AnyView) -> some View {
    NavigationLink(destination: dest) {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundColor(color)
            Text(title).font(.caption.weight(.semibold)).foregroundColor(.ncDark)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .warmCard()
    }.buttonStyle(PlainButtonStyle())
}