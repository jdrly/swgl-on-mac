// App updates with Sparkle, part of libswglmenus.dylib (src/native/swglupdates.m).

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SWGLUpdates : NSObject <NSMenuItemValidation>

// Starts Sparkle for the app bundle around `resources` (on the main thread). nil without
// updates: Sparkle.framework missing, or this process is not registered as the app.
+ (nullable instancetype)startWithResources:(NSString *)resources gameFolder:(NSString *)gameFolder;

// SWGL on Mac menu: "Check for Updates…". Automatic checks are switched in the Settings
// window (SUEnableAutomaticChecks in the app's defaults).
- (NSMenuItem *)checkForUpdatesItem;

@end

// The Java shutdown hook (Launcher.java): while an update is ready to install, Sparkle installs
// it as soon as this process ends. If the game is still running then, wait for it to quit, so
// the app is never replaced under it. Returns at once otherwise. Any thread.
void SWGLUpdatesHoldExit(void);

NS_ASSUME_NONNULL_END
