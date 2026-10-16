# Ozyy for iPhone and iPad

Native UIKit application project with the existing Ozyy workspace inside WKWebView, native Chat/Projects/Models tabs, Apple system-browser authentication, native file sharing, launch branding and app-switcher privacy cover. This is an iOS application source project, not a bookmark or a compiled IPA. Its chat/editor UI continues to come from the existing website; it is not a rewrite of those screens in UIKit.

## Current release status

**Not yet compiled, signed, installed or released.** The local Windows PC has no macOS/Xcode toolchain or Apple signing identity. The free personal-install route now has a manual GitHub macOS build workflow and an unsigned IPA packager. See [SIDELOAD.md](SIDELOAD.md). A cloud build still needs to pass, then the owner must sign the result using their own Apple Account in Sideloadly. Local Windows device detection has not yet reported an iPhone. No paid service, account, or subscription has been created.

The website's default `ios-release.json` has `ready: false`; `/install/ios/manifest.plist` returns an honest 503. It does not fabricate an iPhone installation. The existing Windows download and PWA remain separate.

The sign-in support and gated installation endpoints were deployed on October 16, 2026 to the existing ozyy-platform project, deployment `dpl_4ReVrksvmFQWGBWvVPuEGHzLXxY2`, READY and promoted to ozyy.xyz. The production backend was backed up and restarted gracefully. Existing accounts, model keys and spending allowances were preserved. Production status verified all 20 models and Google/Resend/Discord availability. An anonymous native-auth request returns 401; the unsigned install manifest returns 503 with no-store. These support-endpoint checks do not certify the uncompiled Swift app.

Verification: 62 backend tests and 14 install/offline tests passed; backend type checking and the local/remote frontend builds passed. Project plist files, Xcode reference IDs, native icon files and release-script Python syntax were checked. An isolated browser account approved a connection and produced the expected native return link; its original verifier exchanged it for an HttpOnly session successfully. The native Xcode build checker explicitly reported that macOS/Xcode are unavailable. No IPA, native-device installation or native UI performance has been tested.

## Free installation on a personal iPhone

Use the client-only GitHub repository and its manual `ios-sideload.yml` workflow. It runs `node scripts/build.mjs --unsigned` on a standard macOS runner, packages the compiled arm64 device application and verifies it before uploading a one-day artifact. No signing credentials are supplied to GitHub. Use the account's free Actions allowance only, with a $0 hard spending budget. Then use Sideloadly on Windows to sign and install the IPA with an existing free Apple Account. Signing expires after seven days and must be refreshed. This path does not enable the public OTA manifest or mark `ios-release.json` ready.

## Signed ad-hoc distribution using an existing membership

Use an existing Mac with Xcode and an authorized Apple signing identity. The build command never registers an account, buys signing, automatically provisions a new device, or uses a borrowed enterprise certificate. For ad-hoc distribution, each intended device must already be registered in the provisioning profile. This does not provide unrestricted public installation for every iPhone, and therefore does not satisfy the original zero-account/no-setup requirement by itself.

On the Mac:

1. Open `Ozyy.xcodeproj` or run `node scripts/build.mjs --simulator` to compile and test the simulator build.
2. Set `OZYY_APPLE_TEAM_ID` to the existing team, and `OZYY_IOS_EXPORT_OPTIONS` to an existing export-options plist for the intended authorized distribution method.
3. Run `node scripts/build.mjs`. Xcode must already have access to the corresponding signing identity and profiles. Output is `build/export/Ozyy.ipa` if signing/export succeeds.
4. Run `python3 scripts/prepare-release.py build/export/Ozyy.ipa --output build/release` on the Mac. This verifies code signing against an Apple anchor, app identity, device provisioning, profile/entitlement consistency and signing expiry. Only valid ad-hoc releases are accepted. It prepares an immutable IPA filename and public release metadata. No credentials or registered device IDs are written into that metadata.
5. After actual installation/authentication/download testing on a provisioned iPhone, put the verified IPA in the existing backend storage `downloads` directory and its generated `ios-release.json` at `apps/web/lib/ios-release.json`. These are ordinary deploy artifacts; private signing keys/profiles must never be uploaded. The existing deployment can then enable the real `itms-services` button. Until those artifacts exist, it remains unavailable. This final publishing step is not completed here.

## Authentication and privacy

The app creates a random verifier and SHA-256 challenge in memory. The system authentication browser opens only `https://ozyy.xyz/native/sign-in`, using the existing Google/Discord/Resend sign-in. After explicit account approval, a non-secret callback returns to the app. Only the original verifier can exchange that approval for the normal HttpOnly session cookie. Exchange is single use, expires after five minutes, and is transactional. The native client rejects redirects and transfers the cookie through WKHTTPCookieStore, never through JavaScript. Web browser CSRF checks are unchanged.

The native bridge accepts only a fixed sign-in message from the main frame on the exact HTTPS Ozyy origin. It exposes no filesystem, arbitrary commands, API keys, or raw tokens. External sites open separately, insecure navigation is blocked, and existing generated previews remain sandboxed. Native shared downloads are limited and stored in protected temporary directories, then deleted after sharing or next launch. Native API requests use ephemeral URLSession storage. The existing website API privacy and credit/budget controls still apply.

Backend connections appear in ordinary session management; signing out/revoking those sessions works as before. No alternative inference provider or model is added.

## Must verify on macOS / iPhone before enabling a release

- Xcode compilation with the actual installed SDK and native API signatures.
- Real signing/export, eligibility of the distribution profile, device registration and install prompt.
- Google, Discord and email sign-in through ASWebAuthenticationSession, return callback, cookie persistence, and logout/revocation.
- Chat streaming, stop, multitasking, reconnection, files/ZIP/PDF sharing, project previews, rotation, iPad popovers, physical keyboard sizing and VoiceOver.
- The app's privacy declarations against its final behavior and any future native SDKs. No tracking SDK is included.

Apple's signing verification is a point-in-time check. Certificate revocation can invalidate a previously valid build before its advertised expiry.
