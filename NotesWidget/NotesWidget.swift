//
//  NotesWidget.swift
//  NotesWidget
//
//  Created by Ahmed Shaheen on 11/10/26.
//

import WidgetKit
import SwiftUI

struct NoteEntry: TimelineEntry {
    let date: Date
    let note: WidgetNote?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> NoteEntry {
        NoteEntry(date: .now, note: WidgetNote.samples[0])
    }

    func getSnapshot(in context: Context, completion: @escaping (NoteEntry) -> Void) {
        // The widget gallery shows a sample so people can see what they're adding.
        let note = context.isPreview ? WidgetNote.samples[0] : WidgetNoteStore.latestNote()
        completion(NoteEntry(date: .now, note: note))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NoteEntry>) -> Void) {
        Task {
            let now = Date.now
            // A push from the server reloads the widget right away when a note is sent; checking
            // in every 30 minutes is the backup if a push doesn't arrive.
            let nextCheck = now.addingTimeInterval(30 * 60)
            guard let note = await WidgetNoteStore.fetchLatestNote(at: now) else {
                completion(Timeline(entries: [NoteEntry(date: now, note: nil)], policy: .after(nextCheck)))
                return
            }

            // An entry every 15 minutes keeps "6 min. ago" fresh until the next check, which
            // also clears the note once its 24 hours are up.
            let entries = [now, now.addingTimeInterval(15 * 60)]
                .filter { $0 < note.expiresAt }
                .map { NoteEntry(date: $0, note: note) }
            completion(Timeline(entries: entries, policy: .after(min(nextCheck, note.expiresAt))))
        }
    }
}

/// Receives the push token WidgetKit creates for this widget and passes it to the server,
/// which uses it to reload the widget when a new note is sent.
struct NotesWidgetPushHandler: WidgetPushHandler {
    func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
        Task { await WidgetNoteStore.savePushToken(pushInfo.token) }
    }
}

struct NotesWidget: Widget {
    let kind = "NotesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            NotesWidgetView(entry: entry)
        }
        .configurationDisplayName("Notes")
        .description("The latest note from your friends.")
        .pushHandler(NotesWidgetPushHandler.self)
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryCircular, .accessoryInline
        ])
    }
}

// MARK: - Views

struct NotesWidgetView: View {
    let entry: NoteEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            LockScreenRectangularView(note: entry.note, date: entry.date)
                .containerBackground(.clear, for: .widget)
        case .accessoryCircular:
            LockScreenCircularView(note: entry.note)
                .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            LockScreenInlineView(note: entry.note)
                .containerBackground(.clear, for: .widget)
        default:
            if let note = entry.note {
                HomeScreenNoteView(note: note, date: entry.date, family: family)
                    // Notes always use the sender's assigned color.
                    .containerBackground(note.color, for: .widget)
            } else {
                HomeScreenEmptyView()
                    .containerBackground(Color.lightBackground, for: .widget)
            }
        }
    }
}

/// Home Screen widget from the Figma "Small Widget" / "Large Widget" frames.
private struct HomeScreenNoteView: View {
    let note: WidgetNote
    let date: Date
    let family: WidgetFamily

    private var isLarge: Bool { family == .systemLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(note.text)
                .font(textFont)
                .foregroundStyle(Color.ink)
                .minimumScaleFactor(0.7)
                .noteTextDirection(note.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            HStack(alignment: .bottom) {
                WidgetAvatar(initials: note.senderInitials, color: note.color, size: isLarge ? 52 : 39)
                if family != .systemSmall {
                    Text(note.senderFirstName)
                        .font(isLarge ? .headline : .subheadline)
                        .foregroundStyle(Color.ink)
                        .frame(maxHeight: isLarge ? 52 : 39)
                }
                Spacer()
                Text(note.sentDescription(relativeTo: date))
                    .font(isLarge ? .callout : .caption2)
                    .foregroundStyle(Color.ink.opacity(0.7))
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    /// Shorter notes get bigger text so the widget never feels empty.
    private var textFont: Font {
        switch (family, note.text.count) {
        case (.systemLarge, ..<40): .largeTitle
        case (.systemLarge, _): .title2
        case (_, ..<24): .title2
        default: .title3
        }
    }
}

private struct HomeScreenEmptyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "sparkles")
                .font(.title2)
            Spacer()
            Text("No notes yet")
                .font(.headline)
            Text("Notes from friends show up here.")
                .font(.caption)
                .foregroundStyle(Color.ink.opacity(0.7))
        }
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Lock Screen widget from the Figma "Lock Screen Widget" frame: a bar, then name, note and time.
private struct LockScreenRectangularView: View {
    let note: WidgetNote?
    let date: Date

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .frame(width: 5)
                .padding(.vertical, 4)
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 0) {
                if let note {
                    Text(note.senderName)
                        .font(.headline)
                    Text(note.text)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(note.sentDescription(relativeTo: date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No notes yet")
                        .font(.headline)
                    Text("Notes from friends show up here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LockScreenCircularView: View {
    let note: WidgetNote?

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let note {
                Text(note.senderInitials)
                    .font(.title3)
                    .fontWeight(.semibold)
            } else {
                Image(systemName: "sparkles")
                    .font(.title3)
            }
        }
        .accessibilityLabel(note.map { String(localized: "Note from \($0.senderName)") } ?? String(localized: "No notes yet"))
    }
}

private struct LockScreenInlineView: View {
    let note: WidgetNote?

    var body: some View {
        if let note {
            Label("\(note.senderFirstName): \(note.text)", systemImage: "sparkles")
        } else {
            Label("No notes yet", systemImage: "sparkles")
        }
    }
}

/// Matches the app's avatar: initials on the sender's color with a light ring.
private struct WidgetAvatar: View {
    let initials: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(Color.ink)
            }
            .overlay {
                Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
            }
            .frame(width: size, height: size)
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    NotesWidget()
} timeline: {
    NoteEntry(date: .now, note: WidgetNote.samples[0])
    NoteEntry(date: .now, note: WidgetNote.samples[1])
    NoteEntry(date: .now, note: nil)
}

#Preview("Medium", as: .systemMedium) {
    NotesWidget()
} timeline: {
    NoteEntry(date: .now, note: WidgetNote.samples[1])
    NoteEntry(date: .now, note: WidgetNote.samples[0])
}

#Preview("Large", as: .systemLarge) {
    NotesWidget()
} timeline: {
    NoteEntry(date: .now, note: WidgetNote.samples[2])
    NoteEntry(date: .now, note: WidgetNote.samples[0])
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    NotesWidget()
} timeline: {
    NoteEntry(date: .now, note: WidgetNote.samples[0])
    NoteEntry(date: .now, note: nil)
}

#Preview("Lock Screen Circle", as: .accessoryCircular) {
    NotesWidget()
} timeline: {
    NoteEntry(date: .now, note: WidgetNote.samples[0])
}
