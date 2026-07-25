import WidgetKit
import SwiftUI

struct SongloftNowPlayingWidget: Widget {
    let kind: String = "SongloftNowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingProvider()) { entry in
            NowPlayingEntryView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("Show current playing song on your home screen")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let title: String
    let artist: String
    let artUrl: String
    let isPlaying: Bool
    let hasSong: Bool
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(
            date: Date(),
            title: "Songloft",
            artist: "",
            artUrl: "",
            isPlaying: false,
            hasSong: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        let entry = NowPlayingEntry(
            date: Date(),
            title: "Songloft",
            artist: "",
            artUrl: "",
            isPlaying: false,
            hasSong: false
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let defaults = UserDefaults(suiteName: "group.com.songloft.songloftFlutter")
        let entry = NowPlayingEntry(
            date: Date(),
            title: defaults?.string(forKey: "widget_song_title") ?? "Songloft",
            artist: defaults?.string(forKey: "widget_song_artist") ?? "",
            artUrl: defaults?.string(forKey: "widget_song_art_url") ?? "",
            isPlaying: defaults?.bool(forKey: "widget_is_playing") ?? false,
            hasSong: defaults?.bool(forKey: "widget_has_song") ?? false
        )
        completion(Timeline(entries: [entry], policy: .atEnd))
    }
}

struct NowPlayingEntryView: View {
    let entry: NowPlayingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.hasSong {
                HStack(spacing: 10) {
                    if !entry.artUrl.isEmpty {
                        AsyncImage(url: URL(string: entry.artUrl)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            default:
                                Image("AppIcon")
                                    .resizable()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    } else {
                        Image("AppIcon")
                            .resizable()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        if !entry.artist.isEmpty {
                            Text(entry.artist)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()

                    Image(systemName: entry.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
            } else {
                HStack {
                    Image("AppIcon")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("Songloft")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
    }
}