// App updates with Sparkle 2 (Contents/Frameworks/Sparkle.framework, weakly linked), hosted
// in the Java process that runs the official launcher, next to the app's menus.
//
// The process's main bundle is the Java runtime's, so SPUStandardUpdaterController does not
// fit: the updater is set up here with the app bundle as host. Sparkle keeps its settings in
// the app's defaults domain (io.github.jdrly.swglonmac). Info.plist turns automatic checks on
// without Sparkle's permission prompt and leaves installing to the user.
//
// The game runs in Wine processes from inside the app, which Sparkle knows nothing about, so:
//   - background checks wait while the game runs (and run once it has quit);
//   - "Install and Relaunch" while the game runs is held, with a note, until the game quits;
//   - "Install on Quit" (Dismiss once the update is ready) cancels the install instead, and
//     the Java shutdown hook holds the process while the game runs (SWGLUpdatesHoldExit), so
//     an update never replaces the app under a running game.
//
// For testing, `defaults write io.github.jdrly.swglonmac SWGLUpdateFeedURL <url>` replaces the
// feed (Sparkle accepts http only on 127.0.0.1/localhost).

#import "swglupdates.h"
#import <Sparkle/Sparkle.h>
#include <libproc.h>
#include <limits.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static NSString *const AppBundleID = @"io.github.jdrly.swglonmac";
static NSString *const FeedOverrideKey = @"SWGLUpdateFeedURL";
static NSString *const ErrorDomain = @"io.github.jdrly.swglonmac.updates";

// Set while Sparkle has an update ready and would install it when this process ends.
static atomic_bool installReady;
// "<app>/", "<app>/Contents/Frameworks/" and "<support>/GameMode/" (resolved paths).
static char appPrefix[PATH_MAX + 1], frameworksPrefix[PATH_MAX + 32], gameModePrefix[PATH_MAX + 32];

static BOOL hasPrefix(const char *s, const char *prefix)
{
    return prefix[0] && strncmp(s, prefix, strlen(prefix)) == 0;
}

// The game runs: a process other than this one runs a program from inside the app (Wine's
// loader, wineserver, x87sidecar; Sparkle's own helpers in Contents/Frameworks aside) or the
// Game Mode bundle (src/common.sh, enable_game_mode). Any thread.
static BOOL gameRunning(void)
{
    int count = proc_listallpids(NULL, 0);
    if (count <= 0) return NO;
    size_t capacity = (size_t)count + 64;
    pid_t *pids = calloc(capacity, sizeof(pid_t));
    if (!pids) return NO;
    count = proc_listallpids(pids, (int)(capacity * sizeof(pid_t)));
    BOOL running = NO;
    pid_t me = getpid();
    char path[PROC_PIDPATHINFO_MAXSIZE];
    for (int i = 0; i < count && !running; i++) {
        if (pids[i] == me || pids[i] <= 0) continue;
        if (proc_pidpath(pids[i], path, sizeof(path)) <= 0) continue;
        running = hasPrefix(path, gameModePrefix) ||
                  (hasPrefix(path, appPrefix) && !hasPrefix(path, frameworksPrefix));
    }
    free(pids);
    return running;
}

void SWGLUpdatesHoldExit(void)
{
    if (!atomic_load(&installReady) || !gameRunning()) return;
    NSLog(@"SWGL on Mac: an update is ready; quitting once the game has quit");
    while (gameRunning()) sleep(2);
}

#pragma mark - User driver

@class SWGLUpdates;

// Sparkle's standard windows, with one change: Dismiss for an update that is ready to install
// ("Install on Quit") cancels it, without skipping the version, so quitting the launcher while
// the game runs does not replace the app under it.
@interface SWGLUserDriver : NSObject <SPUUserDriver>
@property (strong) SPUStandardUserDriver *standard;
@property (strong) NSBundle *host;
@end

@implementation SWGLUserDriver

- (instancetype)initWithHostBundle:(NSBundle *)host
{
    if ((self = [super init])) {
        _host = host;
        _standard = [[SPUStandardUserDriver alloc] initWithHostBundle:host delegate:nil];
    }
    return self;
}

