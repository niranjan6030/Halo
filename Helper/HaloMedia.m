// IslandMedia — the now-playing bridge.
//
// Since macOS 15.4, MediaRemote only answers processes Apple trusts, so a
// third-party app asking "what's playing?" gets an empty dictionary. /usr/bin/perl
// is an Apple platform binary, so Island runs perl, has it load this library, and
// calls island_media_run(). From then on this process:
//
//   stdout  one JSON object per line: {"type":"info",...}, {"type":"artwork",...},
//           or {"type":"none"} when nothing is playing.
//   stdin   one command per line: play, pause, toggle, next, previous, seek <sec>.
//
// When Island quits, stdin reaches EOF and this process exits with it.

#import <Foundation/Foundation.h>

typedef enum {
    MRCommandPlay = 0,
    MRCommandPause = 1,
    MRCommandTogglePlayPause = 2,
    MRCommandNextTrack = 4,
    MRCommandPreviousTrack = 5,
} MRCommand;

extern void MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_queue_t queue);
extern void MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t queue, void (^handler)(NSDictionary *info));
extern void MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_queue_t queue, void (^handler)(BOOL playing));
extern void MRMediaRemoteGetNowPlayingClient(dispatch_queue_t queue, void (^handler)(id client));
extern NSString *MRNowPlayingClientGetBundleIdentifier(id client);
extern NSString *MRNowPlayingClientGetParentAppBundleIdentifier(id client);
extern Boolean MRMediaRemoteSendCommand(MRCommand command, NSDictionary *options);
extern void MRMediaRemoteSetElapsedTime(double seconds);

extern NSString *kMRMediaRemoteNowPlayingInfoDidChangeNotification;
extern NSString *kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification;
extern NSString *kMRMediaRemoteNowPlayingApplicationDidChangeNotification;

extern NSString *kMRMediaRemoteNowPlayingInfoTitle;
extern NSString *kMRMediaRemoteNowPlayingInfoArtist;
extern NSString *kMRMediaRemoteNowPlayingInfoAlbum;
extern NSString *kMRMediaRemoteNowPlayingInfoDuration;
extern NSString *kMRMediaRemoteNowPlayingInfoElapsedTime;
extern NSString *kMRMediaRemoteNowPlayingInfoPlaybackRate;
extern NSString *kMRMediaRemoteNowPlayingInfoTimestamp;
extern NSString *kMRMediaRemoteNowPlayingInfoArtworkData;

static NSData *lastArtwork = nil;
static BOOL sentArtworkOnce = NO;
static NSString *lastLine = nil;

static void emit(NSDictionary *object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static id orNull(id value) { return value ?: [NSNull null]; }

static void refresh(void) {
    MRMediaRemoteGetNowPlayingClient(dispatch_get_main_queue(), ^(id client) {
        NSString *bundle = nil;
        if (client) {
            bundle = MRNowPlayingClientGetParentAppBundleIdentifier(client);
            if (bundle.length == 0) bundle = MRNowPlayingClientGetBundleIdentifier(client);
        }
        MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_main_queue(), ^(BOOL playing) {
            MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(NSDictionary *info) {
                NSString *title = info[kMRMediaRemoteNowPlayingInfoTitle];
                if (info.count == 0 || title.length == 0) {
                    if (![lastLine isEqualToString:@"none"]) {
                        lastLine = @"none";
                        lastArtwork = nil;
                        sentArtworkOnce = NO;
                        emit(@{@"type": @"none"});
                    }
                    return;
                }

                NSDate *timestamp = info[kMRMediaRemoteNowPlayingInfoTimestamp];
                NSDictionary *payload = @{
                    @"type": @"info",
                    @"title": title,
                    @"artist": orNull(info[kMRMediaRemoteNowPlayingInfoArtist]),
                    @"album": orNull(info[kMRMediaRemoteNowPlayingInfoAlbum]),
                    @"duration": orNull(info[kMRMediaRemoteNowPlayingInfoDuration]),
                    @"elapsed": orNull(info[kMRMediaRemoteNowPlayingInfoElapsedTime]),
                    @"rate": orNull(info[kMRMediaRemoteNowPlayingInfoPlaybackRate]),
                    @"timestamp": timestamp ? @(timestamp.timeIntervalSince1970) : [NSNull null],
                    @"playing": @(playing),
                    @"bundle": orNull(bundle),
                };
                NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingSortedKeys error:nil];
                NSString *line = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
                if (![line isEqualToString:lastLine]) {
                    lastLine = line;
                    emit(payload);
                }

                // Artwork is large, so it only crosses the pipe when it changes.
                NSData *artwork = info[kMRMediaRemoteNowPlayingInfoArtworkData];
                if (!sentArtworkOnce || !((artwork == nil && lastArtwork == nil) || [artwork isEqualToData:lastArtwork])) {
                    sentArtworkOnce = YES;
                    lastArtwork = artwork;
                    emit(@{@"type": @"artwork", @"data": orNull([artwork base64EncodedStringWithOptions:0])});
                }
            });
        });
    });
}

static void handleCommand(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *name = parts.firstObject;
    if ([name isEqualToString:@"play"]) MRMediaRemoteSendCommand(MRCommandPlay, nil);
    else if ([name isEqualToString:@"pause"]) MRMediaRemoteSendCommand(MRCommandPause, nil);
    else if ([name isEqualToString:@"toggle"]) MRMediaRemoteSendCommand(MRCommandTogglePlayPause, nil);
    else if ([name isEqualToString:@"next"]) MRMediaRemoteSendCommand(MRCommandNextTrack, nil);
    else if ([name isEqualToString:@"previous"]) MRMediaRemoteSendCommand(MRCommandPreviousTrack, nil);
    else if ([name isEqualToString:@"seek"] && parts.count > 1) MRMediaRemoteSetElapsedTime(parts[1].doubleValue);
    else if ([name isEqualToString:@"refresh"]) { lastLine = nil; sentArtworkOnce = NO; }
    refresh();
}

// Called by perl through DynaLoader, with perl's (unused) XS arguments.
void island_media_run(void *unusedInterpreter, void *unusedCV) {
    @autoreleasepool {
        MRMediaRemoteRegisterForNowPlayingNotifications(dispatch_get_main_queue());

        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        for (NSString *name in @[kMRMediaRemoteNowPlayingInfoDidChangeNotification,
                                 kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification,
                                 kMRMediaRemoteNowPlayingApplicationDidChangeNotification]) {
            [center addObserverForName:name object:nil queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification *note) { refresh(); }];
        }

        // Some players change position without posting a notification, so a slow
        // poll backs the notifications up. Identical results are never re-sent.
        dispatch_source_t poll = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(poll, DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
        dispatch_source_set_event_handler(poll, ^{ refresh(); });
        dispatch_resume(poll);

        dispatch_queue_t reader = dispatch_queue_create("island.media.stdin", DISPATCH_QUEUE_SERIAL);
        dispatch_async(reader, ^{
            char buffer[512];
            while (fgets(buffer, sizeof buffer, stdin)) {
                NSString *line = [[NSString stringWithUTF8String:buffer]
                                  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (line.length == 0) continue;
                dispatch_async(dispatch_get_main_queue(), ^{ handleCommand(line); });
            }
            exit(0);
        });

        refresh();
        CFRunLoopRun();
    }
}
