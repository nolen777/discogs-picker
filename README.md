# Crate Shuffle

A tiny SwiftUI iOS app that syncs a Discogs collection, caches it locally, and picks a random record to play.

## Setup

1. Open `DiscogsPicker.xcodeproj` in Xcode.
2. Create a Discogs personal access token from Discogs account settings under Developers.
3. Run the app and enter your Discogs username plus token.
4. Tap `Sync Collection`.

After sync, `Pick Another` chooses from the local cache, so it does not hit the Discogs API on every shuffle. Cached data is used for up to six hours.

## Build

From the repo:

```sh
xcodebuild -project DiscogsPicker.xcodeproj -scheme DiscogsPicker -configuration Debug -sdk iphoneos -destination generic/platform=iOS -derivedDataPath .derivedData CODE_SIGNING_ALLOWED=NO build
```

## TestFlight

The GitHub Actions workflow in `.github/workflows/testflight.yml` archives and uploads builds to TestFlight from the self-hosted macOS runner. See `docs/testflight-setup.md` for the Apple Developer and GitHub secrets checklist.
