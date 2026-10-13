// libswglmenus.dylib: the app's own macOS menus, added to the menu bar of the Java
// process that runs the official launcher (it owns the menu bar while its window is
// in front). Loaded by Launcher.java once JavaFX has created the main menu.
//
//   App menu:  About SWGL on Mac (standard About panel), Open SWGL in Finder (the game folder, for mods),
//              Collect Logs… (a zip for bug reports, Resources/collect-logs.sh)
//   Features:  Retina Mode, Show Metal HUD, Game Mode, Debug Mode (settings.conf through
//              Resources/settings.sh)

#import <Cocoa/Cocoa.h>
#include <jni.h>

@interface SWGLMenus : NSObject <NSMenuItemValidation>
@property (copy) NSString *resources;
@property (copy) NSString *gameFolder;
@property (copy) NSDictionary<NSString *, NSString *> *settings;
@property (strong) NSDate *settingsReadAt;
@property BOOL collectingLogs;
@end

@implementation SWGLMenus

// settings.sh prints KEY=value lines; with "KEY value" it changes one setting first.
- (NSDictionary<NSString *, NSString *> *)runSettings:(NSArray<NSString *> *)args
{
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
    task.arguments = [@[[self.resources stringByAppendingPathComponent:@"settings.sh"]]
                      arrayByAddingObjectsFromArray:args];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        NSLog(@"SWGL on Mac: settings.sh: %@", error);
        return nil;
    }
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSRange eq = [line rangeOfString:@"="];
        if (eq.location != NSNotFound && eq.location > 0)
            values[[line substringToIndex:eq.location]] = [line substringFromIndex:NSMaxRange(eq)];
    }
    return values.count ? values : nil;
}

- (BOOL)isOn:(NSString *)key
{
    // Validation asks once per item each time the menu opens.
    if (!self.settings || -[self.settingsReadAt timeIntervalSinceNow] > 1.0) {
        NSDictionary *values = [self runSettings:@[]];
        if (values) self.settings = values;
        self.settingsReadAt = [NSDate date];
    }
    return [self.settings[key] isEqualToString:@"on"];
}

- (void)toggleSetting:(NSMenuItem *)item
{
    NSString *key = item.representedObject;
    NSDictionary *values = [self runSettings:@[key, [self isOn:key] ? @"off" : @"on"]];
    if (values) self.settings = values;
    self.settingsReadAt = [NSDate date];
    item.state = [self isOn:key] ? NSControlStateValueOn : NSControlStateValueOff;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if (item.action == @selector(toggleSetting:))
        item.state = [self isOn:item.representedObject] ? NSControlStateValueOn : NSControlStateValueOff;
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
                                                   "Developed by %@\n", app[@"author"] ?: @"?"]
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
                    @"%@ is in your %@ folder. Send it along with a short description of the problem.",
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

- (NSMenuItem *)toggleItem:(NSString *)title key:(NSString *)key
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(toggleSetting:) keyEquivalent:@""];
    item.target = self;
    item.representedObject = key;
    return item;
}

- (BOOL)install
{
    NSMenu *mainMenu = NSApp.mainMenu;
    NSMenu *appMenu = mainMenu.numberOfItems ? [mainMenu itemAtIndex:0].submenu : nil;
    if (!appMenu) return NO;

    NSMenuItem *about = [[NSMenuItem alloc] initWithTitle:@"About SWGL on Mac"
                                                   action:@selector(showAbout:) keyEquivalent:@""];
    about.target = self;
    [appMenu insertItem:about atIndex:0];
    [appMenu insertItem:[NSMenuItem separatorItem] atIndex:1];
    // The game files, where mods go.
    NSMenuItem *gameFolder = [[NSMenuItem alloc] initWithTitle:@"Open SWGL in Finder"
                                                        action:@selector(openGameFolder:) keyEquivalent:@""];
    gameFolder.target = self;
    [appMenu insertItem:gameFolder atIndex:2];
    // A zip of the logs to send with a bug report.
    NSMenuItem *collect = [[NSMenuItem alloc] initWithTitle:@"Collect Logs…"
                                                     action:@selector(collectLogs:) keyEquivalent:@""];
    collect.target = self;
    [appMenu insertItem:collect atIndex:3];
    [appMenu insertItem:[NSMenuItem separatorItem] atIndex:4];

    NSMenu *features = [[NSMenu alloc] initWithTitle:@"Features"];
    [features addItem:[self toggleItem:@"Retina Mode" key:@"RETINA"]];
    [features addItem:[self toggleItem:@"Show Metal HUD" key:@"FPS_HUD"]];
    [features addItem:[self toggleItem:@"Game Mode" key:@"GAME_MODE"]];
    [features addItem:[NSMenuItem separatorItem]];
    // Much more logging from the game, at some cost in performance (swgl_debug_env in common.sh).
    NSMenuItem *debug = [self toggleItem:@"Debug Mode" key:@"DEBUG"];
    debug.toolTip = @"Detailed logs for troubleshooting, at some cost in performance. Turn on when asked to.";
    [features addItem:debug];
    [features addItem:[NSMenuItem separatorItem]];
    [features addItem:[[NSMenuItem alloc] initWithTitle:@"Changes apply the next time the game starts"
                                                 action:nil keyEquivalent:@""]];
    NSMenuItem *featuresItem = [[NSMenuItem alloc] initWithTitle:@"Features" action:nil keyEquivalent:@""];
    featuresItem.submenu = features;
    [mainMenu addItem:featuresItem];
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
