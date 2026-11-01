// CopilotCN — GitHub Copilot 桌面端汉化注入器
// 通过 DYLD_INSERT_LIBRARIES 注入，向 App 的 WKWebView 注入翻译脚本，
// 并通过 WKScriptMessageHandlerWithReply 提供双向命令通道（便于调试/抓文案）。
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#include <stdio.h>

static NSString *gDir = nil;
static NSString *gLogPath = nil;
static NSString *gDumpDir = nil;
static NSString *gQueueDir = nil;
static NSHashTable *gWebviews = nil;
static id gHandler = nil;
static int gDumpSeq = 0;
static int gCmdSeq = 0;

static void CNLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], s];
    FILE *f = fopen(gLogPath.UTF8String, "a");
    if (f) { fputs(line.UTF8String, f); fclose(f); }
}

static NSString *CNRead(NSString *name) {
    return [NSString stringWithContentsOfFile:[gDir stringByAppendingPathComponent:name]
                                     encoding:NSUTF8StringEncoding error:NULL];
}

#pragma mark - 消息接收（JS <-> 原生）

@interface CNHandler : NSObject <WKScriptMessageHandler, WKScriptMessageHandlerWithReply>
@end

@implementation CNHandler

- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message {
    [self handle:message.body reply:^(id r, NSString *e) {}];
}

- (void)userContentController:(WKUserContentController *)ucc
      didReceiveScriptMessage:(WKScriptMessage *)message
                 replyHandler:(void (^)(id _Nullable, NSString * _Nullable))replyHandler {
    [self handle:message.body reply:replyHandler];
}

- (void)handle:(id)body reply:(void (^)(id, NSString *))reply {
    @autoreleasepool {
        if (![body isKindOfClass:[NSDictionary class]]) return;
        NSString *kind = body[@"kind"];
        if ([kind isEqualToString:@"poll"]) {
            reply([self nextCommand], nil);
        } else if ([kind isEqualToString:@"cmdresult"]) {
            NSString *ident = body[@"id"] ?: @"?";
            NSString *value = [body[@"value"] description] ?: @"";
            NSMutableDictionary *out = [NSMutableDictionary dictionary];
            out[@"ok"] = body[@"ok"] ?: @NO;
            out[@"value"] = value;
            NSData *d = [NSJSONSerialization dataWithJSONObject:out options:0 error:NULL];
            [d writeToFile:[gQueueDir stringByAppendingPathComponent:[ident stringByAppendingString:@".result.json"]]
                atomically:YES];
            CNLog(@"cmd done: %@ ok=%@ len=%lu", ident, out[@"ok"], (unsigned long)value.length);
            reply(nil, nil);
        } else if ([kind isEqualToString:@"dump"]) {
            NSString *data = body[@"data"];
            if ([data isKindOfClass:[NSString class]]) {
                gDumpSeq++;
                NSString *name = [NSString stringWithFormat:@"%@/dump-%03d-%@.json", gDumpDir, gDumpSeq, body[@"tag"] ?: @"x"];
                [data writeToFile:name atomically:YES encoding:NSUTF8StringEncoding error:NULL];
                CNLog(@"dump saved: %@ (%lu bytes)", name.lastPathComponent, (unsigned long)data.length);
            }
            reply(nil, nil);
        } else if ([kind isEqualToString:@"log"]) {
            CNLog(@"JS: %@", body[@"msg"]);
            reply(nil, nil);
        } else {
            reply(nil, nil);
        }
    }
}

