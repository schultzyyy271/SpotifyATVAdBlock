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

// Music Video Bypass IMPs
static IMP _orig_ConfigProvider_boolValueForId          = NULL;
static IMP _orig_ObservableConfigProvider_boolValueForId = NULL;
static IMP _orig_ProductState_stringForKey              = NULL;
static IMP _orig_ProductState_objectForKeyedSubscript   = NULL;
static IMP _orig_VideoSurface_isEligibleForAttachment   = NULL;
static IMP _orig_VideoSurface_isPlayableForIdentity     = NULL;
static IMP _orig_PlayerStateUtils_isVideoDisabled       = NULL;
static IMP _orig_Track_isPremiumOnly                    = NULL;
static IMP _orig_PlayerState_restrictions               = NULL;
static IMP _orig_PlayerState_contextRestrictions        = NULL;
static IMP _orig_PlaybackIdentity_isRoyaltyMedia        = NULL;
static IMP _orig_PlaybackRequest_isRoyaltyMedia         = NULL;
static IMP _orig_StartCommandFactory_royaltyBypass      = NULL;
static IMP _orig_ContextPlayerProps_royaltyBypass       = NULL;
static IMP _orig_BetamaxSelector_kubrickMusicVideos     = NULL;
static IMP _orig_VideoPlayerConfig_productState         = NULL;

#pragma mark - Utility

static BOOL swizzleMethod(Class cls, SEL sel, IMP newImp, IMP *outOrig) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    if (outOrig) *outOrig = method_getImplementation(m);
    method_setImplementation(m, newImp);
    return YES;
}

static BOOL swizzleClassMethod(Class cls, SEL sel, IMP newImp, IMP *outOrig) {
    Method m = class_getClassMethod(cls, sel);
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
        // Music video specific
        @"\"video-streaming\":\"free\"":     @"\"video-streaming\":\"premium\"",
        @"\"video-enabled\":false":          @"\"video-enabled\":true",
        @"\"music-video-enabled\":false":    @"\"music-video-enabled\":true",
        @"\"can-play-music-videos\":false":  @"\"can-play-music-videos\":true",
        @"\"video-catalogue\":\"free\"":     @"\"video-catalogue\":\"premium\"",
    };

    for (NSString *from in replacements) {
        if ([result containsString:from]) {
            [result replaceOccurrencesOfString:from withString:replacements[from]
                                       options:0 range:NSMakeRange(0, result.length)];
            modified = YES;
        }
    }

    if (modified) {
        NSLog(@"[SpotifyATVAdBlock] bootstrap modified");
        return [result dataUsingEncoding:NSUTF8StringEncoding] ?: data;
    }
    return data;
}

#pragma mark - Network Hooks

