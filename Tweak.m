#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

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
    if ([s containsString:@"bootstrap"])              return YES;
    if ([s containsString:@"remote-config-resolver"]) return YES;
    if ([s containsString:@"/v3/unauth/"])            return YES;
    if ([s containsString:@"v1/customize"])           return YES;
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
    if ([s containsString:@"audio-ad"])               return YES;
    if ([s containsString:@"audio-ak.spotify"])       return YES;
    if ([s containsString:@"audio-ak-spotify"])       return YES;
    if ([s containsString:@"audio-ads-fa"])           return YES;
    if ([s containsString:@"gabo-receiver-service"])  return YES;
    if ([s containsString:@"adeventtracker"])         return YES;
    if ([s containsString:@"adclick"])                return YES;
    if ([s containsString:@"doubleclick"])            return YES;
    if ([s containsString:@"pagead"])                 return YES;
    if ([s containsString:@"GetPremiumPlanRow"])      return YES;
    if ([s containsString:@"GetYourPremiumBadge"])    return YES;
    if ([s containsString:@"on-demand-trial"])        return YES;
    if ([s containsString:@"opt-in-upsell"])          return YES;
    if ([s containsString:@"GetPlanOverview"])        return YES;
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
        NSLog(@"[SAB] bootstrap modified");
        return [result dataUsingEncoding:NSUTF8StringEncoding] ?: data;
    }
    return data;
}

#pragma mark - Network Hooks

static void hooked_didReceiveData_Core(id self, SEL _cmd, id session, id task, NSData *data) {
    NSURL *url = [[task originalRequest] URL] ?: [[task currentRequest] URL];
    if (isAdURL(url)) {
        NSLog(@"[SAB] blocked ad URL: %@", url.absoluteString);
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
        NSLog(@"[SAB] blocked ad URL (DLS): %@", url.absoluteString);
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
            swizzleMethod(dictCls, sel, dictHooks[i].hook, dictHooks[i].orig);
    }

    Class videoTrackCls = NSClassFromString(@"SPTVideoTrack");
    if (videoTrackCls)
        swizzleMethod(videoTrackCls, NSSelectorFromString(@"isAdvertisement"),
                (IMP)hooked_SPTVideoTrack_isAdvertisement, &_orig_SPTVideoTrack_isAdvertisement);

    Class betamaxCls = NSClassFromString(@"SPTVideoBetamaxPlayerSelector");
    if (betamaxCls)
        swizzleMethod(betamaxCls, NSSelectorFromString(@"isAd"),
                (IMP)hooked_SPTVideoBetamaxPlayerSelector_isAd, &_orig_SPTVideoBetamaxPlayerSelector_isAd);

    Class coordCls = NSClassFromString(@"SPTVideoCoordinatorStartCommand");
    if (coordCls)
        swizzleMethod(coordCls, NSSelectorFromString(@"isAdvertisement"),
                (IMP)hooked_SPTVideoCoordinatorStartCommand_isAd, &_orig_SPTVideoCoordinatorStartCommand_isAd);

    Class playerTrackCls = NSClassFromString(@"SPTPlayerTrackImplementation");
    if (!playerTrackCls) playerTrackCls = NSClassFromString(@"SPTPlayerTrack");
    if (playerTrackCls) {
        SEL isAdSel = NSSelectorFromString(@"isAd");
        SEL isAdvSel = NSSelectorFromString(@"isAdvertisement");
        if ([playerTrackCls instancesRespondToSelector:isAdSel])
            swizzleMethod(playerTrackCls, isAdSel, (IMP)hooked_SPTPlayerTrack_isAd, &_orig_SPTPlayerTrack_isAd);
        if ([playerTrackCls instancesRespondToSelector:isAdvSel])
            swizzleMethod(playerTrackCls, isAdvSel, (IMP)hooked_SPTPlayerTrack_isAd, NULL);
    }

    Class urlCls = [NSURL class];
    SEL isAdURLSel = NSSelectorFromString(@"spt_isAdURL");
    if ([urlCls instancesRespondToSelector:isAdURLSel])
        swizzleMethod(urlCls, isAdURLSel, (IMP)hooked_spt_isAdURL, &_orig_spt_isAdURL);

    Class coreCls = NSClassFromString(@"SPTCoreURLSessionDataDelegate");
    if (coreCls)
        swizzleMethod(coreCls, @selector(URLSession:dataTask:didReceiveData:),
                (IMP)hooked_didReceiveData_Core, &_orig_didReceiveData_Core);

    Class dlsCls = NSClassFromString(@"SPTDataLoaderService");
    if (dlsCls)
        swizzleMethod(dlsCls, @selector(URLSession:dataTask:didReceiveData:),
                (IMP)hooked_didReceiveData_DLS, &_orig_didReceiveData_DLS);
}
