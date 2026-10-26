import SwiftUI
import UIKit

struct RotaryDial: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: String
    var color: Color = Palette.cream
    private var fraction: Double { (value - range.lowerBound) / (range.upperBound - range.lowerBound) }
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.7), radius: 5, x: 0, y: 4)
                ForEach(0..<41) { index in
                    Capsule().fill(index % 5 == 0 ? Palette.muted : Palette.muted.opacity(0.4))
                        .frame(width: index % 5 == 0 ? 2 : 1, height: index % 5 == 0 ? 8 : 4)
                        .offset(y: -37).rotationEffect(.degrees(-135 + Double(index) * 6.75))
                }
                Circle().fill(Palette.background).frame(width: 58, height: 58)
                    .overlay(Circle().stroke(.white.opacity(0.08), lineWidth: 1))
                Capsule().fill(color).frame(width: 3, height: 9).offset(y: -30)
                    .rotationEffect(.degrees(-135 + fraction * 270))
                Text(display).font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(Palette.cream)
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                let x = event.location.x - 44
                let y = 44 - event.location.y
                guard hypot(x, y) > 12 else { return }
                let angle = min(135, max(-135, atan2(x, y) * 180 / .pi))
                update(range.lowerBound + (angle + 135) / 270 * (range.upperBound - range.lowerBound))
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(display)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: update(value + step)
                case .decrement: update(value - step)
                @unknown default: break
                }
            }
            Text(title).font(.system(size: 10, weight: .medium)).tracking(0.4).foregroundStyle(Palette.muted)
                .lineLimit(1).minimumScaleFactor(0.75).frame(width: 88)
        }
    }
    private func update(_ next: Double) {
        let snapped = min(range.upperBound, max(range.lowerBound, (next / step).rounded() * step))
        guard snapped != value else { return }
        value = snapped
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

struct FilmRail: View {
    @Binding var selected: FilmStock
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(FilmStock.allCases) { film in
                    Button {
                        selected = film
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 2).fill(film.tint).frame(width: 6, height: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(film.name).font(.system(size: 13, weight: .semibold))
                                Text(film.code).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2)
                            }
                        }
                        .foregroundStyle(selected == film ? Palette.cream : Palette.muted)
                        .padding(.horizontal, 13).padding(.vertical, 12)
                        .background(selected == film ? Color(white: 0.19) : Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected == film ? film.tint.opacity(0.8) : .clear, lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected == film ? .isSelected : [])
                }
            }.padding(.horizontal, 20)
        }
    }
}

struct FilmFrame<Content: View>: View {
    var height: CGFloat
    var stock: FilmStock
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 6) {
            sprockets
            content.frame(maxWidth: .infinity).frame(height: height).clipped()
                .overlay(alignment: .bottomLeading) {
                    Text("AFTERGLOW  •  \(stock.code)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5)
                        .foregroundStyle(.white.opacity(0.85)).padding(12)
                        .shadow(color: .black, radius: 3)
                }
            sprockets
        }.padding(6).background(.black, in: RoundedRectangle(cornerRadius: 10))
    }
    private var sprockets: some View {
        VStack(spacing: 15) {
            ForEach(0..<Int(max(1, height / 25)), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2).fill(Palette.panel).frame(width: 6, height: 10)
            }
        }.frame(width: 6, height: height).clipped().accessibilityHidden(true)
    }
}

struct ActionButton: View {
    var title: String
    var icon: String
    var busy = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy { ProgressView().tint(Palette.background) }
                else { Image(systemName: icon) }
                Text(title).fontWeight(.semibold)
            }.frame(maxWidth: .infinity).padding(.vertical, 17)
                .foregroundStyle(Palette.background).background(Palette.cream, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
}


struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct PhotoShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
