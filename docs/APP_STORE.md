# Publishing Encore on the Mac App Store

Encore is already set up for the store: it's sandboxed (`Encore.entitlements`), has a privacy
manifest (`Resources/PrivacyInfo.xcprivacy`), declares that it uses no non-exempt encryption
(`ITSAppUsesNonExemptEncryption` in `Info.plist`), and builds as a universal binary. What's
left is the account-side setup, which only the account holder can do.

You need a paid Apple Developer Program membership. Encore is free, so there are no
agreements or banking forms to fill in beyond the standard Free Apps agreement.

## 1. Register the app ID (once)

[Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)
→ **Identifiers** → **+** → **App IDs** → **App**.

- Platform: **macOS**
- Bundle ID: **Explicit**, `io.github.sudonicolas.encore` (must match `Info.plist`)
- Capabilities: none needed

## 2. Create the two distribution certificates (once)

In Xcode: **Settings → Accounts** → your team → **Manage Certificates…** → **+**, and add:

- **Apple Distribution** (signs the app)
- **Mac Installer Distribution** (signs the `.pkg`)

Both land in your login keychain, where `build.sh` finds them automatically. Check with:

```sh
security find-identity -v -p codesigning   # Apple Distribution: …
security find-identity -v -p basic | grep Installer
```

## 3. Create the provisioning profile (once a year)

[Profiles](https://developer.apple.com/account/resources/profiles/list) → **+** →
under *Distribution*, **Mac App Store Connect** → choose the `io.github.sudonicolas.encore`
app ID → choose your Apple Distribution certificate → name it (for example
"Encore App Store") → **Download**.

Keep the `.provisionprofile` file somewhere outside the repo (it isn't secret, but it's
tied to your account). For example: `~/Developer/Profiles/Encore_App_Store.provisionprofile`.

## 4. Create the app in App Store Connect (once)

[App Store Connect](https://appstoreconnect.apple.com/apps) → **+** → **New App**.

- Platform: **macOS**
- Name: **Encore**. Store names must be unique, so if it's taken, try something like
  *Encore Clipboard* or *Encore – Clipboard History*. This only changes the listing; the
  app can still be called Encore on the Mac.
- Primary language: English (U.S.)
- Bundle ID: `io.github.sudonicolas.encore`
- SKU: anything unique to you, such as `encore-macos`

Then fill in:

| Section | What to enter |
| --- | --- |
| **Pricing and Availability** | Price: **Free (USD 0)**, all countries |
| **App Privacy → Privacy Policy URL** | `https://github.com/sudonicolas/encore/blob/main/PRIVACY.md` |
| **App Privacy → Data Collection** | **No, we do not collect data from this app.** This results in the *Data Not Collected* label. Online lookups qualify because they go straight from the user's Mac to Wikimedia or Frankfurter, only to answer the request at hand, and never to the developer. |
| **App Information → Category** | Primary: **Productivity**. Secondary (optional): **Utilities** |
| **App Information → Age Rating** | Answer *None* to everything. Encore has no unrestricted web access (lookups show fixed summaries, not a browser). |
| **App Information → Content Rights** | Doesn't contain third-party content |
| **Version → Support URL** | `https://github.com/sudonicolas/encore/issues` |
| **Version → Marketing URL** (optional) | `https://github.com/sudonicolas/encore` |
| **Version → Copyright** | `2026 sudonicolas` |

The listing itself (promotional text, description, keywords, review notes, sandbox
entitlement reasons and screenshots) is ready to paste from `app-store/listing.md`, a
local working file that's kept out of git.

### Screenshots

The seven screenshots in [`app-store/screenshots/`](app-store/screenshots) are 2880×1800
and are generated from the app itself:

```sh
tools/screenshots/make-screenshots.sh                    # all scenes
tools/screenshots/make-screenshots.sh --only hero,search  # some of them
tools/screenshots/make-screenshots.sh --portrait          # 5 portrait slides, 2160x2700 (4:5)
```

The portrait set in [`app-store/portrait/`](app-store/portrait) is for carousels seen on a
phone, with Encore at 175% Text Size. The words and the UI float with open space on every
side, so a slide can take a float or zoom effect. Its scenes live in
`tools/screenshots/Portrait.swift`.

The script builds a small tool from Encore's own sources plus `tools/screenshots/`, and
renders Encore's real popover, History and Settings windows over a branded stage on a
temporary virtual Retina display. So the output is a true 2x capture even on a 1x
monitor, nothing appears on screen, and no Screen Recording permission is needed. It
never touches your clipboard or history: it runs on a fictional history in a throwaway
home folder, with the clock pinned to 9:41. The titles and the rewrite are generated live
by Apple Intelligence and the exchange rates are fetched live, so it needs an Apple
Intelligence Mac and a network connection. Scenes, layout and copy live in
`tools/screenshots/Scenes.swift`; the demo history in `DemoData.swift`.

## 5. Build and upload

Each upload needs a higher build number. Bump `CFBundleVersion` in `Info.plist` (and
`CFBundleShortVersionString` for a new public version), then:

```sh
APPSTORE_PROFILE=~/Developer/Profiles/Encore_App_Store.provisionprofile ./build.sh --app-store
```

This produces `build/Encore.pkg`: a universal app, signed for distribution, with the
profile embedded, wrapped in a signed installer package.

Upload it with **[Transporter](https://apps.apple.com/app/transporter/id1450874784)** (free,
from Apple): sign in, drag in `build/Encore.pkg`, click **Deliver**. Transporter checks the
package before uploading, so problems show up there first. After processing (usually 5 to
30 minutes) the build appears under your app's **TestFlight** tab and can be chosen in the
version's **Build** section.

## 6. Notes for App Review

Paste this into **App Review Information → Notes**. Menu bar apps are often rejected
when reviewers can't find them:

> Encore is a menu bar app with no Dock icon. After launch, click the stacked-cards icon
> in the menu bar to open the clipboard history. Copy some text in any app and it appears
> in the list; click a row to copy it back.
>
> macOS may ask whether Encore can paste from other apps; choose Allow (System Settings →
> Privacy & Security → Paste from Other Apps). Encore needs this permission to work.
>
> Right-click the menu bar icon for a menu with History, Settings and Quit.
>
> Apple Intelligence features (smart titles, writing tools) need an Apple Intelligence–
> capable Mac with it enabled; everything else works without it. Online lookups
> (currency, Wiktionary, Wikipedia) use free public APIs with no account and can be
> turned off in Settings → Intelligence.
>
> No sign-in is required.

No demo account is needed.

## Guideline checklist

These are the review guidelines Mac apps most often fail, and how Encore meets each one:

- **2.4.5(i) App Sandbox:** sandboxed, with only network-client and user-selected
  read-only file access.
- **2.4.5(iii) Launch at login:** off by default. It's only turned on by the user in
  Settings, through `SMAppService`.
- **2.4.5(iv) Updates:** no self-updater; updates come through the store.
- **2.4.5(vii) Other apps:** Encore never launches, controls or terminates other apps.
  (The one-time migration from the old *clipboard* app is a no-op inside the sandbox.)
- **5.1.1 Privacy:** privacy policy linked, no data collected, privacy manifest included.
- **5.1.2 Data use:** clipboard contents never leave the Mac except the explicit lookups
  above.

## Open source and the store

Encore is MIT licensed (`LICENSE`). MIT is compatible with App Store distribution: the
license only asks that the copyright notice travel with copies of the code, and the store
terms don't conflict with it. Others may build and ship their own copies too, but only
you can publish under your bundle ID and developer account.
