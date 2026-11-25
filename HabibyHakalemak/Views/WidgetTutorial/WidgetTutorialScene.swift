//
//  WidgetTutorialScene.swift
//  Kelmteen
//

import SwiftUI

/// A looping mini Home Screen that shows how to add the Kelmteen widget:
/// touch and hold → Edit → Add Widget → Kelmteen → Add Widget → Done.
///
/// Everything is a pure function of `time`, so the same view drives the live animation
/// in the app and the frames of the Picture in Picture video (see `WidgetTutorialVideo`).
/// It's drawn at a fixed size and mirrors automatically in right-to-left languages.
struct WidgetTutorialScene: View {
    /// Seconds into the loop, from 0 up to `duration`.
    let time: Double
    /// The user's own color, used for the wallpaper.
    var wallpaper: Color = .sky

    static let duration = 16.0
    static let size = CGSize(width: 270, height: 480)

    // Key moments in the loop.
    private enum Moment {
        static let press = 1.0
        static let editing = 1.8
        static let tapEdit = 3.0
        static let menu = 3.3
        static let tapAddWidgetMenu = 4.3
        static let gallery = 4.5
        static let tapKelmteen = 6.1
        static let detail = 6.4
        static let tapAddWidget = 8.1
        static let placed = 8.4
        static let tapDone = 10.3
        static let finished = 10.6
    }

    var body: some View {
        ZStack {
            wallpaperView
            iconGrid
            placedWidget
            editingButtons
            menu
            sheet
            caption
            finger
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
        // Fade in and out so the loop restarts smoothly.
        .opacity(min(ramp(0, 0.3), 1 - ramp(Self.duration - 0.5, Self.duration)))
        .background(Color.black)
    }

    // MARK: Home Screen

    private var isEditing: Bool { time >= Moment.editing && time < Moment.tapDone }

    private var wallpaperView: some View {
        LinearGradient(
            colors: [wallpaper, wallpaper.mix(with: .white, by: 0.45)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// App icons laid out in a 4-column grid. The top-leading 2×2 block stays empty:
    /// that's where the finger presses and where the widget lands.
    private var iconGrid: some View {
        ZStack {
            ForEach(Self.iconSlots.indices, id: \.self) { index in
                let slot = Self.iconSlots[index]
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.white.opacity(0.55))
                    .frame(width: 46, height: 46)
                    .rotationEffect(.degrees(isEditing ? sin(time * 28 + Double(index)) * 2.5 : 0))
                    .position(slot)
            }
            // Dock
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.white.opacity(0.35))
                .frame(width: 250, height: 66)
                .position(x: 135, y: 440)
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.white.opacity(0.7))
                    .frame(width: 46, height: 46)
                    .rotationEffect(.degrees(isEditing ? sin(time * 28 + Double(index) * 1.7) * 2.5 : 0))
                    .position(x: 45 + Double(index) * 60, y: 440)
            }
        }
    }

    private static let iconSlots: [CGPoint] = {
        let columns: [Double] = [45, 105, 165, 225]
        let rows: [Double] = [90, 165, 240, 315]
        var slots: [CGPoint] = []
        for (row, y) in rows.enumerated() {
            for (column, x) in columns.enumerated() where !(row < 2 && column < 2) {
                slots.append(CGPoint(x: x, y: y))
            }
        }
        return slots
    }()

    /// The Kelmteen widget, landing in the empty 2×2 block.
    private var placedWidget: some View {
        let appear = easeOutBack(ramp(Moment.placed + 0.2, Moment.placed + 0.8))
        return MiniWidget()
            .frame(width: 106, height: 106)
            .rotationEffect(.degrees(isEditing ? sin(time * 28) * 1.5 : 0))
            .scaleEffect(0.6 + 0.4 * appear)
            .opacity(time >= Moment.placed + 0.2 ? 1 : 0)
            .position(x: 75, y: 128)
    }