- (NSString *)sparkleString:(NSString *)key
{
    return [[NSBundle bundleForClass:SPUStandardUserDriver.class] localizedStringForKey:key value:key table:@"Sparkle"];
}

// The update window labels Dismiss "Install on Quit" for an update that is ready; here it
// postpones like before the download.
- (void)relabelInstallOnQuit
{
    NSString *from = [self sparkleString:@"Install on Quit"], *to = [self sparkleString:@"Remind Me Later"];
    for (NSWindow *window in NSApp.windows) {
        NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObject:window.contentView ?: [NSView new]];
        while (views.count) {
            NSView *view = views.lastObject;
            [views removeLastObject];
            [views addObjectsFromArray:view.subviews];
            if ([view isKindOfClass:NSButton.class] && [((NSButton *)view).title isEqualToString:from])
                ((NSButton *)view).title = to;
        }
    }
}

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem state:(SPUUserUpdateState *)state
                                 reply:(void (^)(SPUUserUpdateChoice))reply
{
    if (state.stage != SPUUserUpdateStageInstalling) {
        [self.standard showUpdateFoundWithAppcastItem:appcastItem state:state reply:reply];
        return;
    }
    atomic_store(&installReady, YES);
    [self.standard showUpdateFoundWithAppcastItem:appcastItem state:state reply:^(SPUUserUpdateChoice choice) {
        if (choice != SPUUserUpdateChoiceDismiss) {
            if (choice == SPUUserUpdateChoiceSkip) atomic_store(&installReady, NO);
            reply(choice);
            return;
        }
        // Skip cancels the prepared install, but also marks the version as skipped: put the
        // skipped versions back once Sparkle has handled the reply (it queues that on the main
        // queue, ahead of this).
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:AppBundleID];
        NSArray<NSString *> *keys = @[@"SUSkippedVersion", @"SUSkippedMajorVersion", @"SUSkippedMajorSubreleaseVersion"];
        NSDictionary *before = [defaults dictionaryWithValuesForKeys:keys];
        atomic_store(&installReady, NO);
        reply(SPUUserUpdateChoiceSkip);
        dispatch_async(dispatch_get_main_queue(), ^{
            for (NSString *key in keys) {
                id value = before[key];
                if (value == NSNull.null) [defaults removeObjectForKey:key];
                else [defaults setObject:value forKey:key];
            }
        });
    }];
    dispatch_async(dispatch_get_main_queue(), ^{ [self relabelInstallOnQuit]; });
}

- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply
{
    atomic_store(&installReady, YES);
    [self.standard showReadyToInstallAndRelaunch:^(SPUUserUpdateChoice choice) {
        if (choice == SPUUserUpdateChoiceDismiss) choice = SPUUserUpdateChoiceSkip;  // cancel, see above
        if (choice == SPUUserUpdateChoiceSkip) atomic_store(&installReady, NO);
        reply(choice);
    }];
}

- (void)dismissUpdateInstallation
{
    atomic_store(&installReady, NO);
    [self.standard dismissUpdateInstallation];
}

// Everything else as standard.
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply
{ [self.standard showUpdatePermissionRequest:request reply:reply]; }
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation
{ [self.standard showUserInitiatedUpdateCheckWithCancellation:cancellation]; }
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData
{ [self.standard showUpdateReleaseNotesWithDownloadData:downloadData]; }
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error
{ [self.standard showUpdateReleaseNotesFailedToDownloadWithError:error]; }
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement
{ [self.standard showUpdateNotFoundWithError:error acknowledgement:acknowledgement]; }
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement
{ [self.standard showUpdaterError:error acknowledgement:acknowledgement]; }
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation
{ [self.standard showDownloadInitiatedWithCancellation:cancellation]; }
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)expectedContentLength
{ [self.standard showDownloadDidReceiveExpectedContentLength:expectedContentLength]; }
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length
{ [self.standard showDownloadDidReceiveDataOfLength:length]; }
- (void)showDownloadDidStartExtractingUpdate
{ [self.standard showDownloadDidStartExtractingUpdate]; }
- (void)showExtractionReceivedProgress:(double)progress
{ [self.standard showExtractionReceivedProgress:progress]; }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)applicationTerminated retryTerminatingApplication:(void (^)(void))retryTerminatingApplication
{ [self.standard showInstallingUpdateWithApplicationTerminated:applicationTerminated retryTerminatingApplication:retryTerminatingApplication]; }
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))acknowledgement
{ [self.standard showUpdateInstalledAndRelaunched:relaunched acknowledgement:acknowledgement]; }
- (void)showUpdateInFocus
{ [self.standard showUpdateInFocus]; }

