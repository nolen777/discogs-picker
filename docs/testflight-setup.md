# TestFlight CI Setup

This repo has a manual GitHub Actions workflow at `.github/workflows/testflight.yml`. It archives the app on the self-hosted macOS runner, exports an App Store Connect IPA, and optionally uploads it to TestFlight.

## Apple Developer

1. In Apple Developer > Certificates, Identifiers & Profiles, create an explicit App ID for `net.danielcrosby.discogspicker`.
2. Keep capabilities minimal. The app currently does not need iCloud, Push Notifications, Associated Domains, or App Groups.
3. Create or reuse an Apple Distribution certificate. Export the certificate and private key from Keychain Access as a `.p12` file and save the export password.
4. Create an App Store distribution provisioning profile for `net.danielcrosby.discogspicker` using that distribution certificate.
5. Download the `.mobileprovision` profile.

## App Store Connect

1. Create a new app record and select the `net.danielcrosby.discogspicker` bundle ID.
2. Set the platform to iOS and choose a SKU. The SKU can be any stable internal value, such as `discogs-picker-ios`.
3. In Users and Access > Integrations > App Store Connect API, create an API key with access to upload builds. `App Manager` is the simplest role for this.
4. Download the `.p8` API key and record the Key ID and Issuer ID.

## GitHub Secrets

Add these repository secrets:

- `APPLE_TEAM_ID`: your Apple Developer Team ID.
- `IOS_CERTIFICATE`: base64-encoded `.p12` distribution certificate.
- `IOS_CERTIFICATE_PWD`: password used when exporting the `.p12`.
- `IOS_PROVISIONING_PROFILE`: base64-encoded App Store `.mobileprovision` profile.
- `APP_STORE_CONNECT_API_KEY_ID`: App Store Connect API Key ID.
- `APP_STORE_CONNECT_API_ISSUER_ID`: App Store Connect API Issuer ID.
- `APP_STORE_CONNECT_API_KEY`: full `.p8` API key contents, including the begin and end lines.
- `IOS_SIGN_IDENTITY`: optional. Use this only if the certificate common name differs from `Apple Distribution: Daniel Crosby (UWJ88DX8WQ)`.

On macOS, encode files like this:

```sh
base64 -i path/to/distribution.p12 | pbcopy
base64 -i path/to/profile.mobileprovision | pbcopy
```

## First Run

Run the `iOS TestFlight` workflow manually from GitHub Actions with `skip_upload` checked first. If archive and export pass, run it again with `skip_upload` unchecked to upload to TestFlight.

The workflow uses `GITHUB_RUN_NUMBER` as the App Store build number, so every CI run gets a higher build number automatically.