    private var editingButtons: some View {
        let visible = isEditing ? 1.0 : 0.0
        return ZStack {
            Text("Edit")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.white.opacity(0.85), in: .capsule)
                .position(x: 36, y: 30)
            Text("Done")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.white.opacity(0.85), in: .capsule)
                .position(x: 230, y: 30)
        }
        .foregroundStyle(.black)
        .opacity(visible)
    }

    private var menu: some View {
        let shown = time >= Moment.menu && time < Moment.gallery
        return VStack(alignment: .leading, spacing: 0) {
            Label("Add Widget", systemImage: "plus.square.on.square")
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(time >= Moment.tapAddWidgetMenu ? Color.black.opacity(0.08) : .clear)
            Divider()
            Label("Customize", systemImage: "paintbrush")
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.black)
        .frame(width: 150, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .scaleEffect(shown ? 1 : 0.8, anchor: .topLeading)
        .opacity(shown ? 1 : 0)
        .position(x: 92, y: 82)
    }

    // MARK: Widget gallery sheet

    private var sheet: some View {
        let rise = ramp(Moment.gallery, Moment.gallery + 0.5)
        let fall = ramp(Moment.placed, Moment.placed + 0.5)
        let offset = 340 * (1 - smooth(rise)) + 340 * smooth(fall)
        let showsDetail = time >= Moment.detail

        return VStack(spacing: 12) {
            Capsule().fill(.black.opacity(0.2)).frame(width: 36, height: 5)
            if showsDetail {
                galleryDetail
            } else {
                galleryList
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.horizontal, 14)
        .frame(width: Self.size.width, height: 330)
        .background(Color(white: 0.96), in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .position(x: Self.size.width / 2, y: 480 - 165 + offset)
    }

    private var galleryList: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                Text("Search Widgets")
                Spacer()
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(8)
            .background(.black.opacity(0.06), in: .capsule)

            HStack(spacing: 10) {
                AppIconMini()
                Text("Kelmteen")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                Spacer()
            }
            .padding(8)
            .background(time >= Moment.tapKelmteen ? Color.black.opacity(0.08) : .white,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.black.opacity(0.12))
                        .frame(width: 30, height: 30)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.black.opacity(0.1))
                        .frame(width: 80, height: 10)
                    Spacer()
                }
                .padding(8)
                .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var galleryDetail: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                AppIconMini()
                Text("Kelmteen")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
            }
            MiniWidget()
                .frame(width: 120, height: 120)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            HStack(spacing: 5) {
                Circle().fill(.black.opacity(0.5)).frame(width: 6, height: 6)
                Circle().fill(.black.opacity(0.2)).frame(width: 6, height: 6)
                Circle().fill(.black.opacity(0.2)).frame(width: 6, height: 6)
            }
            Label("Add Widget", systemImage: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 26)
                .padding(.vertical, 11)
                .background(Color(red: 0, green: 0.48, blue: 1)
                    .opacity(time >= Moment.tapAddWidget ? 0.7 : 1), in: .capsule)
        }
    }

    // MARK: Caption

    private var caption: some View {
        Text(captionText)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: 240)
            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .position(x: Self.size.width / 2, y: 372)
            // Hidden while the gallery sheet covers the bottom of the screen.
            .opacity(time >= Moment.gallery && time < Moment.placed + 0.3 ? 0 : 1)
    }

    private var captionText: LocalizedStringKey {
        switch time {
        case ..<Moment.tapEdit: "Touch and hold an empty spot"
        case ..<Moment.gallery: "Tap Edit, then Add Widget"
        case ..<Moment.tapDone: "Tap Done"
        default: "That's it! Notes from friends show up here."
        }
    }

    // MARK: Finger

    /// Where the finger is over time. Between keyframes it glides with an ease in-out.
    private static let fingerPath: [(time: Double, point: CGPoint)] = [
        (0.2, CGPoint(x: 120, y: 260)),
        (Moment.press, CGPoint(x: 75, y: 128)),
        (Moment.editing + 0.3, CGPoint(x: 75, y: 128)),
        (Moment.tapEdit, CGPoint(x: 36, y: 30)),
        (Moment.menu + 0.3, CGPoint(x: 36, y: 30)),
        (Moment.tapAddWidgetMenu, CGPoint(x: 70, y: 62)),
        (Moment.gallery + 0.6, CGPoint(x: 140, y: 300)),
        (Moment.tapKelmteen, CGPoint(x: 70, y: 237)),
        (Moment.detail + 0.6, CGPoint(x: 150, y: 330)),
        (Moment.tapAddWidget, CGPoint(x: 135, y: 428)),
        (Moment.placed + 0.6, CGPoint(x: 180, y: 300)),
        (Moment.tapDone, CGPoint(x: 230, y: 30)),
        (Moment.finished + 0.8, CGPoint(x: 210, y: 90))
    ]

    /// Moments when the finger presses down (the long press lasts longer).
    private static let taps: [(start: Double, end: Double)] = [
        (Moment.press, Moment.editing),
        (Moment.tapEdit, Moment.tapEdit + 0.25),
        (Moment.tapAddWidgetMenu, Moment.tapAddWidgetMenu + 0.25),
        (Moment.tapKelmteen, Moment.tapKelmteen + 0.25),
        (Moment.tapAddWidget, Moment.tapAddWidget + 0.25),
        (Moment.tapDone, Moment.tapDone + 0.25)
    ]

    private var finger: some View {
        let isPressed = Self.taps.contains { time >= $0.start && time < $0.end }
        let visibility = min(ramp(0.1, 0.4), 1 - ramp(Moment.finished + 0.8, Moment.finished + 1.2))
        return Circle()
            .fill(.white.opacity(isPressed ? 0.95 : 0.7))
            .overlay { Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1.5) }
            .frame(width: 28, height: 28)
            .scaleEffect(isPressed ? 0.8 : 1)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .opacity(visibility)
            .position(fingerPosition)
    }

    private var fingerPosition: CGPoint {
        let path = Self.fingerPath
        guard let next = path.firstIndex(where: { $0.time > time }) else { return path.last!.point }
        guard next > 0 else { return path[0].point }
        let from = path[next - 1], to = path[next]
        let progress = smooth((time - from.time) / (to.time - from.time))
        return CGPoint(
            x: from.point.x + (to.point.x - from.point.x) * progress,
            y: from.point.y + (to.point.y - from.point.y) * progress
        )
    }

    // MARK: Timing helpers

    /// 0 before `start`, 1 after `end`, linear in between.
    private func ramp(_ start: Double, _ end: Double) -> Double {
        min(max((time - start) / (end - start), 0), 1)
    }

    private func smooth(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// Overshoots slightly before settling, for the widget "landing".
    private func easeOutBack(_ value: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        let x = value - 1
        return 1 + c3 * x * x * x + c1 * x * x
    }
}

/// The small Kelmteen widget as it appears in the tutorial, with a sample note.
private struct MiniWidget: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Coffee later?")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(alignment: .bottom) {
                Circle()
                    .fill(Color.sunshine)
                    .overlay { Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1) }
                    .frame(width: 22, height: 22)
                Spacer()
                Text("Just now")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.ink.opacity(0.7))
            }
        }
        .padding(12)
        .background(Color.sunshine, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// A stand-in for the app icon in the widget gallery.
private struct AppIconMini: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.sky)
            .overlay {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ink)
            }
            .frame(width: 30, height: 30)
    }
}

#Preview("Live") {
    TimelineView(.animation) { context in
        WidgetTutorialScene(
            time: context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: WidgetTutorialScene.duration),
            wallpaper: .bubblegum
        )
    }
}

#Preview("Gallery") {
    WidgetTutorialScene(time: 7.2, wallpaper: .sky)
}