- (id)nextCommand {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [[fm contentsOfDirectoryAtPath:gQueueDir error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *n in names) {
        if (![n hasSuffix:@".json"] || [n rangeOfString:@".result"].location != NSNotFound) continue;
        if ([n hasPrefix:@"native-"]) continue;
        NSString *full = [gQueueDir stringByAppendingPathComponent:n];
        NSData *data = [NSData dataWithContentsOfFile:full];
        NSDictionary *obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        [fm removeItemAtPath:full error:NULL];
        if (![obj isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *out = [obj mutableCopy];
        out[@"id"] = n;
        gCmdSeq++;
        CNLog(@"cmd dispatch: %@ op=%@", n, obj[@"op"]);
        return out;
    }
    return nil;
}

@end

#pragma mark - WKWebView 注入

static id (*gOrigInitWithFrameConfig)(id, SEL, CGRect, WKWebViewConfiguration *);

static void CNAttachToConfiguration(WKWebViewConfiguration *cfg) {
    if (!cfg) return;
    if (!gHandler) gHandler = [CNHandler new];
    WKUserContentController *ucc = cfg.userContentController;
    if (!ucc) { ucc = [[WKUserContentController alloc] init]; cfg.userContentController = ucc; }
    @try {
        [ucc addScriptMessageHandlerWithReply:gHandler contentWorld:WKContentWorld.pageWorld name:@"copilotcn"];
    } @catch (NSException *e) { CNLog(@"addScriptMessageHandlerWithReply: %@", e); }

    NSString *dict = CNRead(@"dict.json") ?: @"{}";
    NSString *translator = CNRead(@"translator.js") ?: @"";
    NSString *bridge = CNRead(@"bridge.js") ?: @"";
    NSString *collector = CNRead(@"collector.js") ?: @"";
    NSString *src = [NSString stringWithFormat:
        @"(function(){try{window.__CN_DICT=%@;}catch(e){};\n%@\n%@\n%@})();", dict, translator, bridge, collector];
    WKUserScript *us = [[WKUserScript alloc] initWithSource:src
                                             injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                                          forMainFrameOnly:NO];
    [ucc addUserScript:us];
    CNLog(@"user script attached (%lu bytes)", (unsigned long)src.length);
}

static id CNInitWithFrameConfig(id self, SEL _cmd, CGRect frame, WKWebViewConfiguration *cfg) {
    @try { CNAttachToConfiguration(cfg); } @catch (NSException *e) { CNLog(@"attach exception: %@", e); }
    id wv = gOrigInitWithFrameConfig(self, _cmd, frame, cfg);
    if (wv) { @synchronized(gWebviews) { [gWebviews addObject:wv]; } }
    return wv;
}

#pragma mark - 本地化 AppKit 菜单

static const void *kCNOrigTitleKey = &kCNOrigTitleKey;

static void CNTranslateMenu(NSMenu *menu, NSDictionary *map) {
    if (!menu || !map) return;
    for (NSMenuItem *item in menu.itemArray) {
        NSString *t = item.title;
        NSString *orig = objc_getAssociatedObject(item, kCNOrigTitleKey);
        if (!orig && t.length) {
            objc_setAssociatedObject(item, kCNOrigTitleKey, t, OBJC_ASSOCIATION_COPY_NONATOMIC);
            orig = t;
        }
        NSString *want = map[orig ?: @""];
        if (want && ![item.title isEqualToString:want]) item.title = want;
        if (item.submenu) CNTranslateMenu(item.submenu, map);
    }
}

static void CNTranslateMenus(void) {
    static NSDictionary *map = nil;
    static NSDate *mapDate = nil;
    @try {
        NSString *path = [gDir stringByAppendingPathComponent:@"menu.json"];
        NSDate *m = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL][NSFileModificationDate];
        if (m && (!mapDate || ![m isEqualToDate:mapDate])) {
            NSData *d = [NSData dataWithContentsOfFile:path];
            if (d) { map = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL]; mapDate = m; }
        }
        if (!map) return;
        NSApplication *app = [NSApplication sharedApplication];
        if (!app) return;
        CNTranslateMenu(app.mainMenu, map);
    } @catch (NSException *e) { CNLog(@"menu: %@", e); }
}

static void CNRunEvalFile(NSString *path) {
    NSString *script = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    NSString *resultPath = [path stringByDeletingPathExtension];
    resultPath = [resultPath stringByAppendingString:@".result.json"];
    WKWebView *wv = nil;
    @synchronized(gWebviews) {
        for (WKWebView *v in gWebviews.allObjects) {
            if (v.URL.absoluteString.length > 0) { wv = v; break; }
        }
    }
    if (!wv) {
        [@"{\"ok\":false,\"value\":\"no webview\"}" writeToFile:resultPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        return;
    }
    NSString *target = wv.URL.absoluteString;
    CNLog(@"eval -> %@ : %.60@", target, script);
    [wv evaluateJavaScript:script ?: @"0" completionHandler:^(id result, NSError *error) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        out[@"ok"] = @(error == nil);
        NSString *s = nil;
        if (result) {
            s = [result isKindOfClass:[NSString class]] ? result : [result description];
        }
        out[@"value"] = s ?: (error ? error.localizedDescription : @"");
        NSData *d = [NSJSONSerialization dataWithJSONObject:out options:0 error:NULL];
        [d writeToFile:resultPath atomically:YES];
        CNLog(@"eval done ok=%d len=%lu", error == nil, (unsigned long)[(s ?: @"") length]);
    }];
}

static void CNPollEvalFiles(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [[fm contentsOfDirectoryAtPath:gQueueDir error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *n in names) {
        if (![n hasPrefix:@"eval-"] || ![n hasSuffix:@".js"]) continue;
        NSString *full = [gQueueDir stringByAppendingPathComponent:n];
        NSString *busy = [full stringByAppendingString:@".busy"];
        if ([fm moveItemAtPath:full toPath:busy error:NULL]) {
            CNRunEvalFile(busy);
        }
    }
}

#pragma mark - 原生菜单：导出 / 触发

static NSDictionary *CNMenuTree(NSMenu *menu) {
    NSMutableArray *items = [NSMutableArray array];
    for (NSMenuItem *it in menu.itemArray) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        d[@"title"] = it.title ?: @"";
        if (it.isSeparatorItem) d[@"separator"] = @YES;
        if (it.submenu) d[@"items"] = CNMenuTree(it.submenu);
        [items addObject:d];
    }
    return @{ @"title": menu.title ?: @"", @"items": items };
}

static BOOL CNMenuPerform(NSMenu *menu, NSString *title) {
    for (NSMenuItem *it in menu.itemArray) {
        if (it.isSeparatorItem) continue;
        if (it.submenu) { if (CNMenuPerform(it.submenu, title)) return YES; continue; }
        NSString *orig = objc_getAssociatedObject(it, kCNOrigTitleKey);
        BOOL match = (it.title.length && [it.title localizedCaseInsensitiveContainsString:title]) ||
                     (orig.length && [orig localizedCaseInsensitiveContainsString:title]);
        if (match && it.isEnabled) {
            if ([NSApp sendAction:it.action to:it.target from:it]) { CNLog(@"menu action fired: %@", it.title); return YES; }
        }
    }
    return NO;
}

static void CNPollNativeFiles(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [[fm contentsOfDirectoryAtPath:gQueueDir error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *n in names) {
        if (![n hasPrefix:@"native-"] || ![n hasSuffix:@".json"]) continue;
        if ([n rangeOfString:@".result"].location != NSNotFound) continue;
        NSString *full = [gQueueDir stringByAppendingPathComponent:n];
        NSData *data = [NSData dataWithContentsOfFile:full];
        [fm removeItemAtPath:full error:NULL];
        NSDictionary *req = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSString *op = req[@"op"];
        NSString *resultPath = [[full stringByDeletingPathExtension] stringByAppendingString:@".result.json"];
        NSMutableDictionary *res = [NSMutableDictionary dictionary];
        if ([op isEqualToString:@"menudump"]) {
            NSDictionary *tree = CNMenuTree(NSApp.mainMenu);
            NSData *d = [NSJSONSerialization dataWithJSONObject:tree options:NSJSONWritingPrettyPrinted error:NULL];
            [d writeToFile:[gDumpDir stringByAppendingPathComponent:@"menu.json"] atomically:YES];
            res[@"ok"] = @YES;
            res[@"value"] = @"menu dumped";
        } else if ([op isEqualToString:@"menuclick"]) {
            BOOL ok = CNMenuPerform(NSApp.mainMenu, req[@"title"] ?: @"");
            res[@"ok"] = @(ok);
            res[@"value"] = ok ? @"clicked" : @"not found";
        } else {
            res[@"ok"] = @NO;
            res[@"value"] = @"unknown native op";
        }
        NSData *d = [NSJSONSerialization dataWithJSONObject:res options:0 error:NULL];
        [d writeToFile:resultPath atomically:YES];
    }
}

static dispatch_source_t gPoller = nil;

static void CNStartPoller(void) {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    gPoller = timer;
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), NSEC_PER_SEC, 200 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{ CNTranslateMenus(); CNPollEvalFiles(); CNPollNativeFiles(); });
    dispatch_resume(timer);
}

