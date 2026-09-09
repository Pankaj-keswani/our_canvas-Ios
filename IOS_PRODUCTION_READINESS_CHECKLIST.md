# iOS Production Readiness Checklist — Our Canvas

**Generated:** 2026-09-09 · Phase 4 final hardening
**Status legend:** ✅ READY · 🧪 VERIFIED BY UNIT TEST (see §Q of the Phase 4 report) · 📱 NEEDS MANUAL DEVICE TEST · 🔧 NEEDS EXTERNAL CONSOLE ACTION · ⛔ BLOCKED (backend/rules) · 🤝 NEEDS MIXED ANDROID↔iOS TEST

---

## A. Repository / build
| Item | Status | Notes |
|---|---|---|
| XcodeGen project (app + widget + tests) | ✅ | CI green on macos-14/Xcode 16.1 |
| CI builds + 200+ unit tests | ✅ | 183 pre-Phase-4 + Phase 4 additions |
| App icon / asset catalog / launch screen | ⛔→🔧 | **No `Assets.xcassets`, no AppIcon, no launch screen file exists.** Must be added before any TestFlight/App Store submission. |
| Deployment target | ✅ | iOS 16.0 (widget interactive refresh gated to 17+) |
| Worker URL/API-key config | 🔧 | Info.plist keys `GuessWorkerBaseURL` / `GuessWorkerApiKey` are empty placeholders by design — fill per-environment, never commit values |
| DEVELOPMENT_TEAM / signing | 🔧 | Empty in project.yml; CI runs with `CODE_SIGNING_ALLOWED=NO`. Device builds need a real team/profile |

## B. Firebase configuration
| Item | Status | Notes |
|---|---|---|
| `GoogleService-Info.plist` (project `prempatra-c91fd`) | ✅ present | Real config committed (standard practice; contains no master secrets) |
| iOS app registered in Firebase console with matching bundle id (`com.aapka.prempatra`) | 🔧 | Verify the `GOOGLE_APP_ID` `1:102366474445:ios:556acfbac06a22b95cf984` exists in the console |
| Firestore usage (collections `users/groups/drawings/guess_games/co_draw_sessions/premium_codes/promo_redemptions/notifications subcoll.`) | ✅ code · 🤝 live | Field names mirror Android; needs one live mixed session |

## C. APNs
| Item | Status | Notes |
|---|---|---|
| `aps-environment` entitlement | ✅ | `development` — switch to distribution/ad-hoc via Xcode for release |
| APNs auth key uploaded to Firebase | 🔧 | **Unverified — required or pushes never reach iOS** |
| Foreground presentation + local composition for data-only pushes | ✅ code · 📱 | Real banner/sound delivery needs a device push test |
| Background delivery of data-only payloads | 📱 ⚠️ | Best-effort by iOS design; documented, not claimed guaranteed |

## D. Sign in with Apple
| Item | Status | Notes |
|---|---|---|
| Capability + entitlement | ✅ | Nonce flow implemented |
| Console: Apple sign-in provider in Firebase | 🔧 | Enable in Firebase → Authentication |
| Real device sign-in | 📱 | Works in simulator only superficially (no real ASAuthorization sheet coverage) |

## E. Google Sign-In
| Item | Status | Notes |
|---|---|---|
| GIDSignIn 7.x + URL scheme (`REVERSED_CLIENT_ID`) | ✅ code | Client ID read from `GoogleService-Info.plist` |
| Firebase console Google provider enabled | 🔧 | Must be enabled + iOS client configured |
| Real device flow | 📱 | Needs TestFlight/dev build |

## F. StoreKit / App Store
| Item | Status | Notes |
|---|---|---|
| StoreKit 2 purchase/restore/verify/price/loading | ✅ code · 📱 | Sandbox purchase test needed |
| **Server-side Pro grant for Apple purchases** | ⛔ | **Production Firestore rules have no APP_STORE path — the honest client shows `pendingServerActivation` instead of faking Pro.** Requires the rules/function work in §J/K of `IOS_EXTERNAL_SETUP_AND_TESTING.md` |
| 1:1 transaction→account binding | 🧪 | `PurchaseGrantPolicy` unit-tested (first-claim/idempotent/wrong-account/not-signed-in) |
| App Store Connect product `prempatra_lifetime_pro` | 🔧 | Non-consumable, ₹99 (offer display), must be created + approved |
| Promo codes (`premium_codes`) + welcome promo | ✅ code · 📱 | CODE path is rules-compatible; live redemption needs data + device |

## G. Widget
| Item | Status | Notes |
|---|---|---|
| App-group payload architecture (no Firestore in extension) | ✅ code | Firebase deps removed from widget target |
| Circle picker + payload writer in app | ✅ code | Home → widget tip → Choose circle |
| Deep link `ourcanvas://feed?groupId=` | 🧪 | Parser tested end-to-end |
| Timeline (hourly entries + `.after(1h)`) | ✅ code · 📱 | Widget rendering needs a real home-screen run |
| iOS 17 interactive refresh | ✅ code (gated) · 📱 | iOS 16 fallback = timeline + app reloads (documented) |

