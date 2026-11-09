// gen1recomp iOS: keep SDL off AirPlay / external-display scenes.
//
// THE WHITE TV.  Reported from play: AirPlay screen mirroring of the iOS build
// "just shows a white screen" on the TV.
//
// SDL 3.4.10 (the SDL3.xcframework in love-apple-dependencies a552263, which
// the pinned LOVE b7daef0 links) runs UIApplicationMain with
// SDLUIKitSceneDelegate as the app delegate, and that class implements
// application:configurationForConnectingSceneSession:options:, so iOS treats
// the app as scene-based.  A scene-based app is handed a SECOND scene when a
// TV is attached (role UIWindowSceneSessionRoleExternalDisplay[NonInteractive])
// and iOS mirrors the phone onto it only while the app leaves that scene
// alone.  SDL 3.4.10 does not leave it alone: its
// scene:willConnectToSession:options: treats every scene as the app's main
// one -- it puts a launch window on it (LOVE's "Launch Screen.xib", whose
// background is white), schedules postFinishLaunch (which calls the app's
// main function AGAIN), and its sceneWillResignActive / sceneDidEnterBackground
// for that scene send the whole app background events (LOVE then stops
// drawing via Graphics::setActive(false)).
//
// Upstream SDL fixed exactly this after 3.4.10, in commit 6f34ce4d (2026-10-23,
// "Don't re-launch the application for external display scenes on iOS"): skip
// external-display scenes in willConnect and in the four lifecycle callbacks,
// and never start main twice.  The SDL we link is a prebuilt framework, so the
// same rule is applied here, at run time, by wrapping those five methods of
// SDLUIKitSceneDelegate before UIApplicationMain connects any scene.  A newer
// SDL that already carries the fix is unaffected: the checks are the same.
//
// With the external scene left empty iOS mirrors the phone (TV / CAST =
// MIRROR, the default).  BOTTOM and TOP put a window on that scene themselves:
// GRCastBridge.swift finds the scene through UIApplication.connectedScenes and
// UIScene notifications, so nothing here needs to talk to it.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL GRSceneGuardInstalled = NO;
static BOOL GRMainSceneStarted = NO;

static BOOL GRIsExternalDisplayScene(UIScene *scene)
{
    NSString *role = scene.session.role;
    if (role == nil) {
        return NO;
    }
    if (@available(iOS 16.0, *)) {
        if ([role isEqualToString:UIWindowSceneSessionRoleExternalDisplayNonInteractive]) {
            return YES;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if ([role isEqualToString:UIWindowSceneSessionRoleExternalDisplay]) {
        return YES;
    }
#pragma clang diagnostic pop
    return NO;
}

static void GRWrapWillConnect(Class cls)
{
    SEL sel = @selector(scene:willConnectToSession:options:);
    Method method = class_getInstanceMethod(cls, sel);
    if (method == NULL) {
        NSLog(@"GRSceneGuard: %@ has no scene:willConnectToSession:options:", cls);
        return;
    }
    typedef void (*GRWillConnectFn)(id, SEL, UIScene *, UISceneSession *, UISceneConnectionOptions *);
    GRWillConnectFn original = (GRWillConnectFn)method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(
        ^(id delegate, UIScene *scene, UISceneSession *session, UISceneConnectionOptions *options) {
        if (GRIsExternalDisplayScene(scene)) {
            // Leave it empty so the system mirrors the phone onto it.
            NSLog(@"GRSceneGuard: external display scene connected (%@); left to iOS",
                  scene.session.role);
            return;
        }
        if (GRMainSceneStarted) {
            // The game is already running: never run main twice.  Hand any
            // URLs to SDL the way its own (fixed) delegate does.
            SEL handle = NSSelectorFromString(@"handleURL:");
            if ([delegate respondsToSelector:handle]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                for (NSUserActivity *activity in options.userActivities) {
                    if (activity.webpageURL) {
                        [delegate performSelector:handle withObject:activity.webpageURL];
                    }
                }
                for (UIOpenURLContext *context in options.URLContexts) {
                    [delegate performSelector:handle withObject:context.URL];
                }
#pragma clang diagnostic pop
            }
            return;
        }
        GRMainSceneStarted = YES;
        original(delegate, sel, scene, session, options);
    });
    method_setImplementation(method, replacement);
}

static void GRWrapLifecycle(Class cls, SEL sel)
{
    Method method = class_getInstanceMethod(cls, sel);
    if (method == NULL) {
        return;
    }
    typedef void (*GRSceneFn)(id, SEL, UIScene *);
    GRSceneFn original = (GRSceneFn)method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^(id delegate, UIScene *scene) {
        if (GRIsExternalDisplayScene(scene)) {
            // A TV scene going inactive is not the app going to background.
            return;
        }
        original(delegate, sel, scene);
    });
    method_setImplementation(method, replacement);
}

static BOOL GRInstallSceneGuard(void)
{
    if (GRSceneGuardInstalled) {
        return YES;
    }
    Class cls = NSClassFromString(@"SDLUIKitSceneDelegate");
    if (cls == Nil) {
        return NO;
    }
    GRSceneGuardInstalled = YES;
    GRWrapWillConnect(cls);
    GRWrapLifecycle(cls, @selector(sceneDidBecomeActive:));
    GRWrapLifecycle(cls, @selector(sceneWillResignActive:));
    GRWrapLifecycle(cls, @selector(sceneWillEnterForeground:));
    GRWrapLifecycle(cls, @selector(sceneDidEnterBackground:));
    NSLog(@"GRSceneGuard: installed on SDLUIKitSceneDelegate");
    return YES;
}

// Before main(): SDL3.framework is a dependency of the app binary, so its
// classes are registered by the time this image's constructors run.  If the
// class is somehow not there yet, try again when launching finishes, which is
// still before UIKit connects the first scene.
__attribute__((constructor))
static void GRSceneGuardBoot(void)
{
    if (GRInstallSceneGuard()) {
        return;
    }
    __block id token = nil;
    token = [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        if (!GRInstallSceneGuard()) {
            NSLog(@"GRSceneGuard: SDLUIKitSceneDelegate not found; external displays unguarded");
        }
        if (token != nil) {
            [[NSNotificationCenter defaultCenter] removeObserver:token];
            token = nil;
        }
    }];
}