@end

#pragma mark - Updater

@interface SWGLUpdates () <SPUUpdaterDelegate>
@property (strong) SPUUpdater *updater;
@property (strong) SWGLUserDriver *userDriver;
@property (strong) NSTimer *gameWatch;        // a held install or a postponed background check
@property (copy) void (^heldInstall)(void);
@property BOOL backgroundCheckPostponed;
@property (strong) NSAlert *holdNote;
@property (weak) NSWindow *holdNoteParent;
@end

@implementation SWGLUpdates

+ (instancetype)startWithResources:(NSString *)resources gameFolder:(NSString *)gameFolder
{
    if (!NSClassFromString(@"SPUUpdater")) {
        NSLog(@"SWGL on Mac: Sparkle.framework is missing; no update checks");
        return nil;
    }
    // Run as an anonymous java process (src/main.sh explains when), Sparkle could not quit and
    // relaunch the app.
    NSString *registered = NSRunningApplication.currentApplication.bundleIdentifier;
    if (![registered isEqualToString:AppBundleID]) {
        NSLog(@"SWGL on Mac: running as %@, not %@; no update checks", registered ?: @"an unnamed process", AppBundleID);
        return nil;
    }
    NSString *appPath = [[resources stringByAppendingPathComponent:@"../.."] stringByStandardizingPath];
    NSBundle *app = [NSBundle bundleWithPath:appPath];
    if (![app.bundleIdentifier isEqualToString:AppBundleID]) {
        NSLog(@"SWGL on Mac: %@ is not the app; no update checks", appPath);
        return nil;
    }
    char real[PATH_MAX];
    if (realpath(appPath.fileSystemRepresentation, real)) {
        snprintf(appPrefix, sizeof(appPrefix), "%s/", real);
        snprintf(frameworksPrefix, sizeof(frameworksPrefix), "%s/Contents/Frameworks/", real);
    }
    NSString *support = gameFolder.stringByStandardizingPath.stringByDeletingLastPathComponent;
    if (realpath(support.fileSystemRepresentation, real))
        snprintf(gameModePrefix, sizeof(gameModePrefix), "%s/GameMode/", real);

    SWGLUpdates *updates = [SWGLUpdates new];
    updates.userDriver = [[SWGLUserDriver alloc] initWithHostBundle:app];
    updates.updater = [[SPUUpdater alloc] initWithHostBundle:app applicationBundle:app
                                                  userDriver:updates.userDriver delegate:updates];
    NSError *error = nil;
    if (![updates.updater startUpdater:&error]) {
        NSLog(@"SWGL on Mac: Sparkle did not start: %@", error.localizedDescription);
        return nil;
    }
    NSLog(@"SWGL on Mac: update checks %@, feed %@",
          updates.updater.automaticallyChecksForUpdates ? @"automatic" : @"manual", updates.updater.feedURL);
    return updates;
}

#pragma mark Menus

- (NSMenuItem *)checkForUpdatesItem
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Check for Updates…"
                                                  action:@selector(checkForUpdates:) keyEquivalent:@""];
    item.target = self;
    return item;
}

- (NSMenuItem *)automaticChecksItem
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Check for Updates Automatically"
                                                  action:@selector(toggleAutomaticChecks:) keyEquivalent:@""];
    item.target = self;
    return item;
}

- (void)checkForUpdates:(id)sender
{
    [self.updater checkForUpdates];
}

- (void)toggleAutomaticChecks:(NSMenuItem *)item
{
    self.updater.automaticallyChecksForUpdates = !self.updater.automaticallyChecksForUpdates;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if (item.action == @selector(checkForUpdates:))
        return self.updater.canCheckForUpdates;
    if (item.action == @selector(toggleAutomaticChecks:))
        item.state = self.updater.automaticallyChecksForUpdates ? NSControlStateValueOn : NSControlStateValueOff;
    return YES;
}

