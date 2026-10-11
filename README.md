# FirstResponse

Explains why a government service rejected you and what to fix, in what order.
A verified rulebook decides the answer; AI is only used later to read messy
input and to rephrase output.

Not affiliated with any government body.

## Layout

| Path | What it is |
| --- | --- |
| `packages/core_rules` | Pure Dart engine: rule model, matcher, fix sequencer (#12), life-certificate schedule (#9). No `dart:io`, so it runs in the app, on web and on a server. |
| `rules/records.json` | Records that can be wrong (Aadhaar, PAN, bank KYC…), which copies from which, and display labels. |
| `rules/packs/<portal>/` | One rule pack per portal: `pack.json`, one JSON file per rule in `rules/`, golden cases in `golden/`. |
| `apps/api` | Dart (Shelf) HTTP API: diagnose, confirm, rulebook downloads, life-certificate schedule, admin review queue. |
| `apps/app` | Flutter app for Android, iOS and the logged-in web consoles. Diagnoses offline from a bundled copy of the rulebook. |

## Commands

Needs Flutter 3.47 or later (includes Dart).

```sh
flutter pub get                                   # whole workspace

cd packages/core_rules
dart run core_rules:rules validate                # load and check every pack
dart run core_rules:rules golden                  # run golden cases
dart run core_rules:rules diagnose "Biometric data did not match"
dart run core_rules:rules bundle ../../apps/app/assets/rulebook.json
dart test

cd ../../apps/app
flutter test
flutter run -d chrome
```

Run `bundle` before running or testing the app; the bundle is generated, not
checked in.

```sh
cd apps/api
ADMIN_TOKEN=dev-only dart run bin/server.dart     # http://localhost:8080
```

## API

| Route | Does |
| --- | --- |
| `POST /v1/diagnose` `{text, portal?, code?, lang?}` | `answer` with rule, fix and sequence; `confirm` with candidates; or `review` with a `reviewId` |
| `POST /v1/diagnose/confirm` `{text, ruleId, …}` | User picked a candidate; only rules the engine offered are accepted |
| `POST /v1/diagnose/reject` `{text, …}` | User said no candidate fits; queues it for review |
| `GET /v1/rulebook` | Offline bundle for the app, with an ETag of pack versions |
| `GET /v1/life-certificate?dob=YYYY-MM-DD` | Window, days left, upcoming reminder dates |
| `GET /v1/admin/review?status=open` | Review queue, oldest first (Bearer `ADMIN_TOKEN`) |
| `POST /v1/admin/review/<id>/resolve` `{ruleId \| null, reviewer, note?}` | Map an input to a rule, or mark that a new rule is needed |
| `GET /v1/admin/review/golden` | Resolved items as golden cases, ready to add to a pack |

Identity numbers (Aadhaar, PAN, account numbers) are masked inside the engine
before anything is stored or returned, and request logs hold only method,
path and status. The review queue is in memory until Postgres is added.

## Writing a rule

Add a JSON file under `rules/packs/<portal>/rules/` and at least one golden
case. New rules start as `"status": "draft"`; the app shows them with an
"unverified" warning. A reviewer marks a rule `verified` only after checking
it against the official source, and must fill in `verifiedOn`, `reviewer` and
`reverifyBy`. The validator rejects a verified rule without them.

Matching runs in order: exact code, phrase, regex, then trigram similarity.
Confidence 0.85 or higher answers; 0.60 to 0.85 asks the user to confirm;
lower goes to review. Fuzzy and bare-number matches can never answer on their
own.

Set `"propagates": false` when the fix does not change values other records
copy (a biometric update), and `"generic": true` for catch-all rules that
should yield to a specific match.

## Changes from the build plan

The plan assumed a TypeScript monorepo (Expo + Next.js + Node). We chose:

- **Dart everywhere.** One engine in `core_rules`, used by the Flutter app
  offline and, later, by a Dart API server. The engine is written once.
- **Static site for SEO.** Flutter web renders to a canvas and indexes
  poorly, so the public one-page-per-error-code site will be generated as
  static HTML from the rule JSON. Flutter web serves the logged-in agent,
  professional and admin consoles.
- **Browser extension (#4)** stays TypeScript; it only calls the API.
