# iOS External Setup & Testing Guide — Our Canvas

Everything that must happen OUTSIDE this repository to take the iOS app from
CI-green to production. **No secret values belong in this document.**

---

## 1. Firebase Console (project `prempatra-c91fd`)

1. **Register/verify the iOS app** with bundle id `com.aapka.prempatra` (the committed
   `GoogleService-Info.plist` carries `GOOGLE_APP_ID 1:102366474445:ios:556acfbac06a22b95cf984`).
2. **Authentication → Sign-in method:** enable **Apple** and **Google** (and keep
   Email/Password). For Google, add the iOS client id / reversed URL scheme already
   present in the plist.
3. **APNs:** upload the Apple push **auth key (.p8)** (team id + key id) under
   Project Settings → Cloud Messaging → APNs Authentication Key. Without this, FCM
   cannot deliver to iOS tokens at all.
4. (Optional hardening) App Check.

## 2. Apple Developer portal

1. Bundle id `com.aapka.prempatra` + capability set: **Push Notifications**,
   **Sign in with Apple**. App Group `group.com.aapka.prempatra` for the app AND the
   widget extension (`com.aapka.prempatra.widget`).
2. Generate the APNs .p8 key (→ upload to Firebase, §1.3).
3. Associated domains — only if universal https invite links are wanted later (the
   client already parses Android-style https params).

## 3. App Store Connect

1. Create the non-consumable IAP **`prempatra_lifetime_pro`** (Lifetime Pro, ₹99;
   display-only ₹299→₹99 offer lives in the app UI).
2. Fill the app record: privacy nutrition label (emails, doodle content, purchase
   history), screenshots, sign-in demo account.
3. TestFlight distribution for all device testing below.

## 4. Worker configuration (repository-external values)

Fill these Info.plist build settings per environment (never commit values):
- `GuessWorkerBaseURL` — the deployed Cloudflare Worker endpoint Android already uses.
- `GuessWorkerApiKey` — the same `X-Api-Key` secret Android uses.

Until both are set, Guess judging shows a friendly "not configured" error and the
game stays in start/spectate states. The worker itself needs **no changes**.

### Shared-worker note (do not regress)

The push-relay worker is **shared backend** between iOS and Android, and its source
lives only in the Android-side tooling — the iOS repo deliberately carries **no copy**
of `push-relay/src/index.js`. Keep it that way: never deploy the worker from anything
in this repo, or a stale copy could regress production fixes.

Already live in production (deployed 2026-09-09, worker version `cf320597`):
`handleJudge`'s membership check now falls back to the **live** `groups/{groupId}.memberIds`
when the guesser is missing from the game document's creation-time `memberIds` snapshot.
This fixes permanent 403 "not a member" dead-ends for members who joined a circle
**mid-round**. The fix applies to iOS automatically — nothing to redeploy here.

iOS-side verification for that fix (needs two+ real devices/accounts):
1. Accounts A and B in a circle; A starts a Guess My Doodle round.
2. Account C joins the circle **after** the round started.
3. As C: open the Guess tab, replay the doodle, submit guesses — wrong → "Not quite —
   try again!", correct → win flow. No "couldn't reach the judge" dead-end.
4. C's Reveal Word / give-up path works; when everyone revealed, round ends GAVE_UP.
5. Regression: A still judges normally; the drawer cannot guess their own doodle;
   a genuine non-member is still rejected.

iOS client behavior after this change: a worker `409` (round no longer in guessing
phase) surfaces as "This round already ended" instead of a connection error; all other
non-2xx responses keep the generic connection error (Android parity).

### Idempotent judge replays (worker `cf4717ce`, 2026-09-09, already live)

On very slow networks a judge request can commit server-side while the HTTP response
carrying the outcome is lost. The worker now REPLAYS the recorded outcome with 200
instead of erroring when the game is already FINISHED or the caller is already in
`gaveUpUsers` (no writes on replay):

| Replay case | Response |
|---|---|
| FINISHED + CORRECT, caller is winner | `{correct:true, word}` |
| FINISHED + CORRECT, caller not winner | `{correct:false, lostRace:true, winnerName, word}` |
| FINISHED + GAVE_UP | `{correct:false, gaveUp:true, roundOver:true, word}` |
| Caller already in gaveUpUsers (round still GUESSING) | `{correct:false, gaveUp:true, roundOver:false, word}` |

iOS handling (unit-tested in `JudgeReplayTests`): win replay → win confirmation;
lostRace replay → "So close — <winnerName> got it first!"; gaveUp replays → the word
is persisted to the local reveal store (Android `guess_reveals` pattern), and the
reveal card reads ONLY that local store while the round is live — never
`game.revealedWord` before FINISH — so a retried reveal can never show a blank word.

Device verification (slow-network simulation, e.g. Network Link Conditioner):
1. As a guesser, trigger giveUp twice (retry after a lost response) — second call
   returns `{gaveUp:true, word}` and the reveal card shows the word.
2. After someone wins: retry checkGuess as the winner (`correct:true` + word) and as
   another member (`lostRace:true` + winnerName + word). No 409s.
3. Regression: drawer guessing own live round → 403; non-member → 403; mid-round
   joiner can guess and reveal normally.

## 5. Cloud Functions — deploy the member-joined trigger (required for the new join notifications)

