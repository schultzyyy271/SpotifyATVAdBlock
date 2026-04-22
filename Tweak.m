#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ════════════════════════════════════════════════════════════════════════
// SpotifyATVAdBlock v31
//
// FIXES vs v30:
//   1. Hooks installed at 0.0s (no delay) — eliminates race condition
//      where 1 ad slips through before bootstrap is patched on cold start
//   2. Broader bootstrap URL matching — catches spclient.wg.spotify.com
//      and any /v1/ endpoint that returns player config
//   3. isAdURL now also matches audio-ak CDN patterns and gabo endpoints
//   4. Added SPTPlayerTrackImplementation.isAd hook (catches the "-" title ad)
//   5. Added hook on NSDictionary spt_metadata_isAd (separate from isAdvertisement)
//   6. modifyBootstrapData now also flips "streaming-rules":"free" and
//      "playback-restrictions" ad flags
// ════════════════════════════════════════════════════════════════════════

#pragma mark - Stored IMPs

static IMP _orig_spt_metadata_isAdvertisement           = NULL;
static IMP _orig_spt_metadata_isPodcastAdvertisement    = NULL;
static IMP _orig_spt_metadata_isSkippableAdvertisement  = NULL;
static IMP _orig_spt_metadata_isCanvasAd                = NULL;
static IMP _orig_spt_metadata_isFullScreenAdvertisement = NULL;
static IMP _orig_spt_metadata_isAd                      = NULL;
static IMP _orig_SPTVideoTrack_isAdvertisement          = NULL;
static IMP _orig_SPTVideoBetamaxPlayerSelector_isAd     = NULL;
static IMP _orig_SPTVideoCoordinatorStartCommand_isAd   = NULL;
static IMP _orig_SPTPlayerTrack_isAd                    = NULL;
static IMP _orig_spt_isAdURL                            = NULL;
static IMP _orig_didReceiveData_Core                    = NULL;
static IMP _orig_didReceiveData_DLS                     = NULL;

#pragma mark - Utility

static BOOL swizzleMethod(Class cls, SEL sel, IMP newImp, IMP *outOrig) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    if (outOrig) *outOrig = method_getImplementation(m);
    method_setImplementation(m, newImp);
    return YES;
}

#pragma mark - URL Classification

static BOOL isBootstrapURL(NSURL *url) {
    if (!url) return NO;
    NSString *s = url.absoluteString;
    // Original patterns
    if ([s containsString:@"bootstrap"])              return YES;
    if ([s containsString:@"remote-config-resolver"]) return YES;
    if ([s containsString:@"/v3/unauth/"])            return YES;
    if ([s containsString:@"v1/customize"])           return YES;
    // Additional config endpoints that return player-license/ads flags
    if ([s containsString:@"spclient.wg.spotify.com"]) return YES;
    if ([s containsString:@"/v1/config"])             return YES;
    if ([s containsString:@"/v2/config"])             return YES;
    if ([s containsString:@"clienttoken"])            return YES;
    if ([s containsString:@"apresolve"])              return YES;
    return NO;
}

static BOOL isAdURL(NSURL *url) {
    if (!url) return NO;
    NSString *s = url.absoluteString;
    // Audio ad CDN endpoints
    if ([s containsString:@"audio-ad"])               return YES;
    if ([s containsString:@"audio-ak.spotify"])       return YES;
    if ([s containsString:@"audio-ak-spotify"])       return YES;
    if ([s containsString:@"audio-ads-fa"])           return YES;
    // Ad tracking / analytics
    if ([s containsString:@"gabo-receiver-service"])  return YES;
    if ([s containsString:@"adeventtracker"])         return YES;
    if ([s containsString:@"adclick"])                return YES;
    if ([s containsString:@"doubleclick"])            return YES;
    if ([s containsString:@"pagead"])                 return YES;
    // Upsell endpoints
    if ([s containsString:@"GetPremiumPlanRow"])      return YES;
    if ([s containsString:@"GetYourPremiumBadge"])    return YES;
    if ([s containsString:@"on-demand-trial"])        return YES;
    if ([s containsString:@"opt-in-upsell"])          return YES;
    if ([s containsString:@"GetPlanOverview"])        return YES;
    // Ad slots / breaks
    if ([s containsString:@"/ads/"])                  return YES;
    if ([s containsString:@"ad-logic"])               return YES;
    return NO;
}