static void hooked_didReceiveData_Core(id self, SEL _cmd, id session, id task, NSData *data) {
    NSURL *url = [[task originalRequest] URL] ?: [[task currentRequest] URL];
    if (isAdURL(url)) {
        NSLog(@"[SpotifyATVAdBlock] blocked ad URL: %@", url.absoluteString);
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
        NSLog(@"[SpotifyATVAdBlock] blocked ad URL (DLS): %@", url.absoluteString);
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

#pragma mark - Music Video Bypass Hooks

// Feature flag hook - disable premium check, enable music video features
static BOOL hooked_ConfigProvider_boolValueForId(id self, SEL _cmd, NSString *flagId, BOOL defaultValue) {
    if ([flagId isEqualToString:@"enable_music_video_premium_check"]) {
        NSLog(@"[SpotifyMusicVideo] bypassing premium check");
        return NO;
    }
    if ([flagId isEqualToString:@"enable_music_video_playback"]) {
        return YES;
    }
    if ([flagId containsString:@"music_video"]) {
        return YES;
    }
    return ((BOOL(*)(id,SEL,NSString*,BOOL))_orig_ConfigProvider_boolValueForId)(self, _cmd, flagId, defaultValue);
}

static BOOL hooked_ObservableConfigProvider_boolValueForId(id self, SEL _cmd, NSString *flagId, BOOL defaultValue) {
    if ([flagId isEqualToString:@"enable_music_video_premium_check"]) {
        NSLog(@"[SpotifyMusicVideo] bypassing premium check (observable)");
        return NO;
    }
    if ([flagId isEqualToString:@"enable_music_video_playback"]) {
        return YES;
    }
    if ([flagId containsString:@"music_video"]) {
        return YES;
    }
    return ((BOOL(*)(id,SEL,NSString*,BOOL))_orig_ObservableConfigProvider_boolValueForId)(self, _cmd, flagId, defaultValue);
}

// Product state hook - spoof premium catalogue
static NSString* hooked_ProductState_stringForKey(id self, SEL _cmd, NSString *key) {
    if ([key isEqualToString:@"catalogue"]) {
        return @"premium";
    }
    if ([key isEqualToString:@"type"]) {
        return @"premium";
    }
    if ([key isEqualToString:@"product"]) {
        return @"premium";
    }
    return ((NSString*(*)(id,SEL,NSString*))_orig_ProductState_stringForKey)(self, _cmd, key);
}

static id hooked_ProductState_objectForKeyedSubscript(id self, SEL _cmd, NSString *key) {
    if ([key isEqualToString:@"catalogue"]) {
        return @"premium";
    }
    return ((id(*)(id,SEL,NSString*))_orig_ProductState_objectForKeyedSubscript)(self, _cmd, key);
}

// Video surface eligibility hooks
static BOOL hooked_VideoSurface_isEligibleForAttachment(id self, SEL _cmd) {
    return YES;
}

static BOOL hooked_VideoSurface_isPlayableForIdentity(id self, SEL _cmd, id identity) {
    return YES;
}

// Video rendering disabled check
static BOOL hooked_PlayerStateUtils_isVideoDisabled(id self, SEL _cmd, id playerState) {
    return NO;
}

// Track premium check
static BOOL hooked_Track_isPremiumOnly(id self, SEL _cmd) {
    return NO;
}

// Player restrictions
static id hooked_PlayerState_restrictions(id self, SEL _cmd) {
    return nil;
}

static id hooked_PlayerState_contextRestrictions(id self, SEL _cmd) {
    return nil;
}

// Royalty media bypass - critical for music video playback
static BOOL hooked_PlaybackIdentity_isRoyaltyMedia(id self, SEL _cmd) {
    return NO;  // Not royalty media = no premium check for playback
}

static BOOL hooked_PlaybackRequest_isRoyaltyMedia(id self, SEL _cmd) {
    return NO;
}

static BOOL hooked_StartCommandFactory_royaltyBypass(id self, SEL _cmd) {
    return YES;  // Enable royalty bypass
}

static BOOL hooked_ContextPlayerProps_royaltyBypass(id self, SEL _cmd) {
    return YES;
}

// Kubrick player enabled for music videos
static BOOL hooked_BetamaxSelector_kubrickMusicVideos(id self, SEL _cmd) {
    return YES;  // Enable kubrick adaptive player for music videos
}

#pragma mark - Constructor

__attribute__((constructor))
static void SABInit(void) {
    NSLog(@"[SpotifyATVAdBlock] initializing...");

    // ========== Ad Blocking Hooks ==========

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

    // ========== Music Video Bypass Hooks ==========

    NSLog(@"[SpotifyMusicVideo] installing music video hooks...");

    // Feature flag providers
    Class configProviderCls = NSClassFromString(@"_TtC22RemoteConfigurationSDK25ConfigurationProviderImpl");
    if (configProviderCls) {
        SEL boolValueSel = NSSelectorFromString(@"boolValueForId:defaultValue:");
        if ([configProviderCls instancesRespondToSelector:boolValueSel]) {
            swizzleMethod(configProviderCls, boolValueSel,
                    (IMP)hooked_ConfigProvider_boolValueForId, &_orig_ConfigProvider_boolValueForId);
            NSLog(@"[SpotifyMusicVideo] hooked ConfigurationProviderImpl");
        }
    }

    Class observableConfigCls = NSClassFromString(@"_TtC22RemoteConfigurationSDK35ObservableConfigurationProviderImpl");
    if (observableConfigCls) {
        SEL boolValueSel = NSSelectorFromString(@"boolValueForId:defaultValue:");
        if ([observableConfigCls instancesRespondToSelector:boolValueSel]) {
            swizzleMethod(observableConfigCls, boolValueSel,
                    (IMP)hooked_ObservableConfigProvider_boolValueForId, &_orig_ObservableConfigProvider_boolValueForId);
            NSLog(@"[SpotifyMusicVideo] hooked ObservableConfigurationProviderImpl");
        }
    }

    // Product state - spoof premium catalogue
    Class productStateCls = NSClassFromString(@"SPTCoreProductState");
    if (productStateCls) {
        SEL stringForKeySel = NSSelectorFromString(@"stringForKey:");
        SEL objectSubSel = NSSelectorFromString(@"objectForKeyedSubscript:");
        if ([productStateCls instancesRespondToSelector:stringForKeySel]) {
            swizzleMethod(productStateCls, stringForKeySel,
                    (IMP)hooked_ProductState_stringForKey, &_orig_ProductState_stringForKey);
            NSLog(@"[SpotifyMusicVideo] hooked SPTCoreProductState stringForKey:");
        }
        if ([productStateCls instancesRespondToSelector:objectSubSel]) {
            swizzleMethod(productStateCls, objectSubSel,
                    (IMP)hooked_ProductState_objectForKeyedSubscript, &_orig_ProductState_objectForKeyedSubscript);
            NSLog(@"[SpotifyMusicVideo] hooked SPTCoreProductState objectForKeyedSubscript:");
        }
    }

    // Video surface eligibility
    Class videoSurfaceCls = NSClassFromString(@"SPTVideoSurfaceImpl");
    if (videoSurfaceCls) {
        SEL eligibleSel = NSSelectorFromString(@"isEligibleForAttachment");
        SEL playableSel = NSSelectorFromString(@"isPlayableForIdentity:");
        if ([videoSurfaceCls instancesRespondToSelector:eligibleSel]) {
            swizzleMethod(videoSurfaceCls, eligibleSel,
                    (IMP)hooked_VideoSurface_isEligibleForAttachment, &_orig_VideoSurface_isEligibleForAttachment);
            NSLog(@"[SpotifyMusicVideo] hooked SPTVideoSurfaceImpl isEligibleForAttachment");
        }
        if ([videoSurfaceCls instancesRespondToSelector:playableSel]) {
            swizzleMethod(videoSurfaceCls, playableSel,
                    (IMP)hooked_VideoSurface_isPlayableForIdentity, &_orig_VideoSurface_isPlayableForIdentity);
            NSLog(@"[SpotifyMusicVideo] hooked SPTVideoSurfaceImpl isPlayableForIdentity:");
        }
    }

    // Video rendering disabled check (class method)
    Class playerStateUtilsCls = NSClassFromString(@"SPTPlayerStateUtilities");
    if (playerStateUtilsCls) {
        SEL videoDisabledSel = NSSelectorFromString(@"isVideoRenderingLocallyDisabled:");
        if ([playerStateUtilsCls respondsToSelector:videoDisabledSel]) {
            swizzleClassMethod(playerStateUtilsCls, videoDisabledSel,
                    (IMP)hooked_PlayerStateUtils_isVideoDisabled, &_orig_PlayerStateUtils_isVideoDisabled);
            NSLog(@"[SpotifyMusicVideo] hooked SPTPlayerStateUtilities isVideoRenderingLocallyDisabled:");
        }
    }

    // Track premium only check
    Class trackImplCls = NSClassFromString(@"_TtC29Playlist_PlaylistPlatformImpl36PlaylistTrackEsperantoImplementation");
    if (trackImplCls) {
        SEL premiumOnlySel = NSSelectorFromString(@"isPremiumOnly");
        if ([trackImplCls instancesRespondToSelector:premiumOnlySel]) {
            swizzleMethod(trackImplCls, premiumOnlySel,
                    (IMP)hooked_Track_isPremiumOnly, &_orig_Track_isPremiumOnly);
            NSLog(@"[SpotifyMusicVideo] hooked PlaylistTrackEsperantoImplementation isPremiumOnly");
        }
    }

    // Player state restrictions
    Class playerStateCls = NSClassFromString(@"SPTPlayerStateImplementation");
    if (playerStateCls) {
        SEL restrictionsSel = NSSelectorFromString(@"restrictions");
        SEL contextRestrictionsSel = NSSelectorFromString(@"contextRestrictions");
        if ([playerStateCls instancesRespondToSelector:restrictionsSel]) {
            swizzleMethod(playerStateCls, restrictionsSel,
                    (IMP)hooked_PlayerState_restrictions, &_orig_PlayerState_restrictions);
            NSLog(@"[SpotifyMusicVideo] hooked SPTPlayerStateImplementation restrictions");
        }
        if ([playerStateCls instancesRespondToSelector:contextRestrictionsSel]) {
            swizzleMethod(playerStateCls, contextRestrictionsSel,
                    (IMP)hooked_PlayerState_contextRestrictions, &_orig_PlayerState_contextRestrictions);
            NSLog(@"[SpotifyMusicVideo] hooked SPTPlayerStateImplementation contextRestrictions");
        }
    }

    // ========== Additional Music Video Hooks (Royalty/Playback) ==========

    // Royalty media check - PlaybackIdentityImpl
    Class playbackIdentityCls = NSClassFromString(@"_TtC10BetamaxSDK20PlaybackIdentityImpl");
    if (playbackIdentityCls) {
        SEL isRoyaltySel = NSSelectorFromString(@"isRoyaltyMedia");
        if ([playbackIdentityCls instancesRespondToSelector:isRoyaltySel]) {
            swizzleMethod(playbackIdentityCls, isRoyaltySel,
                    (IMP)hooked_PlaybackIdentity_isRoyaltyMedia, &_orig_PlaybackIdentity_isRoyaltyMedia);
            NSLog(@"[SpotifyMusicVideo] hooked PlaybackIdentityImpl isRoyaltyMedia");
        }
    }

    // Royalty media check - PlaybackRequestImpl
    Class playbackRequestCls = NSClassFromString(@"_TtCC13BetamaxSDKAPI22PlaybackRequestFactoryP33_D84ACD925BDAD37D9EFF9097F93EA1D619PlaybackRequestImpl");
    if (playbackRequestCls) {
        SEL isRoyaltySel = NSSelectorFromString(@"isRoyaltyMedia");
        if ([playbackRequestCls instancesRespondToSelector:isRoyaltySel]) {
            swizzleMethod(playbackRequestCls, isRoyaltySel,
                    (IMP)hooked_PlaybackRequest_isRoyaltyMedia, &_orig_PlaybackRequest_isRoyaltyMedia);
            NSLog(@"[SpotifyMusicVideo] hooked PlaybackRequestImpl isRoyaltyMedia");
        }
    }

    // Royalty bypass - SPTVideoCoordinatorStartCommandFactory
    Class startCommandFactoryCls = NSClassFromString(@"SPTVideoCoordinatorStartCommandFactory");
    if (startCommandFactoryCls) {
        SEL royaltyBypassSel = NSSelectorFromString(@"listPlayerRoyaltyBypassEnabled");
        if ([startCommandFactoryCls instancesRespondToSelector:royaltyBypassSel]) {
            swizzleMethod(startCommandFactoryCls, royaltyBypassSel,
                    (IMP)hooked_StartCommandFactory_royaltyBypass, &_orig_StartCommandFactory_royaltyBypass);
            NSLog(@"[SpotifyMusicVideo] hooked SPTVideoCoordinatorStartCommandFactory listPlayerRoyaltyBypassEnabled");
        }
    }

    // Royalty bypass - ContextPlayerCoordinatorImplProperties
    Class contextPlayerPropsCls = NSClassFromString(@"SPTBetamax_ContextPlayerCoordinatorImplProperties");
    if (contextPlayerPropsCls) {
        SEL royaltyBypassSel = NSSelectorFromString(@"listPlayerRoyaltyBypassEnabled");
        if ([contextPlayerPropsCls instancesRespondToSelector:royaltyBypassSel]) {
            swizzleMethod(contextPlayerPropsCls, royaltyBypassSel,
                    (IMP)hooked_ContextPlayerProps_royaltyBypass, &_orig_ContextPlayerProps_royaltyBypass);
            NSLog(@"[SpotifyMusicVideo] hooked ContextPlayerCoordinatorImplProperties listPlayerRoyaltyBypassEnabled");
        }
    }

    // Kubrick adaptive player for music videos
    Class betamaxSelectorCls = NSClassFromString(@"SPTVideoBetamaxPlayerSelector");
    if (betamaxSelectorCls) {
        SEL kubrickMusicVideosSel = NSSelectorFromString(@"isKubrickAdaptiveOnContextPlayerMusicVideosEnabled");
        if ([betamaxSelectorCls instancesRespondToSelector:kubrickMusicVideosSel]) {
            swizzleMethod(betamaxSelectorCls, kubrickMusicVideosSel,
                    (IMP)hooked_BetamaxSelector_kubrickMusicVideos, &_orig_BetamaxSelector_kubrickMusicVideos);
            NSLog(@"[SpotifyMusicVideo] hooked SPTVideoBetamaxPlayerSelector isKubrickAdaptiveOnContextPlayerMusicVideosEnabled");
        }
    }

    NSLog(@"[SpotifyATVAdBlock] initialization complete");
}