`functions/index.js` now includes `onGroupMemberAdded` (groups doc updated → detects new
memberIds → pushes `member_joined` to every other member with `{user} has joined your
circle {circle name}` copy handled client-side). Clients cannot fan this out themselves
(rules correctly deny cross-user notification writes), so:

    firebase deploy --only functions:onGroupMemberAdded

Until deployed, joining a circle simply produces no notification. The trigger follows
the exact patterns of the existing drawing/reaction triggers (region us-central1,
`sendDataMessage`, stale-token cleanup, Promise.allSettled fan-out).

## 6. Firestore rules — the ONE required backend change (production blocker)

Today premium-field writes are only permitted with `premiumSource` ∈
{CODE, PLAY, WELCOME_PROMO, test-reset}. The iOS client therefore:
- verifies purchases with StoreKit 2 locally,
- attempts an honest `APP_STORE` grant (claim doc `play_purchases/{transactionId}`
  + the shared premium fields, token = StoreKit transaction id),
- shows **"pending server activation"** when rules deny it (never fake Pro).

**Recommended change (server-side verification):**
1. Deploy a Cloud Function / worker endpoint `verifyAppStorePurchase` that:
   receives (uid, transaction id), verifies the receipt against the App Store Server API,
   writes the `play_purchases` claim doc (uid, source APP_STORE) and grants
   `users/{uid}` with `premiumSource: "APP_STORE"` + `playPurchaseToken` fields —
   mirroring `grantLifetimePro` in the existing Android `functions/index.js`.
2. Rules: extend the users-update whitelist with an `isAppStoreUpdate()` predicate
   identical to `isPlayPurchaseUpdate()` but for source APP_STORE, and keep
   `play_purchases` client-blocked (verification happens server-side).
3. iOS then swaps its direct grant attempt for the function call (one-method change
   in `StoreManager.attemptServerGrant`).

## 7. Physical device test procedures

Run on iPhone + the Android production build in the SAME Firebase project.

### 7.1 Push end-to-end
1. Fresh install iOS, sign in, allow notifications. Confirm `users/{uid}.fcmToken` populated in the console.
2. Android sends a drawing to the shared circle → expect iOS banner (foreground),
   lock-screen notification (background), and after tapping: the circle's feed opens.
3. Repeat with the app KILLED (cold launch) — route must still land on the feed.
4. Guess round events → `new_game_turn` + `guess_result` copy check
   (drawer 🏆 / guesser ⚡ / all-gave-up ✏️).

### 7.2 Widget
1. Add the widget → pick a circle in the app → confirm the latest doodle + sender
   name render on the home screen.
2. Tap → feed deep link. iOS 17: tap the refresh button after a new drawing arrives.
3. Kill the app, send a drawing from Android → widget updates within the push-reload/timeline window.

### 7.3 Offline queue
1. Airplane mode → draw → Send → expect "Saved for later ✈️" + offline banner.
2. Re-enable network → banner flips to "Sending…" → doodle appears in the feed exactly once.
3. Repeat with app killed while queued, then relaunch.

### 7.4 Mixed Android ↔ iOS matrix (16 scenarios)
| # | Scenario | Expected |
|---|---|---|
| A | Android & iOS accounts share a circle | Both member lists agree |
| B | Android drawing → iOS feed | Image + replay render, sender name correct |
| C | iOS drawing → Android feed | Same (PNG base64, Android envelope) |
| D | Android reaction → iOS badge + hub entry | `reaction:{drawing}:{sender}` id, emoji copy |
| E | iOS reaction → Android push | Cloud Function fires (emoji/senderName fields present) |
| F | Android starts Guess round → iOS guesses | Race UI works; worker judges; loser sees ⚡ copy |
| G | iOS starts round → Android guesses | Same, reversed |
| H | Legacy Android 1v1 game (`guesserId` set) | iOS renders legacy guesser/spectator flow |
| I | iOS as legacy spectator | Spectator card, no guess UI |
| J | Co-Draw Android ↔ iOS | Strokes stream both ways; scaling sane; undo/clear broadcast |
| K | Notifications Android → iOS | Delivered + persisted + deep link |
| L | Notifications iOS → Android | Worker/CF fan-out reaches Android |
| M | What's New seen-version | Open on iOS clears the dot on Android for the same account (v3 field) |
| N | Hide my Gmail | Toggle on either side hides emails in BOTH member sheets within TTL |
| O | Premium cross-platform | Pro granted on Android reflects on iOS (server plan) and vice versa |
| P | Offline/reconnect with both platforms drawing | Queues flush once, no dupes |

### 7.5 Account lifecycle & privacy
Fresh install → signup (email/Google/Apple) → verification → profile setup →
onboarding → create-circle; logout → login as second account: What's New dot,
walkthrough, reveals, visit timestamps, notification prefs must be account-scoped;
widget shows the placeholder until re-picked. Account deletion (two-step) removes
the user's data per the documented scope.

### 7.6 Accessibility / adaptivity sweep
iPhone SE ↔ Pro Max, Dynamic Type default → XXL across: auth, canvas toolbar,
letter bank, feed, notifications, What's New, profile, settings, onboarding,
widget config. No clipping, no lost buttons, wrapped grids stay wrapped.

## 8. Signing / CI notes
- Set `DEVELOPMENT_TEAM` in `project.yml` (or xcconfig) for device builds; CI stays
  unsigned. Add an App Store distribution workflow when the icon/launch-screen
  blocker is cleared.