#pragma mark - Bootstrap Modification

static NSData *modifyBootstrapData(NSData *data) {
    if (!data || data.length == 0 || data.length > 2 * 1024 * 1024) return data;
    const uint8_t *bytes = data.bytes;
    if (bytes[0] < 0x20 && bytes[0] != 0x09 && bytes[0] != 0x0A && bytes[0] != 0x0D) return data;

    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!str) return data;

    NSMutableString *result = [str mutableCopy];
    BOOL modified = NO;

    NSDictionary *replacements = @{
        @"\"free\"":                         @"\"premium\"",
        @"\"open\"":                         @"\"premium\"",
        @"\"ads\":\"1\"":                    @"\"ads\":\"0\"",
        @"\"ads\":true":                     @"\"ads\":false",
        @"\"type\":\"free\"":                @"\"type\":\"premium\"",
        @"\"type\":\"open\"":                @"\"type\":\"premium\"",
        @"\"catalogue\":\"free\"":           @"\"catalogue\":\"premium\"",
        @"\"on-demand\":false":              @"\"on-demand\":true",
        @"\"on-demand-set\":false":          @"\"on-demand-set\":true",
        @"\"player-license\":\"free\"":      @"\"player-license\":\"premium\"",
        @"\"player-license-v2\":\"free\"":   @"\"player-license-v2\":\"premium\"",
        @"\"streaming-rules\":\"free\"":     @"\"streaming-rules\":\"premium\"",
        @"\"shuffle-eligible\":false":       @"\"shuffle-eligible\":true",
        @"\"ad_free_music_listening\":false": @"\"ad_free_music_listening\":true",
        @"\"play_songs_in_any_order\":false": @"\"play_songs_in_any_order\":true",
        // v31: additional flags
        @"\"show-ads\":true":                @"\"show-ads\":false",
        @"\"audio-ads\":true":               @"\"audio-ads\":false",
        @"\"ads-enabled\":true":             @"\"ads-enabled\":false",
        @"\"playback-restrictions\":true":   @"\"playback-restrictions\":false",
    };

    for (NSString *from in replacements) {
        if ([result containsString:from]) {
            [result replaceOccurrencesOfString:from withString:replacements[from]
                                       options:0 range:NSMakeRange(0, result.length)];
            modified = YES;
        }
    }

    if (modified) {
        NSLog(@"[SAB] ✅ Bootstrap modified");
        return [result dataUsingEncoding:NSUTF8StringEncoding] ?: data;
    }
    return data;
}

#pragma mark - Network Hooks

static void hooked_didReceiveData_Core(id self, SEL _cmd, id session, id task, NSData *data) {
    NSURL *url = [[task originalRequest] URL] ?: [[task currentRequest] URL];
    if (isAdURL(url)) {
        NSLog(@"[SAB] 🚫 Blocked ad URL: %@", url.absoluteString);
        return;
    }
    if (isBootstrapURL(url)) {
        NSData *modified = modifyBootstrapData(data);
        ((void(*)(id,SEL,id,id,NSData*))_orig_didReceiveData_Core)(self,_cmd,session,task,modified);
        return;
    }
    ((void(*)(id,SEL,id,id,NSData*))_orig_didReceiveData_Core)(self,_cmd,session,task,data);
}

