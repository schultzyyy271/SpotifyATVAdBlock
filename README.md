# SpotifyATVAdBlock
AdBlock for Spotify on AppleTV


A Cydia Substrate / dylib tweak for **Spotify on Apple TV (tvOS)** that blocks ads and unlocks premium features by hooking into Spotify's Objective-C runtime.

Tested on **Spotify tvOS 9.1.28** and **9.1.36**.

---

## Features

- Blocks all audio ad streams at the network layer
- Patches bootstrap config to remove ads and spoof premium account flags
- Hooks all ad classification metadata methods
- Blocks video ads (Betamax/Kubrick video player)
- Pre-classifies ad URLs before they hit the network
- Unlocks premium-gated features via bootstrap JSON patching
- Fails gracefully — if a class or method isn't found, the hook is silently skipped without crashing

---

## How It Works

The tweak operates across five layers:

### 1. Network Layer
Hooks `SPTCoreURLSessionDataDelegate` and `SPTDataLoaderService` to intercept all outbound Spotify network requests and incoming responses at the session level, blocking ad audio streams before they reach the player.

### 2. Bootstrap Patching
Intercepts all `spclient.wg.spotify.com` config responses and rewrites key JSON fields on the fly:
- `"ads": true` → `"ads": false`
- `"player-license": "free"` → `"player-license": "premium"`
- `"product": "free"` → `"product": "premium"`
- `"account_type": "free"` → `"account_type": "premium"`
- Various other premium feature flags

### 3. Metadata Layer
Hooks all six `spt_metadata_*` category methods on `NSDictionary` to intercept ad track classification at the metadata level, preventing ad tracks from being identified and queued.

### 4. Player Layer
Hooks `SPTPlayerTrackImplementation.isAd`, `isAdvertisement`, and `SPTPlayerTrack` (fallback) to return `NO` for all tracks, including the `"-"` title ad detection pattern used by Spotify.

### 5. Video Ad Layer
Hooks `SPTVideoTrack`, `SPTVideoBetamaxPlayerSelector`, and `SPTVideoCoordinatorStartCommand` to block video ads from loading or playing.

---

## Coverage Table

| Layer | What's Hooked | Risk if Missing |
|---|---|---|
| Network | `SPTCoreURLSessionDataDelegate` + `SPTDataLoaderService` | Ad audio streams |
| Bootstrap | All config endpoints | `"ads":true` config |
| Metadata | All 6 `spt_metadata_*` methods | Ad track classification |
| Player | `SPTPlayerTrackImplementation.isAd/isAdvertisement` + `SPTPlayerTrack` "-" title ad | Ads playing through |
| Video | `SPTVideoTrack`, `SPTVideoBetamaxPlayerSelector`, `SPTVideoCoordinatorStartCommand` | Video ads |
| URL | `NSURL.spt_isAdURL` | URL pre-classification |

> Note: `hasAdBreakContext`, `adBreakContext`, and `positionInCurrentAdBreak` are protobuf field descriptors — read-only, don't gate playback, and cannot be meaningfully swizzled.

---

## Requirements

- A **decrypted** Spotify tvOS IPA (FairPlay-encrypted App Store IPAs will not work)
- macOS with Xcode command line tools
- `insert_dylib` or equivalent load command injection tool
- A signing script (e.g. `resign.sh`) and a valid provisioning profile / certificate
- Theos (for building from source)

---

## Building from Source

```bash
cd SpotifyATVAdBlock
make clean && make
```

This produces a `.deb` containing the compiled dylib.

---

## Installing

### 1. Inject the dylib into the IPA

Extract the dylib from the `.deb` and inject it into your decrypted Spotify IPA using `insert_dylib` or equivalent:

```bash
insert_dylib --all-yes @rpath/SpotifyATVAdBlock.dylib Payload/Spotify.app/Spotify
```

### 2. Sign the IPA

```bash
./resign.sh SpotifyATV.ipa SpotifyATV_signed.ipa
```

### 3. Install to Apple TV

```bash
xcrun devicectl device install app --device <YOUR_DEVICE_UDID> SpotifyATV_signed.ipa
```

Replace `<YOUR_DEVICE_UDID>` with your Apple TV's UDID.

---

## Updating for New Spotify Versions

The hooked classes are deep core infrastructure and have been stable across multiple Spotify tvOS versions. When a new IPA drops:

1. Run `strings` on the new binary and confirm the class names are still present
2. If all classes are found — just inject the existing dylib, no code changes needed
3. If a class name changed — it's a one-line fix in `Tweak.m`

The hooks all fail gracefully, so even if a class isn't found the app won't crash — that specific ad path just won't be blocked until updated.

---

## Known Limitations

- **Music videos** — the music video button is gated entirely server-side via a `relatedmusicvideos.v1` gRPC call. The server never sends video data to free accounts, so this cannot be unlocked via client-side hooking alone.
- **45-minute crash (9.1.28 only)** — a memory leak in the vanilla Spotify 9.1.28 binary causes a watchdog kill after extended sessions. This is unrelated to the tweak and is resolved by using a newer IPA (9.1.36+).
- Requires a **decrypted IPA** — cannot be used with App Store IPAs directly.

---

## Disclaimer

For educational and personal use only. This project is not affiliated with Spotify. Use at your own risk.