#pragma mark Game watch

// While an install is held or a background check postponed, look every 2 s whether the game
// has quit.
- (void)watchGame
{
    if (self.gameWatch) return;
    __weak SWGLUpdates *weakSelf = self;
    self.gameWatch = [NSTimer timerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf gameWatchFired];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.gameWatch forMode:NSRunLoopCommonModes];
}

- (void)gameWatchFired
{
    if (gameRunning()) return;
    [self.gameWatch invalidate];
    self.gameWatch = nil;
    if (self.heldInstall) {
        NSLog(@"SWGL on Mac: the game has quit; installing the update");
        [self closeHoldNote];
        void (^install)(void) = self.heldInstall;
        self.heldInstall = nil;
        install();
    } else if (self.backgroundCheckPostponed) {
        self.backgroundCheckPostponed = NO;
        if (self.updater.automaticallyChecksForUpdates && !self.updater.sessionInProgress) {
            NSLog(@"SWGL on Mac: the game has quit; checking for updates");
            [self.updater checkForUpdatesInBackground];
        }
    }
}

// "Install and Relaunch" while the game runs: say why nothing happens yet, as a sheet on
// Sparkle's window the button was in.
- (void)showHoldNote
{
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"The update will be installed when you quit the game";
    alert.informativeText = @"SWGL on Mac installs the update and relaunches as soon as the game is closed.";
    [alert addButtonWithTitle:@"OK"];
    NSWindow *parent = NSApp.keyWindow;
    if (!parent) {
        for (NSWindow *window in NSApp.windows)
            if (window.visible && [NSStringFromClass(window.windowController.class) hasPrefix:@"SU"]) parent = window;
    }
    self.holdNote = alert;
    self.holdNoteParent = parent;
    if (parent) {
        [alert beginSheetModalForWindow:parent completionHandler:^(NSModalResponse response) {
            self.holdNote = nil;
        }];
    } else {
        [NSApp activateIgnoringOtherApps:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            [alert runModal];
            self.holdNote = nil;
        });
    }
}

- (void)closeHoldNote
{
    NSAlert *alert = self.holdNote;
    if (!alert) return;
    self.holdNote = nil;
    if (self.holdNoteParent && alert.window.sheetParent)
        [self.holdNoteParent endSheet:alert.window];
    else if (alert.window.visible)
        [NSApp abortModal];
}

#pragma mark SPUUpdaterDelegate

- (NSString *)feedURLStringForUpdater:(SPUUpdater *)updater
{
    NSString *feed = [[[NSUserDefaults alloc] initWithSuiteName:AppBundleID] stringForKey:FeedOverrideKey];
    return feed.length ? feed : nil;
}

- (BOOL)updater:(SPUUpdater *)updater mayPerformUpdateCheck:(SPUUpdateCheck)updateCheck error:(NSError **)error
{
    if (updateCheck != SPUUpdateCheckUpdatesInBackground || !gameRunning()) return YES;
    NSLog(@"SWGL on Mac: the game is running; checking for updates once it has quit");
    self.backgroundCheckPostponed = YES;
    [self watchGame];
    if (error)
        *error = [NSError errorWithDomain:ErrorDomain code:1
                                 userInfo:@{NSLocalizedDescriptionKey: @"The game is running."}];
    return NO;
}

- (BOOL)updater:(SPUUpdater *)updater shouldPostponeRelaunchForUpdate:(SUAppcastItem *)item
untilInvokingBlock:(void (^)(void))installHandler
{
    if (!gameRunning()) return NO;
    NSLog(@"SWGL on Mac: holding the update to %@ until the game has quit", item.displayVersionString);
    self.heldInstall = installHandler;
    [self showHoldNote];
    [self watchGame];
    return YES;
}

- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error
{
    if (![error.domain isEqualToString:ErrorDomain])
        NSLog(@"SWGL on Mac: update aborted: %@", error.localizedDescription);
}

- (void)updaterWillRelaunchApplication:(SPUUpdater *)updater
{
    NSLog(@"SWGL on Mac: relaunching for the update");
}

@end
