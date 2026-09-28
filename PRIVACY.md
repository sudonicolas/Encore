# Privacy Policy

_Last updated: September 24, 2026_

Encore is a clipboard history app for macOS. It's free and open source, and it's built so
that what you copy stays on your Mac.

## The short version

Encore collects no data. The developer never receives anything you copy, anything about
how you use the app, or anything that identifies you. There's no account, no analytics, no
crash reporting, no advertising and no tracking.

## What stays on your Mac

- **Your clipboard history.** Text, images and file references you copy are saved only on
  your Mac, inside Encore's sandbox container. They're never uploaded anywhere.
- **Your settings**, including the apps you've told Encore to ignore.
- **Apple Intelligence features.** Smart titles and writing tools (proofread, summarize,
  explain and so on) use Apple's on-device model. Your clippings aren't sent to a server
  for these features.

Deleted clippings go to Recently Deleted and are erased for good after 30 days, or sooner
if you empty it. Deleting Encore deletes everything it stored.

## Online lookups

Encore can show a currency conversion, a dictionary definition or an encyclopedia summary
for a clipping. These come from free public services:

| Service | What's sent | When |
| --- | --- | --- |
| [Frankfurter](https://frankfurter.dev) (exchange rates) | A three-letter currency code, such as `USD`. Never the amount or anything else you copied. | When you open a clipping that contains a price |
| [Wiktionary](https://en.wiktionary.org) (Wikimedia Foundation) | The word you asked to define | Only when you click **Define** |
| [Wikipedia](https://en.wikipedia.org) (Wikimedia Foundation) | The name or topic you asked about | Only when you click **Wikipedia** |

Requests are made directly from your Mac to the service over HTTPS. They carry no cookies
and no identifiers, only a standard app name and version. They never pass through a
server run by the developer. Those services handle requests under their own privacy
policies: [Wikimedia](https://foundation.wikimedia.org/wiki/Policy:Privacy_policy) and
[Frankfurter](https://frankfurter.dev).

You can turn online lookups off entirely in **Settings → Intelligence**.

## Sensitive content

Encore skips anything that password managers and similar apps mark as concealed or
transient, and you can stop it recording from specific apps in **Settings → Privacy**. You
can pause recording at any time from the menu bar.

## Children

Encore collects no information from anyone, including children.

## Changes

If this policy ever changes, the new version will be published in this file, with its
full history in the [repository](https://github.com/sudonicolas/encore/commits/main/PRIVACY.md).

## Contact

Questions? Open an issue at
[github.com/sudonicolas/encore/issues](https://github.com/sudonicolas/encore/issues).