static void hooked_didReceiveData_DLS(id self, SEL _cmd, id session, id task, NSData *data) {
    NSURL *url = [[task originalRequest] URL] ?: [[task currentRequest] URL];
    if (isAdURL(url)) {
        NSLog(@"[SAB] 🚫 Blocked ad URL (DLS): %@", url.absoluteString);
        return;
    }
    if (isBootstrapURL(url)) {
        NSData *modified = modifyBootstrapData(data);
        ((void(*)(id,SEL,id,id,NSData*))_orig_didReceiveData_DLS)(self,_cmd,session,task,modified);
        return;
    }
    ((void(*)(id,SEL,id,id,NSData*))_orig_didReceiveData_DLS)(self,_cmd,session,task,data);
}

#pragma mark - ObjC Ad Detection Hooks

static BOOL hooked_spt_metadata_isAdvertisement(id self, SEL _cmd)           { return NO; }
static BOOL hooked_spt_metadata_isPodcastAdvertisement(id self, SEL _cmd)    { return NO; }
static BOOL hooked_spt_metadata_isSkippableAdvertisement(id self, SEL _cmd)  { return NO; }
static BOOL hooked_spt_metadata_isCanvasAd(id self, SEL _cmd)                { return NO; }
static BOOL hooked_spt_metadata_isFullScreenAdvertisement(id self, SEL _cmd) { return NO; }
static BOOL hooked_spt_metadata_isAd(id self, SEL _cmd)                      { return NO; }
static BOOL hooked_SPTVideoTrack_isAdvertisement(id self, SEL _cmd)          { return NO; }
static BOOL hooked_SPTVideoBetamaxPlayerSelector_isAd(id self, SEL _cmd)     { return NO; }
static BOOL hooked_SPTVideoCoordinatorStartCommand_isAd(id self, SEL _cmd)   { return NO; }
static BOOL hooked_SPTPlayerTrack_isAd(id self, SEL _cmd)                    { return NO; }
static BOOL hooked_spt_isAdURL(id self, SEL _cmd)                            { return NO; }

#pragma mark - Constructor

