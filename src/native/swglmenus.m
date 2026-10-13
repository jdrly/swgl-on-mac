// libswglmenus.dylib: the app's own macOS menus, added to the menu bar of the Java
// process that runs the official launcher (it owns the menu bar while its window is
// in front). Loaded by Launcher.java once JavaFX has created the main menu.
//
//   App menu:  About SWGL on Mac (standard About panel), Check for Updates… (Sparkle,
//              src/native/swglupdates.m), Settings… (the SwiftUI settings window,
//              Contents/Helpers/SWGL on Mac Settings.app), Open SWGL in Finder (the game
//              folder, for mods), Collect Logs… (a zip for bug reports, Resources/collect-logs.sh)

#import <Cocoa/Cocoa.h>
#include <jni.h>
#import "swglupdates.h"

@interface SWGLMenus : NSObject <NSMenuItemValidation>
@property (copy) NSString *resources;
@property (copy) NSString *gameFolder;
@property BOOL collectingLogs;
@property (strong) SWGLUpdates *updates;  // nil without app updates
@end

@implementation SWGLMenus

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if (item.action == @selector(collectLogs:))
        return !self.collectingLogs;
    return item.action != nil;
}

// Resources/app.properties (written by build.sh): version, author, github, repo.
- (NSDictionary<NSString *, NSString *> *)appProperties
{
    NSString *path = [self.resources stringByAppendingPathComponent:@"app.properties"];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSRange eq = [line rangeOfString:@"="];
        if (eq.location != NSNotFound)
            values[[line substringToIndex:eq.location]] = [line substringFromIndex:NSMaxRange(eq)];
    }
    return values;
}

// "Wine cx-26.3.0-8 · d9mt 43af888" from Resources/VERSIONS.
- (NSString *)componentVersions
{
    NSString *path = [self.resources stringByAppendingPathComponent:@"VERSIONS"];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSArray *f = [[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
                      componentsSeparatedByString:@" "];
        if (f.count >= 2 && [f[0] isEqualToString:@"wine"])
            [parts addObject:[@"Wine " stringByAppendingString:f[1]]];
        else if (f.count >= 2 && [f[0] isEqualToString:@"d9mt"])
            [parts addObject:[@"d9mt " stringByAppendingString:f[1]]];
    }
    return [parts componentsJoinedByString:@" · "];
}

- (void)showAbout:(id)sender
{
    NSDictionary *app = [self appProperties];
    NSMutableParagraphStyle *centered = [NSMutableParagraphStyle new];
    centered.alignment = NSTextAlignmentCenter;
    NSDictionary *body = @{ NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize],
                            NSForegroundColorAttributeName: NSColor.labelColor,
                            NSParagraphStyleAttributeName: centered };
    NSMutableAttributedString *credits = [[NSMutableAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"Unofficial client for macOS\n"
                                                   "Developed by %@\n\n"
                                                   "Not supported by the SWG Legends team.\n"
                                                   "For help: Pharaphobia on Discord or GitHub.\n",
                                                   app[@"author"] ?: @"?"]
            attributes:body];
    for (NSString *key in @[@"repo", @"github"]) {
        NSString *url = app[key];
        if (url.length == 0) continue;
        NSString *shown = [url stringByReplacingOccurrencesOfString:@"https://" withString:@""];
        NSMutableDictionary *link = [body mutableCopy];
        link[NSLinkAttributeName] = [NSURL URLWithString:url];
        [credits appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:body]];
        [credits appendAttributedString:[[NSAttributedString alloc] initWithString:shown attributes:link]];
    }
    NSMutableDictionary *small = [body mutableCopy];
    small[NSFontAttributeName] = [NSFont systemFontOfSize:NSFont.labelFontSize - 1];
    small[NSForegroundColorAttributeName] = NSColor.secondaryLabelColor;
    [credits appendAttributedString:[[NSAttributedString alloc]
        initWithString:[@"\n\n" stringByAppendingString:[self componentVersions]] attributes:small]];

    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    options[NSAboutPanelOptionApplicationName] = @"SWGL on Mac";
    options[NSAboutPanelOptionApplicationVersion] = app[@"version"] ?: @"?";
    options[NSAboutPanelOptionVersion] = @"";
    options[NSAboutPanelOptionCredits] = credits;
    NSImage *icon = [[NSImage alloc] initWithContentsOfFile:
                     [self.resources stringByAppendingPathComponent:@"AppIcon.icns"]];
    if (icon) options[NSAboutPanelOptionApplicationIcon] = icon;
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanelWithOptions:options];
}

// Its own app, so it gets the current design (this process's Java is linked against an old
// SDK). Opening it again brings the running one to the front; it quits with the launcher.
- (void)showSettings:(id)sender
{
    NSURL *helper = [NSURL fileURLWithPath:[self.resources stringByAppendingPathComponent:
                                            @"../Helpers/SWGL on Mac Settings.app"]].URLByStandardizingPath;
    NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
    config.arguments = @[[NSString stringWithFormat:@"%d", getpid()]];
    // Activation is cooperative: without handing it over, the helper may not take focus and
    // its window opens behind the launcher.
    [NSApp yieldActivationToApplicationWithBundleIdentifier:@"io.github.jdrly.swglonmac.settings"];
    [NSWorkspace.sharedWorkspace openApplicationAtURL:helper configuration:config
                                    completionHandler:^(NSRunningApplication *app, NSError *error) {
        if (error) NSLog(@"SWGL on Mac: could not open the settings: %@", error);
    }];
}

- (void)openGameFolder:(id)sender
{
    [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:self.gameFolder isDirectory:YES]];
}

