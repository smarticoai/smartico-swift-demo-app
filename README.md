# Smartico Swift demo

<!-- video: drop the demo recording's user-attachments URL here -->

**A showcase of building a fully custom, native gamification UI on top of the
Smartico API.**

This is not a drop-in widget and not a wrapped web page. Every screen you see —
missions, tournaments, raffles, jackpots, levels, leaderboard, store, inbox — is
a plain SwiftUI screen, styled by us, fed by Smartico API calls. Smartico is the
backend; the look, the navigation and the interaction model are entirely the
app's own. Swap the theme and it becomes your brand.

It is a Smartico demo app (parity with the web https://play.smartico.ai) built on
**[`SmarticoPublicAPI`](https://github.com/smarticoai/smartico-swift-sdk)** —
Smartico's Swift SDK that talks the WebSocket protocol directly, with no browser
and no `smartico.js` page script. It supplies the typed API surface (missions,
tournaments, store, jackpots, raffles, leaderboard, inbox, …) as `async throws`
functions; the protocol documentation lives in
[`public-api`](https://github.com/smarticoai/public-api).

Swift 5 language mode · SwiftUI · iOS 16 · Xcode 16+. The SDK is a Swift
package with zero dependencies — Foundation only, no UIKit, no WebKit. The app
adds exactly one: `GoogleSignIn-iOS`.

## Try it on the simulator

[**Download `SmarticoDemo-simulator.zip` →**](https://github.com/smarticoai/smartico-swift-demo-app/releases/latest)

Needs a Mac with Xcode (for the simulator), nothing else. Unzip it, boot a
simulator, install, launch — the whole demo runs against the live ICE demo
label. Sign in with Google.

```bash
unzip SmarticoDemo-simulator.zip
open -a Simulator
xcrun simctl install booted SmarticoDemo.app
xcrun simctl launch booted ai.smartico.rnexpo
```

The zip is a Release build for both simulator architectures (Apple silicon and
Intel). No release yet, or want a fresh one? `Tools/make-sim-build.sh` builds
the same zip into `build/`.

There is no downloadable build for a real iPhone, and there cannot be: iOS has
no sideloading. An app runs on a device only if it is signed by a team the
device is registered with, or comes through TestFlight / the App Store. To run
it on your phone: clone, open `SmarticoDemo.xcodeproj`, select your team in
**Signing & Capabilities**, run.

## What is demonstrated

**Session & identity**
- Google sign-in through `GoogleSignIn-iOS` (Google's own web sheet), verified
  by a demo backend (SL_SERVER) that owns the `user_ext_id` mapping, and session
  restore on cold start from a stored `cookie_token`. The `serverClientID` is
  the web client, so the id_token's `aud` is the one the backend checks.
- `Smartico.initialize(labelKey:options:)` / identify with a hashed
  `extUserId`, logout, and a profile enrichment round-trip through custom
  events.
- One event bridge over the socket (`identify`, `props_change`, `engagement`,
  `execute_deeplink`, `reload_achievements`, `show_spin`) feeding
  `@MainActor` `ObservableObject` singletons, so no view subscribes to the
  socket itself. The SDK delivers listener callbacks on the main queue.

**Native gamification screens — API in, your own UI out**
- Missions & badges — list, detail, opt-in, claim reward
  (`getMissions`, `getBadges`, `requestMissionOptIn`, `requestMissionClaimReward`).
- Tournaments — lobby, detail with leaderboard / prizes / info tabs,
  registration (`getTournamentsList`, `getTournamentInstanceInfo`,
  `registerInTournament`).
- Raffles — list, draws, draw detail, draw history, opt-in, prize claim
  (`getRaffles`, `getRaffleDrawRun`, `getRaffleDrawRunsHistory`,
  `requestRaffleOptin`, `claimRafflePrize`).
- Jackpots — pots, opt-in (`jackpotGet`, `jackpotOptIn`).
- Store — catalogue and purchase (`getStoreItems`, `buyStoreItem`).
- Levels / VIP progress (`getLevels`, `getCurrentLevel`) and live public props
  (points, gems, diamonds, username, unread count) pushed over the socket.
- Leaderboard (`getLeaderBoard`).
- Inbox — messages, read / unread, favourites, delete, HTML bodies in a
  `WKWebView` (`getInboxMessages`, `getInboxUnreadCount`, `getInboxMessageBody`,
  `markInboxMessageAsRead`, `markAllInboxMessagesAsRead`,
  `markUnmarkInboxMessageAsFavorite`, `deleteInboxMessage`), plus the
  engagement analytics behind them (`reportImpressionEvent` when a body is
  opened, `reportClickEvent` for a CTA or an in-body link).
- Profile — username editor, activity log (`changeUsername`, `getActivityLog`).
- Avatars, including AI avatar generation (`getAvatarsList`, `getAvatarPrompts`,
  `avatarsCustomize`, `getAvatarsCustomized`, `setAvatar`).
- Mini-games catalogue (`getMiniGames`) and per-game related items
  (`getRelatedItemsForGame`, the side panel in the slot).

**Engagement & routing**
- Engagement popups — the SDK owns the queue, the dedupe and the bridge
  handshake, the app owns the presentation: a transparent `WKWebView` with a
  `SmarticoBridge` message handler and the `SMTO-WRAPPER` user agent, always in
  the hierarchy and revealed only when the page reports it is ready (created on
  "show", it could never report that). The wrapper page reports its own
  impressions and clicks through the bridge, so no analytics code is needed
  here.
- Deep links (`dp:`) — the SDK parses and dispatches, the app binds them to its
  own screens, plus custom handlers (`dp:deposit`, `dp:opencashier`) and
  mapping of `play.smartico.ai/...` URLs onto native screens. Links also arrive
  from outside through the `smartico-demo://dp?dp=<url-encoded dp>` scheme —
  `xcrun simctl openurl` is the iOS stand-in for an Android intent — and one
  that arrives before login runs as soon as a player is logged in.
- Push notifications (APNs) — the device token, as lowercase hex, registered
  with Smartico after identify (cid 1003, `PushPlatform.NATIVE_IOS`), and full
  lifecycle analytics: delivered + impression when a push is shown in the
  foreground, delivered + impression + action on a tap. A tap that cold-starts
  the app parks its deep link until the user is identified. Payload keys are
  the Android demo's FCM data keys at the APNs top level (`engagement_uid`,
  `message_id`, `dp`). On the simulator the whole path runs from
  `xcrun simctl push`.

**Three rendering tiers — you choose per surface**
1. **Native** — everything listed above. API call in, your SwiftUI views out.
2. **In-app WebView** — mini-games (`gf_saw`, `gf_section`, `gf_quiz`,
   `gf_matchx`), engagement popups, and inbox HTML bodies.
3. **External browser** — widget sections this demo deliberately does not build
   natively (bonuses, clans) open the hosted wrapper page. Register a native
   handler for one later and it wins automatically.

The demo casino around it (lobby, game screen, fake wallet, slots, cashier) is
scaffolding, not integration surface.

> **Note on the identify hash.** This demo computes it client-side only because
> the demo label's hash salt is the literal string `"null"`. A production
> operator computes `md5(ext_user_id:SALT:ts)` on its **backend** with a secret
> salt and hands the result to the app. Do not ship `Sdk.demoHash()`.

## Build your own with Claude Code or Codex

The fastest path to your own app is not reading this repo line by line — it is
handing it to a coding agent as a worked example, together with the API
documentation, and describing the UI you want.

```bash
git clone https://github.com/smarticoai/smartico-swift-demo-app.git
git clone https://github.com/smarticoai/public-api.git
```

Then open your own project next to them and give the agent both references:

> Use `../smartico-swift-demo-app` as a reference implementation of a native
> Smartico integration — `Integration/Sdk.swift` is the integration surface
> (identify, the event bridge, public props, custom events),
> `Integration/DeepLinks.swift` wires deep links and `Integration/PopupHost.swift`
> hosts the engagement popups, `Integration/Push.swift` covers notifications,
> and the files in `Screens/` show the API calls behind each screen. Use
> `../public-api` for the API reference and the protocol docs. Build me a
> `missions` screen (or `tournaments`, `raffles`, …) in my app, in my design
> system, using the same integration pattern.

Why this works: the integration surface is small, commented and separated from
the demo's own visual styling on purpose, so an agent can lift the pattern
without dragging the casino UI along.

## Setup

Needs Xcode 16 or newer — the committed project is in the Xcode 16 file format;
Xcode 26 was used here. Swift 5 language mode, iOS 16 deployment target.

`SmarticoDemo.xcodeproj` is generated by [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml` and committed, so a clone opens in Xcode as is. Run
`xcodegen generate` only after editing `project.yml` (or adding / removing
source files), and commit both.

The SDK comes from GitHub
([`smarticoai/smartico-swift-sdk`](https://github.com/smarticoai/smartico-swift-sdk),
`from: 0.1.0` in `project.yml`), pinned to an exact tag by the committed
`Package.resolved` — SDK releases are git tags, so that pin is what ties the
demo to a given SDK. Bump it to move to a newer one (Xcode: **File → Packages →
Update to Latest Package Versions**, then commit `Package.resolved`).
GoogleSignIn-iOS is resolved the same way. Xcode fetches both on first open; a
clone needs nothing next to it.

**Push notifications** need nothing on the simulator. A simulator build is
signed ad hoc and still gets an APNs token; delivery to it is driven by
`xcrun simctl push` (see Run). Real delivery needs an Apple Developer team and
an APNs key — see Known manual steps.

## Run

In Xcode: pick an iPhone simulator, ⌘R. From the shell:

```bash
xcodebuild -project SmarticoDemo.xcodeproj -scheme SmarticoDemo -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build build
open -a Simulator
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/SmarticoDemo.app
xcrun simctl launch --console booted ai.smartico.rnexpo
```

`--console` streams the app's log: `[SmarticoDemo]` lines from the demo,
`[Smartico]` lines from the SDK.

Debug builds take launch arguments (compiled out of Release), passed after the
bundle id — or in Xcode under Scheme → Run → Arguments:

| Argument | Effect |
|---|---|
| `-dp <link>` | run a deep link once the user has signed in and is identified, e.g. `-dp dp:gf_tournaments` |
| `-pushTap <uid>` | simulate a tap on a campaign push (a banner tap cannot be driven from the shell); its link comes from `-pushTapDp <link>`, default `dp:gf_missions` |
| `-traceFrames` | log every non-ping socket frame the SDK sends and receives |
| `-inboxHtmlSample` | put a local message with an HTML body on top of the inbox (the demo label's messages have none); it sends no analytics |

```bash
xcrun simctl launch --console booted ai.smartico.rnexpo -dp dp:gf_raffle
```

A deep link can be handed to the running app from the shell, which is the
quickest way to reach a screen without clicking through. iOS may first ask
"Open in “Fakebet”?":

```bash
xcrun simctl openurl booted "smartico-demo://dp?dp=dp%3Agf_missions"
```

A push is delivered to the simulator from a payload file. In the foreground it
shows a banner and reports delivered + impression; tapping it reports the
action and opens the payload's `dp` (missions):

```bash
xcrun simctl push booted ai.smartico.rnexpo Tools/push-sample.apns
```

## Working on the SDK

Normally the SDK comes from GitHub, which is exactly what a client gets. To
develop against a local checkout instead, replace the two lines in
`project.yml`

```yaml
  SmarticoPublicAPI:
    url: https://github.com/smarticoai/smartico-swift-sdk
    from: 0.1.0
```

with

```yaml
  SmarticoPublicAPI:
    path: ../smartico-swift-sdk
```

and run `xcodegen generate`. Edits in the SDK are then picked up on the next
build with no publishing step in between. Put the `url` lines back to return to
the published package.

## Layout

```
project.yml                   XcodeGen spec (target, bundle id, packages, URL schemes, entitlements)
SmarticoDemo.xcodeproj/       generated from project.yml, committed
Tools/make-sim-build.sh       Release simulator build → build/SmarticoDemo-simulator.zip
Tools/push-sample.apns        payload for xcrun simctl push
SmarticoDemo/
  Integration/
    Sdk.swift               ← the integration surface (what an operator replicates)
    DeepLinks.swift           deep-link bindings, custom handlers, smartico-demo:// entry point
    Push.swift                APNs token registration, lifecycle analytics, tap routing
    PopupHost.swift           popup host (transparent WKWebView over PopupBridgeSession)
    WidgetScreen.swift        in-app WKWebView for mini-game deep links
    Auth.swift                SL_SERVER social login, session restore
    Providers.swift           GoogleSignIn-iOS plumbing
    Store.swift               one fetch, shared lists (missions, badges, tournaments)
    Economy.swift             demo wallet: backend-authored money events, balance poll
  Screens/
    MissionsScreen | LevelsScreen | VipScreen | ProfileScreen | AvatarPickerScreen | NameDialog
    TournamentsScreen | TournamentDetailScreen | LeaderboardScreen | JackpotsScreen
    RafflesScreen | RaffleDrawsScreen | DrawDetailScreen | InboxScreen | StoreScreen | MiniGamesScreen
                            ← the API calls behind each screen
    LobbyScreen | GameScreen | CashierScreen | LoginScreen
                            ← demo-casino UI (not integration-relevant)
  Nav/Routes.swift            every destination, one NavigationStack path per tab
  Nav/AppNav.swift            tabs, header, bottom bar, promos spread, burger menu
  App/SmarticoDemoApp.swift   @main, AppDelegate (push), root switch, DEBUG launch arguments
  App/Theme.swift             palette and shared view helpers
  Casino/Catalog.swift        game catalogue
  Casino/AvifImage.swift      AVIF stills and animated slot sprites through ImageIO
  Resources/                  Info.plist and entitlements (written by XcodeGen), assets
```

Label/brand config: `Integration/Sdk.swift` (ICE env4 demo label; its hash salt
is literally `"null"`, so the identify hash is computed client-side —
production operators compute it on their backend).

## Known manual steps

- An Apple Developer Program team is needed for real push delivery (an APNs
  key, and a provisioning profile that carries the `aps-environment`
  entitlement), for TestFlight, and for device installs that last beyond
  7 days. Until then the push path is verified on the simulator with
  `xcrun simctl push` only.
- A free Apple ID (Personal Team) can install on a device for 7 days. It
  cannot sign the Push Notifications capability, so `project.yml` applies the
  `aps-environment` entitlement to simulator builds only: a device build from a
  free team runs as is, and push-token registration fails gracefully (logged,
  nothing else). With a paid team, add the entitlement for `[sdk=iphoneos*]`
  in `project.yml` and run `xcodegen generate`.
- The bundle id is `ai.smartico.rnexpo`, deliberately the same as the React
  Native demo, so Google sign-in reuses the iOS OAuth client already registered
  for it. As a consequence the two demos cannot live side by side on one device
  or simulator: installing one replaces the other. If Xcode reports the bundle
  id as unavailable for your team, change it — but Google sign-in is tied to
  it, so a new id needs its own iOS OAuth client.
- Google sign-in on the simulator opens Google's web sheet and needs a real
  Google account.
- For some long-lived demo users (the ICE test user `test48054049`, for one)
  the header balance never moves after a spin or a deposit: the demo backend
  reads the wrong wallet row for them (their first currency row is not EUR). Smartico does receive the events — mission
  progress moves. Users who sign in with Google are not affected.
- The slot animations are AVIF image sequences decoded by ImageIO, frame by
  frame off the main thread, skipping late frames so a clip keeps its length.
  The simulator decodes in software and manages about 11 fps; a device is
  expected to play the clips' full 24 fps.

## The SDK

```swift
dependencies: [
    .package(url: "https://github.com/smarticoai/smartico-swift-sdk", from: "0.1.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "SmarticoPublicAPI", package: "smartico-swift-sdk"),
    ]),
],
```

In Xcode: **File → Add Package Dependencies…**, paste the URL, add the
`SmarticoPublicAPI` library to the app target.

https://github.com/smarticoai/smartico-swift-sdk