__attribute__((constructor))
static void SABInit(void) {
    NSLog(@"[SAB] ════════════════════════════════════════════");
    NSLog(@"[SAB] SpotifyATVAdBlock v31");
    NSLog(@"[SAB] ════════════════════════════════════════════");

    // v31: No delay — install hooks immediately to catch first bootstrap request
    // NSDictionary ad metadata hooks
    Class dictCls = [NSDictionary class];
    struct { const char *name; IMP hook; IMP *orig; } dictHooks[] = {
        {"spt_metadata_isAdvertisement",           (IMP)hooked_spt_metadata_isAdvertisement,           &_orig_spt_metadata_isAdvertisement},
        {"spt_metadata_isPodcastAdvertisement",    (IMP)hooked_spt_metadata_isPodcastAdvertisement,    &_orig_spt_metadata_isPodcastAdvertisement},
        {"spt_metadata_isSkippableAdvertisement",  (IMP)hooked_spt_metadata_isSkippableAdvertisement,  &_orig_spt_metadata_isSkippableAdvertisement},
        {"spt_metadata_isCanvasAd",                (IMP)hooked_spt_metadata_isCanvasAd,                &_orig_spt_metadata_isCanvasAd},
        {"spt_metadata_isFullScreenAdvertisement", (IMP)hooked_spt_metadata_isFullScreenAdvertisement, &_orig_spt_metadata_isFullScreenAdvertisement},
        {"spt_metadata_isAd",                      (IMP)hooked_spt_metadata_isAd,                      &_orig_spt_metadata_isAd},
    };
    for (int i = 0; i < 6; i++) {
        SEL sel = NSSelectorFromString(@(dictHooks[i].name));
        if ([dictCls instancesRespondToSelector:sel])
            if (swizzleMethod(dictCls, sel, dictHooks[i].hook, dictHooks[i].orig))
                NSLog(@"[SAB] ✅ %s", dictHooks[i].name);
    }

    // Video class hooks
    Class videoTrackCls = NSClassFromString(@"SPTVideoTrack");
    if (videoTrackCls)
        if (swizzleMethod(videoTrackCls, NSSelectorFromString(@"isAdvertisement"),
                (IMP)hooked_SPTVideoTrack_isAdvertisement, &_orig_SPTVideoTrack_isAdvertisement))
            NSLog(@"[SAB] ✅ SPTVideoTrack.isAdvertisement");

    Class betamaxCls = NSClassFromString(@"SPTVideoBetamaxPlayerSelector");
    if (betamaxCls)
        if (swizzleMethod(betamaxCls, NSSelectorFromString(@"isAd"),
                (IMP)hooked_SPTVideoBetamaxPlayerSelector_isAd, &_orig_SPTVideoBetamaxPlayerSelector_isAd))
            NSLog(@"[SAB] ✅ SPTVideoBetamaxPlayerSelector.isAd");

    Class coordCls = NSClassFromString(@"SPTVideoCoordinatorStartCommand");
    if (coordCls)
        if (swizzleMethod(coordCls, NSSelectorFromString(@"isAdvertisement"),
                (IMP)hooked_SPTVideoCoordinatorStartCommand_isAd, &_orig_SPTVideoCoordinatorStartCommand_isAd))
            NSLog(@"[SAB] ✅ SPTVideoCoordinatorStartCommand.isAdvertisement");

    // v31: SPTPlayerTrackImplementation - catches the "-" title ad slot
    Class playerTrackCls = NSClassFromString(@"SPTPlayerTrackImplementation");
    if (!playerTrackCls) playerTrackCls = NSClassFromString(@"SPTPlayerTrack");
    if (playerTrackCls) {
        SEL isAdSel = NSSelectorFromString(@"isAd");
        SEL isAdvSel = NSSelectorFromString(@"isAdvertisement");
        if ([playerTrackCls instancesRespondToSelector:isAdSel])
            if (swizzleMethod(playerTrackCls, isAdSel, (IMP)hooked_SPTPlayerTrack_isAd, &_orig_SPTPlayerTrack_isAd))
                NSLog(@"[SAB] ✅ SPTPlayerTrack.isAd");
        if ([playerTrackCls instancesRespondToSelector:isAdvSel])
            swizzleMethod(playerTrackCls, isAdvSel, (IMP)hooked_SPTPlayerTrack_isAd, NULL);
    }

    // v31: hook spt_isAdURL on NSURL category — closes gap where URL
    // classification could gate ad fetching before network hooks fire
    Class urlCls = [NSURL class];
    SEL isAdURLSel = NSSelectorFromString(@"spt_isAdURL");
    if ([urlCls instancesRespondToSelector:isAdURLSel])
        if (swizzleMethod(urlCls, isAdURLSel, (IMP)hooked_spt_isAdURL, &_orig_spt_isAdURL))
            NSLog(@"[SAB] ✅ NSURL.spt_isAdURL");

    // Network hooks
    Class coreCls = NSClassFromString(@"SPTCoreURLSessionDataDelegate");
    if (coreCls)
        if (swizzleMethod(coreCls, @selector(URLSession:dataTask:didReceiveData:),
                (IMP)hooked_didReceiveData_Core, &_orig_didReceiveData_Core))
            NSLog(@"[SAB] ✅ SPTCoreURLSessionDataDelegate");

    Class dlsCls = NSClassFromString(@"SPTDataLoaderService");
    if (dlsCls)
        if (swizzleMethod(dlsCls, @selector(URLSession:dataTask:didReceiveData:),
                (IMP)hooked_didReceiveData_DLS, &_orig_didReceiveData_DLS))
            NSLog(@"[SAB] ✅ SPTDataLoaderService");

    NSLog(@"[SAB] ════════════════════════════════════════════");
    NSLog(@"[SAB] Init complete");
}