// Resources/collect-logs.sh zips the logs for a bug report (a few seconds: off the main
// thread) and prints the zip's path; then say where it is and show it in Finder.
- (void)collectLogs:(id)sender
{
    self.collectingLogs = YES;
    NSString *script = [self.resources stringByAppendingPathComponent:@"collect-logs.sh"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSTask *task = [NSTask new];
        task.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
        task.arguments = @[script];
        task.standardInput = [NSFileHandle fileHandleWithNullDevice];
        NSPipe *output = [NSPipe pipe], *errors = [NSPipe pipe];
        task.standardOutput = output;
        task.standardError = errors;
        NSError *error = nil;
        NSString *zip = nil, *problem = nil;
        if ([task launchAndReturnError:&error]) {
            NSData *data = [output.fileHandleForReading readDataToEndOfFile];
            NSData *errorData = [errors.fileHandleForReading readDataToEndOfFile];
            [task waitUntilExit];
            NSCharacterSet *space = NSCharacterSet.whitespaceAndNewlineCharacterSet;
            NSString *path = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                              stringByTrimmingCharactersInSet:space];
            path = [path componentsSeparatedByString:@"\n"].lastObject;
            if (task.terminationStatus == 0 && path.length && [NSFileManager.defaultManager fileExistsAtPath:path])
                zip = path;
            else
                problem = [[[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding]
                           stringByTrimmingCharactersInSet:space];
        } else {
            problem = error.localizedDescription;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.collectingLogs = NO;
            NSAlert *alert = [NSAlert new];
            if (zip) {
                NSString *folder = [NSFileManager.defaultManager displayNameAtPath:zip.stringByDeletingLastPathComponent];
                alert.messageText = @"Logs collected";
                alert.informativeText = [NSString stringWithFormat:
                    @"%@ is in your %@ folder. Send it with a short description of the problem to "
                     "Pharaphobia on Discord or attach it to a GitHub issue, not to the SWG Legends team.",
                    zip.lastPathComponent, folder];
                [alert addButtonWithTitle:@"Show in Finder"];
            } else {
                alert.alertStyle = NSAlertStyleWarning;
                alert.messageText = @"Could not collect the logs";
                alert.informativeText = [NSString stringWithFormat:@"%@\n\nThe logs are in ~/Library/Logs/SWGLonMac.",
                                         problem.length ? problem : @"collect-logs.sh failed."];
            }
            [NSApp activateIgnoringOtherApps:YES];
            [alert runModal];
            if (zip)
                [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:zip]]];
        });
    });
}

- (BOOL)install
{
    NSMenu *mainMenu = NSApp.mainMenu;
    NSMenu *appMenu = mainMenu.numberOfItems ? [mainMenu itemAtIndex:0].submenu : nil;
    if (!appMenu) return NO;

    NSInteger index = 0;
    NSMenuItem *about = [[NSMenuItem alloc] initWithTitle:@"About SWGL on Mac"
                                                   action:@selector(showAbout:) keyEquivalent:@""];
    about.target = self;
    [appMenu insertItem:about atIndex:index++];
    self.updates = [SWGLUpdates startWithResources:self.resources gameFolder:self.gameFolder];
    if (self.updates)
        [appMenu insertItem:[self.updates checkForUpdatesItem] atIndex:index++];
    [appMenu insertItem:[NSMenuItem separatorItem] atIndex:index++];
    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"Settings…"
                                                      action:@selector(showSettings:) keyEquivalent:@","];
    settings.target = self;
    [appMenu insertItem:settings atIndex:index++];
    [appMenu insertItem:[NSMenuItem separatorItem] atIndex:index++];
    // The game files, where mods go.
    NSMenuItem *gameFolder = [[NSMenuItem alloc] initWithTitle:@"Open SWGL in Finder"
                                                        action:@selector(openGameFolder:) keyEquivalent:@""];
    gameFolder.target = self;
    [appMenu insertItem:gameFolder atIndex:index++];
    // A zip of the logs to send with a bug report.
    NSMenuItem *collect = [[NSMenuItem alloc] initWithTitle:@"Collect Logs…"
                                                     action:@selector(collectLogs:) keyEquivalent:@""];
    collect.target = self;
    [appMenu insertItem:collect atIndex:index++];
    [appMenu insertItem:[NSMenuItem separatorItem] atIndex:index++];
    return YES;
}

@end

static SWGLMenus *menus;

// Launcher.installMenus(String resources, String gameFolder): true once the menus are in place, false if
// JavaFX has not created the main menu yet. Called on the JavaFX thread, which on macOS
// is the AppKit main thread.
JNIEXPORT jboolean JNICALL Java_Launcher_installMenus(JNIEnv *env, jclass cls, jstring resources, jstring gameFolder)
{
    if (menus) return JNI_TRUE;
    if (![NSThread isMainThread]) {
        NSLog(@"SWGL on Mac: installMenus called off the main thread");
        return JNI_TRUE;
    }
    const char *res = (*env)->GetStringUTFChars(env, resources, NULL);
    SWGLMenus *m = [SWGLMenus new];
    m.resources = [NSString stringWithUTF8String:res];
    (*env)->ReleaseStringUTFChars(env, resources, res);
    const char *game = (*env)->GetStringUTFChars(env, gameFolder, NULL);
    m.gameFolder = [NSString stringWithUTF8String:game];
    (*env)->ReleaseStringUTFChars(env, gameFolder, game);
    if (![m install]) return JNI_FALSE;
    menus = m;
    return JNI_TRUE;
}

// Launcher.holdExitForUpdate(), from the JVM's shutdown hook: see SWGLUpdatesHoldExit.
JNIEXPORT void JNICALL Java_Launcher_holdExitForUpdate(JNIEnv *env, jclass cls)
{
    SWGLUpdatesHoldExit();
}