#pragma mark - 初始化

static BOOL CNIsMainApp(void) {
    char buf[4096]; uint32_t size = sizeof(buf);
    if (_NSGetExecutablePath(buf, &size) != 0) return NO;
    NSString *exe = [NSString stringWithUTF8String:buf];
    if ([exe hasSuffix:@"/Contents/MacOS/github"]) return YES;
    return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.github.githubapp"];
}

__attribute__((constructor))
static void CNCtor(void) {
    @autoreleasepool {
        if (!CNIsMainApp()) return;
        const char *env = getenv("COPILOT_CN_DIR");
        NSString *dir = env ? [NSString stringWithUTF8String:env]
                            : [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/CopilotCN"];
        gDir = dir;
        gLogPath = [dir stringByAppendingPathComponent:@"copilot-cn.log"];
        gDumpDir = [dir stringByAppendingPathComponent:@"dumps"];
        gQueueDir = [dir stringByAppendingPathComponent:@"queue"];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:gDumpDir withIntermediateDirectories:YES attributes:nil error:NULL];
        [fm createDirectoryAtPath:gQueueDir withIntermediateDirectories:YES attributes:nil error:NULL];
        gWebviews = [NSHashTable weakObjectsHashTable];

        CNLog(@"==== injected into pid %d, dir=%@ ====", getpid(), dir);

        gOrigInitWithFrameConfig = (void *)method_getImplementation(
            class_getInstanceMethod(NSClassFromString(@"WKWebView"), @selector(initWithFrame:configuration:)));
        if (!gOrigInitWithFrameConfig) { CNLog(@"WKWebView not found, abort"); return; }
        method_setImplementation(class_getInstanceMethod(NSClassFromString(@"WKWebView"), @selector(initWithFrame:configuration:)),
                                 (IMP)CNInitWithFrameConfig);

        CNStartPoller();
    }
}
