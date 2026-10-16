# Install Ozyy on your own iPhone for free

This package is a real iPhone app built from Ozyy's native client source. It opens the existing Ozyy workspace inside a native UIKit app. The IPA is intentionally unsigned. It cannot install directly from Safari and is not a public distribution certificate.

1. Use Sideloadly for Windows, downloaded only from https://sideloadly.io/. Its current Windows instructions require Apple's desktop iTunes and iCloud. Install those official prerequisites if needed.
2. Connect your iPhone, unlock it and approve **Trust This Computer** on the phone if prompted. Ozyy requires iOS 17 or later.
3. Load **Ozyy-unsigned.ipa** in Sideloadly, select your phone and use your existing free Apple Account. Enter your Apple password and any verification code directly in Sideloadly, never in chat. Saving the password is optional; do not save it without choosing to.
4. Follow the device's developer-app trust and Developer Mode instructions if required. A restart may be needed. Do not install unknown certificates, configuration profiles or enterprise signing services.
5. Open **Ozyy AI** from your Home Screen and sign in to your usual Ozyy account. Chats, projects, model access and credits use the existing platform.

Free Apple signing expires after seven days. Sideloadly can refresh it automatically when the required PC/device connection is available; it cannot guarantee permanent installation without refreshing. Each person needs their own setup. There is no paid Apple membership, App Store submission or TestFlight step in this personal-install route.

## Build on GitHub

The manual GitHub Actions workflow uses a standard macOS runner with a fifteen-minute timeout and one-day artifact retention. For a private repository, first verify that the account has enough free Actions allowance and a **$0 Actions budget with stop usage enabled**. Do not dispatch a build when paid overages are possible. Never upload backend code, secrets, model keys, signing identities, provisioning profiles or account data to this client-only repository.

After the run passes, download its `Ozyy-iPhone-personal-install` artifact, extract it and verify `SHA256SUMS`. The package includes `build-info.json` stating that personal signing is still required. This does not enable the website's signed OTA installer.
