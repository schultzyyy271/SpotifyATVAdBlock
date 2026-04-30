# SpotifyATVAdBlock

A dylib tweak for **Spotify on Apple TV (tvOS)** that hooks into Spotify’s Objective-C runtime to modify ad-related behavior.

Tested on **Spotify Version 9.1.42** **Memory Leak fixed on this version!**

-----

## How It Works

The tweak operates across five layers:

### 1. Network Layer

Hooks `SPTCoreURLSessionDataDelegate` and `SPTDataLoaderService` to intercept outbound network requests and incoming responses at the session level.

### 2. Bootstrap Patching

Intercepts `spclient.wg.spotify.com` config responses and rewrites JSON fields on the fly.

### 3. Metadata Layer

Hooks all six `spt_metadata_*` category methods on `NSDictionary` to intercept ad track classification at the metadata level.

### 4. Player Layer

Hooks `SPTPlayerTrackImplementation.isAd`, `isAdvertisement`, and `SPTPlayerTrack` including the `"-"` title detection pattern.

### 5. Video Ad Layer

Hooks `SPTVideoTrack`, `SPTVideoBetamaxPlayerSelector`, and `SPTVideoCoordinatorStartCommand`.

Hooks fail gracefully — if a class or method isn’t found, it’s silently skipped without crashing.

-----

## Requirements

- A decrypted Spotify tvOS IPA
- macOS with Xcode command line tools
- `insert_dylib` or equivalent
- A signing script and valid provisioning profile / certificate
- Theos (for building from source)

-----

## Building

```bash
make clean && make
```

## Installing

```bash
insert_dylib --all-yes @rpath/SpotifyATVAdBlock.dylib Payload/Spotify.app/Spotify
./resign.sh SpotifyATV.ipa SpotifyATV_signed.ipa
xcrun devicectl device install app --device <UDID> SpotifyATV_signed.ipa
```

-----

## Known Limitations/Issues

- Music videos are gated server-side and cannot be unlocked client-side.
- A memory leak in Spotify 9.1.28-9.1.40 causes watchdog kills after extended sessions; use 9.1.42+

-----

## Disclaimer

This project is for **personal and educational use only** and is not affiliated with Spotify. Use at your own risk.