## H. Push notifications (all four types)
| Item | Status | Notes |
|---|---|---|
| Payload parsing/validation/defaults | 🧪 | `new_drawing/new_reaction/new_game_turn/guess_result` incl. role fields |
| Receiver-side persistence + stable IDs + dedupe | 🧪 | Own docs only |
| Hub (20 cap, unread, mark-all, clear-all+confirm, swipe, 30-day cleanup ≤100/pass) | 🧪 | |
| Deep links incl. cold launch | 🧪 | Pending-route persistence tested |
| FCM token lifecycle (fresh install/login/re-login/refresh) | 🧪 | Phase 0 PushTokenStore suite |
| Permission timing (first Main entry, idempotent) | ✅ code · 📱 | |
| **Real push reaches an iOS device** | 📱+🔧 | Requires APNs key upload first — NOT claimed done |

## I. Deep links
| Item | Status | Notes |
|---|---|---|
| `ourcanvas://` scheme registered | ✅ | |
| Push/widget/notification routes | 🧪 | |
| Signed-out arrival (parked, applied after login) | ✅ code | Cold-launch persistence |
| Universal links / invite `https` links | 🔧 | Associated domains not configured; Android-style https params are parsed if a domain is ever registered |
| Malformed/unknown URLs | 🧪 | Fail gracefully to nil |

## J. Firestore rules
| Item | Status | Notes |
|---|---|---|
| iOS writes respect production rules (users create/update, CODE/WELCOME_PROMO premium, notifications own-docs, co-draw transactions) | ✅ code · 🤝 | **No rules were weakened from the client.** |
| APP_STORE premium path | ⛔ | See F — requires a deliberate rules/function change (server-side verification recommended) |

## K. Cloudflare Worker
| Item | Status | Notes |
|---|---|---|
| Judge client contract (`checkGuess`/`giveUp`, `X-Api-Key`, response fields) | 🧪 | Worker untouched, as required |
| Shared worker live-membership fix (mid-round joiners) | ✅ live · 📱 | Worker `cf320597` (2026-09-09) authorizes against live `groups/{id}.memberIds` — applies to iOS automatically; iOS repo carries no worker copy and must never deploy one. Device-verify per `IOS_EXTERNAL_SETUP_AND_TESTING.md` §4 |
| 409 wrong-phase error copy | 🧪 | Client maps worker 409 → "This round already ended" (other non-2xx stay generic, Android parity) |
| Idempotent judge replays (lost HTTP responses) | ✅ live · 🧪 | Worker `cf4717ce` (2026-09-09) replays FINISHED / already-gave-up outcomes with 200 (no writes). iOS maps all four replay shapes and persists replayed reveal words to the local store; reveal card never reads `game.revealedWord` before FINISH (tested in `JudgeReplayTests`) |
| Config values | 🔧 | Info.plist placeholders must be filled (same key Android uses) |

## L. Offline reliability
| Item | Status | Notes |
|---|---|---|
| File-backed pending queue, uid-scoped | 🧪 | Survives restart, backoff 30s→1h |
| NWPathMonitor reconnect + foreground flush + banner | ✅ code · 📱 | Reconnect path needs device airplane-mode test |
| No duplicate sends / removal only after confirmed write | 🧪 | |
| Account switch never flushes another user's drawings | 🧪 | |

## M. Privacy
| Item | Status | Notes |
|---|---|---|
| Hide my Gmail reciprocity + 10-min TTL + field-level updates | 🧪 | |
| Cross-account cleanup (widget payload/selection cleared on sign-out; user-scoped stores keyed per uid) | 🧪 | |
| Account deletion (two-step, rules-scoped) | ✅ code · 📱 | Documented skips: embedded reactions on others' drawings; shared game/co-draw docs |

## N. Accessibility / Dynamic Type
| Item | Status | Notes |
|---|---|---|
| Accessibility labels on icon-only controls | ✅ code | FABs, eraser, tiles, replay, avatars |
| Dynamic Type | 📱 | Forms/Lists/system styles scale automatically; brand display fonts are fixed-size by design with `minimumScaleFactor` on primary CTAs — full XXL sweep needs a device/simulator pass |
| Wrapped (non-scrolling) letter bank & grids | ✅ code | Adaptive LazyVGrid |

## O. Device testing (single-platform)
Required matrix before release: **iPhone SE 3rd / iPhone 15–16 / iPhone 16 Pro Max, portrait (+landscape where supported), Dynamic Type default→XXL, keyboard fields (auth/profile/settings), background & killed app, cold launch from push, widget on home screen, account switch.** — 📱 none of this can be truthfully claimed from CI.

## P. Mixed Android↔iOS testing
All sixteen scenarios (auth sharing, same circle, drawings/reactions both directions, Guess both directions, legacy 1v1, Co-Draw, notifications both directions, What's New version sync, Hide-Gmail reciprocity, premium state) — procedures in `IOS_EXTERNAL_SETUP_AND_TESTING.md` §Mixed Testing. 🤝 **Not executed — physical devices required.**

## Q. App Store release requirements
| Item | Status |
|---|---|
| App icon / launch screen | ⛔ missing (see A) |
| Privacy nutrition label + data-use declarations | 🔧 manual |
| Sign in with Apple present alongside Google/email | ✅ code |
| Account deletion inside the app (Apple requirement) | ✅ code · 📱 |
| Restore purchases | ✅ code |
| TestFlight build + sandbox IAP + push certificate | 🔧 |

---

## Consolidated blocker list (must fix before production)
1. ⛔ APP_STORE premium activation — needs the documented rules/Cloud-Function change.
2. ⛔ App icon / launch screen / asset catalog missing.
3. 🔧 APNs key upload to Firebase (without it: no pushes at all).
4. 🔧 Worker URL + API key values.
5. 🔧 App Store Connect product; Apple/Google sign-in providers in Firebase.
6. 📱🤝 The full device + mixed-Android test pass (O + P).
