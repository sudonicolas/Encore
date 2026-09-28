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

## 7. Replying to a Guideline 2.1 "Information Needed" rejection

New developer accounts often get this instead of a normal review. Apple isn't reporting a
bug — it wants the reply below in two places: click **Reply to App Review** on the message
in **App Store Connect → Distribution → App Review**, and also paste it into **App Review
Information → Notes** (Apple asks for both, so it's on file for later submissions too).

> 1. Screen recording: [record this yourself on a physical Mac — see below]
>
> 2. Encore is a native clipboard history manager for macOS that lives in the menu bar. It
>    keeps every text, image and file clipping you copy so you can find and reuse it later,
>    with on-device Apple Intelligence writing short titles for long clippings and offering
>    writing tools (proofread, rewrite, summarize, explain) on any clipping. It solves a
>    basic macOS limitation — the system clipboard holds only one item and discards it on
>    the next copy. The audience is Mac users who copy and paste often: writers, developers,
>    students and knowledge workers who want their clipboard history available without an
>    account or cloud sync.
>
> 3. No login or setup is required. After launch, click the stacked-cards icon in the menu
>    bar (there is no Dock icon) to open the clipboard history. Copy any text, image or file
>    and it appears at the top of the list; click a row to copy it back to the pasteboard.
>    macOS will ask whether Encore can paste from other apps — choose Allow (System Settings
>    → Privacy & Security → Paste from Other Apps); Encore needs this to work. Right-click
>    the menu bar icon for History, Settings and Quit. Apple Intelligence features (smart
>    titles, writing tools) appear only on an Apple Intelligence–capable Mac with it enabled;
>    everything else works without it.
>
> 4. External services: two free, keyless public APIs, called directly from the user's Mac —
>    Frankfurter (frankfurter.dev) for currency exchange rates, and the Wikimedia Wiktionary/
>    Wikipedia APIs for word definitions and topic summaries. On-device text features (smart
>    titles, proofread, rewrite, summarize) run entirely on Apple's on-device Foundation
>    Models framework (Apple Intelligence) — no third-party AI service is used. There is no
>    authentication service, analytics SDK, payment processor or backend server; Encore has
>    no server of its own.
>
> 5. Encore functions identically in every region. The only variation is Apple Intelligence
>    itself, which depends on Apple's own regional and language availability for that
>    feature; on a Mac or region without it, those specific buttons are hidden and the rest
>    of the app — clipboard history, search, pinning, Recently Deleted — is unchanged.
>    Currency, dictionary and encyclopedia lookups need network access and work worldwide.
>
> 6. Encore does not operate in a regulated industry and includes no protected third-party
>    material. It calls Wikipedia and Wiktionary only through their public, keyless APIs to
>    display standard reference content, the same content a browser would show on their
>    site; no special license or credential is required or held.
>
> Encore also has no account registration, login or account deletion flow, no user-generated
> content, and no in-app purchases or paid content — it is entirely free with no
> monetization, so those parts of the guideline don't apply.

### The screen recording (item 1)

Apple wants this captured on a physical Mac, so record it yourself — QuickTime Player →
**File → New Screen Recording**, or ⇧⌘5. Cover, in one continuous take:

1. Launch Encore (from Applications or Launchpad) and show it appear only in the menu bar.
2. Copy some text in another app (Notes, Safari) and switch back to show it land at the top
   of the popover; click it to copy it back.
3. Open a long clipping and show its Apple Intelligence smart title, then use a writing tool
   (Proofread or Summarize) on it.
4. Open the History window (right-click the menu bar icon → History): search, pin a row,
   delete one, then show Undo and Recently Deleted.
5. Open Settings → Privacy and Intelligence tabs briefly, then Quit from the menu.

Export it and attach it to the same **Reply to App Review** message as the text above.

### Do you need to attach a new build?

Yes, in this case — not because Apple asked for one, but because the rejected submission
was **1.1.0 (3)** and the code has since moved to **1.2.0 (4)**. Sending Apple the reply
above without a new build would put 1.1.0 (3) back into review, which isn't the version you
want live. Steps:

1. Build and upload the current code, same as [step 5](#5-build-and-upload) above:
   ```sh
   APPSTORE_PROFILE=~/Developer/Profiles/Encore_App_Store.provisionprofile ./build.sh --app-store
   ```
   then upload `build/Encore.pkg` with Transporter and wait for it to finish processing
   (**App Store Connect → TestFlight** tab) — usually 5 to 30 minutes.
2. In App Store Connect, go to your app → **+ Version or Platform → macOS** and enter
   **1.2.0** (the rejected 1.1.0 entry stays as-is; you're not editing it). Fill in "What's
   New in This Version."
3. In that new version's **Build** section, choose build **1.2.0 (4)** once Transporter's
   upload finishes processing.
4. Paste the section 7 reply above into this version's **App Review Information → Notes**.
5. Still reply directly to the original message thread under the rejected 1.1.0 submission
   with the same text and the screen recording attached — that's the thread Apple's message
   points at, and it stays linked to your account regardless of which version it reviews next.
6. Click **Save**, then **Add for Review** / **Submit to App Review** on the 1.2.0 version.

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
