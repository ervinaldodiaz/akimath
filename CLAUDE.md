# AkiMath

Adaptive math challenges in Mexican Spanish, with a dog called Aki. Flutter client,
TypeScript backend, Postgres on Neon (planned). One repository — see
[ARCHITECTURE.md](ARCHITECTURE.md) §1 for why.

**The audience is adults, and nobody under 18 is an intended user** (Mexico and
Spanish-speaking LatAm, decision #1; adults-only since 2026-08-29,
[ADR 0004](docs/adr/0004-the-game-is-for-adults.md)). Decision #1 is about **markets** and is
untouched; what moved is the audience, which said *"and children can play too"* from 2026-08-17
until 0004 reversed it. **The refusal happens at link time and nowhere else** — 0004's amendment
picked Reading A — so an under-18 gets no account, while anyone who never taps the sign-in door
installs the app and plays offline for ever, because nothing gates play. **"Adults only" means
accounts only**, and the reasoning is worth carrying: the legal weight comes from holding data, and
offline holds nothing on our side.

That is half the story and the other half is the half that rots. **Adults have data-protection
rights.** The privacy notice, the deletion path and the 400-and-30-day retention figures all
survive 0004 untouched, and so does Gate A — **narrowed, not closed**. Its brief is
`docs/gates/gate-a-adult-data-consult.md`; the children's-data one beside it is superseded and
carries a *do not send* header, and it is kept because it is the reason several frozen values look
the way they do.

**`players.age_band` still exists, and it stopped being a routing decision.** It is resolved on the
device before the device obtains any session — that much is unchanged — but after 0004 there is one
population, so nothing routes. What the column holds is **the declaration the player made**,
written once at link time by one `INSERT` that nothing ever `UPDATE`s. It therefore keeps a
vocabulary it no longer issues: the frozen `CHECK` still names `under_13` and `13_17`,
**deliberately**, because a refused minor never links and the two values go dead by construction
rather than by a migration — and deleting them would foreclose the still-open question of whether a
refusal should be recorded at all. `AgeGate.consentAge` is **still 13 in the code**; it moves to 18
with the refusal a sibling change is building, and whether 18 is the right line is Gate A's Q-A1.

Where a comment or a document says "a child", ask whether it means *the player*, specifically *the
under-13 case*, or **a premise that is simply gone**. Two corrections are layered here — 2026-08-17
said the product is not child-directed, 2026-08-29 said children are not an audience — and most of
the prose predates both.

**Before adding *any* dependency, check whether it phones home; if it does, it does not go in.**
That rule is unchanged and its reason is new. It used to stand on *a mixed audience is governed by
its youngest member*, and that premise went with 0004; the standing refusal of analytics, ads,
attribution and crash reporting is still a **category** refusal rather than a per-dependency
question, and it now stands on three grounds no audience clause touches — the supply-chain surface
of the closures below, ADR 0003's recurring-per-version audit cost, and data minimisation under the
LFPDPPP, which applies to adults (0004's amendment §2). A rule whose stated reason has died is a
rule the next person argues away, which is why the reason is written here and not only the rule.
Today the constraint holds by construction, and the four
shipping sets are — audited 2026-08-27, each against its own manifest and its own lock file:

- `app/` ships **five** at runtime: `flutter`, `cupertino_icons`, `meta`, `shared_preferences`
  (added 2026-08-16) and `crypto` (added 2026-08-20 for the offline HMAC verifier), the last two
  with their audits recorded in `dependency_allowlist_test.dart` itself. The **transitive runtime
  closure is 28 packages**, all Flutter-team or Dart-team; the only ones exposing a network API are
  the SDK itself (`flutter`, `sky_engine`, `web`), which is where `app/lib/api/`'s `dart:io` client
  gets its socket. No plugin in that closure references one.
- `packages/core` has **no `dependencies` key at all** — the zero-dependency package.
- `packages/server` has **six**: four third-party, pinned exactly (`pg`, `hono`,
  `@hono/node-server`, `jose`), plus the first-party `@akimath/core` and `@akimath/contract`
  linked by `file:` path. Its transitive runtime tree is **17 third-party packages**, thirteen of
  them `pg`'s.
- `packages/contract` has exactly one: `zod`, pinned to an exact `4.4.3` because the pack
  determinism gate is byte-for-byte, and bringing nothing transitively.

**The gate is each package's `dependency-allowlist` test, and all four bite** — proven by
falsification rather than assumed, since a list compared only against itself is green by
construction.

**Code, identifiers, comments and docs are in English.** Only end-user-visible text is in
es-MX.

## Where the design lives

The source of truth for every screen is a **Claude Design project**, reachable through the
`claude_design` MCP (`/design-login` if a session has no auth):

- project `11887b49-aa66-4b2f-b059-de9100b124c1`
- `AkiMath Pantallas Base.dc.html` — inicio, reto, acierto, error, mapa
- `AkiMath Reactivos y Puzzles.dc.html` — the six families and the five boards
- `AkiMath Primera Vez y Cuenta.dc.html` — onboarding and auth
- `AkiMath Perfil y Estados.dc.html` — perfil, ajustes and the eight cross-cutting states
- `AkiMath Marca.dc.html`, `Aki Hoja de Personaje.dc.html`, `TecladoReactivo`, `TecladoPuzzle`

**Read it, do not write it.** `_ds/` is another team's design system and is out of bounds.

Worth stating because it was assumed unreachable and cost real time twice: `f0-brand-icons`
carried a *"blocked, the digests cannot be opened"* note for weeks, re-checked the morning it
turned out they could. **The raw `.dc.html` is the primary source** — its `<svg>` elements carry
verbatim path data, stroke widths and caps that a prose digest paraphrases.

## Layout

```
app/                      the Flutter client — the only Dart package
  lib/api/                 the hand-written API client (ADR 0003, superseding 0001). `dart:io`, no dependency
  lib/design/brand/spec/   pure geometry: no Canvas, no widgets, testable without mocks
  lib/design/brand/        the adapter that paints that spec
  lib/design/tokens/       colors, type, shape. No color literal lives outside tokens/
  lib/features/            screens
  test/architecture/       import-graph and literal gates: pure predicates + one SourceTree adapter
packages/server/          @akimath/server — pure `routing.ts`, IO in `adapters/`
packages/contract/        @akimath/contract — the offline pack format, pure; emitter in `adapters/`
packages/core/            @akimath/core — the rederivation machine. ZERO runtime dependencies,
                          no ambient IO; the one adapter writes the golden artifacts
contract/                 the frozen artifacts: 3 schemas, 37 fixtures, canon.golden.json,
                          openapi.json (OpenAPI 3.0.3, emitted, byte-diffed and oasdiff'd)
docs/adr/                 0004 makes the game adults-only; 0003 decides the Dart API client,
                          superseding 0001; 0002 auth and sync; older decisions live in
                          ARCHITECTURE.md
```

`app/lib/api/` now exists and holds seven of the contract's operations. `packages/contract` holds
the offline pack format and its OpenAPI half.

## What exists today

- **Built and tested — and playable.** `main.dart` opens the round: an item renders, the keypad
  takes an answer, a verdict comes back. On top of the brand layer sit the math compositor
  (`design/math/`), the press primitives, the dashed outline, the verdict encoding, the keypad,
  and `features/round/` with its three pure policies, plus the stat readouts — tiles, both pill
  sizes, the counter chip and the baseline meter — and the two verdict screens, `03 Acierto` and
  `04 Error`, which show time and streak and **no rating**: F2 has no server, so nothing on them is
  a figure sync could later contradict. `features/shell/` is the frame: cream, a banner slot, and a
  **bottom bar with three roots** — `Inicio`, `Mapa` and `Perfil`. `visibleTabs` returns nothing
  while one root exists, so the bar was absent by rule rather than by omission.
  **`features/progress/` is deleted; `Perfil` holds what `Avance` showed** (below), in two halves
  that fail independently: the figures the device knows — days practised and the current run,
  moved out of Ajustes because what a player has done is not a setting — and the history the
  server knows, from `GET /me/history`. The three history states somebody has to act on get the
  `HISTORIAL` section and a banner; a refused session gets no retry, because asking twice with a
  dead token gets the same refusal, and the silence elsewhere is the same reading as the toggles
  Ajustes does not draw (DR-P2). **No rating, and accuracy is the device's own.** F4 landed and
  `ratingDelta` is a real figure now — null only for a session that spanned two skills and for one
  that only calibrated — but `GET /me/standing` answers a rating **per skill** and no single number
  over a list of Glicko ratings is a fact about a player, so the slot stays empty rather than being
  averaged into existence; accuracy comes from the record `features/stats/` keeps of what was
  actually answered, which needs no server at all. **What "actually answered" means was wrong by
  one surface until 2026-09-02**: the calibration probe graded ten real pack items and recorded
  none of them, so a player who finished the first run read `10 RETOS` — the probe advances the
  same series cursor a series does — beside no `ACIERTOS` tile at all, while `LocalStats.accuracy`
  documents an absent figure as *"the player has answered nothing"*. It was an omission and not a
  policy, and the fact that settles it is that two of the three device figures were already wired
  to the probe, `0.7` saying in as many words that probe items are *"challenges this player did"*.
  The probe now reports each graded item through the same `onGraded` seam the round has. **The
  teaching item still records nothing** — `0.3` teaches how the app works rather than measuring
  the player — and nothing about the probe produces a level, a rank or a rating, which is what
  `0.4`'s *"No se califica"* and `0.6`'s *"No es calificación"* mean by the word. The
  session that makes any of it possible is held by `RootScaffold` — two roots have to agree about
  whether there is an account, and their common ancestor is the only place that can hold it. In
  memory only; `LinkedSession.toString` does not carry the token, because `toString` reaches logs
  and crash reports. The app opens on **`FirstRunGate`**, which reads one
  boolean and shows either the first run — `0.2 Bienvenida`, then `0.3 Primer reto`, a fixed teaching
  item that reads no pack, records no day and shows no streak — or the **home**: Aki, the
  `RETO DEL DÍA` preview composed by the real compositor, the week strip, and
  `ROMPECABEZAS` — **one card per puzzle the pack carries**, named by the pure `puzzleMenu`. A series is pushed from
  there as a full-screen route with no navigation affordance. The first run completes when the item is
  **solved**; leaving it, by the close control or a system back, returns to the welcome and sets
  nothing. The streak is **earned within a session** — `DayLog` records
  the day on submit and the home re-reads it — and is persisted by `shared_preferences`.
  **Verified on a device across two launches of two different binaries** (2026-08-17): a build with
  no write code read a day the previous build had written, with the key confirmed on disk. CocoaPods
  is required for the iOS build — `pod` must be installed or `flutter run` cannot link the plugin. **3362 Flutter tests, green — among them `app/lib/api/`, which is
  checked against `contract/openapi.json` by `test/api/contract_parity_test.dart` the way the
  server's half is.**
  **The streak can say it is about to go, and that it went.** `streakLength` has answered *how
  long* since F2 and nothing could ask *is it about to go* — a question that needs a time of day
  the first deliberately ignores. `features/home/policy/streak_state.dart` adds it as one closed
  set and **asks `streakLength`** rather than re-walking the days, so the home and the screen
  cannot drift. `4.12 Racha en riesgo` and `4.13 Racha perdida` are the only two of that
  document's fifteen screens whose every figure a `DayLog` and a clock already produce, and both
  are **pushed over the home** from `HomeRoute` — which has the log, the pack and the navigator,
  none of which `FirstRunGate` has. The two are deliberately asymmetric: the warning comes back on
  every launch of a day that is still at risk, and the page turn happens once, which is true by
  construction because only one of them is recorded. `4.13`'s `1` is **`dayOfNewRun`, not the
  streak** — the screen is reached before the player has solved, where `streakLength` correctly
  returns 0, and one function answering both would be two callers disagreeing about what it counts.
  Neither prints a rating.
  **Every glyph is the design's own geometry.** `f0-brand-icons` was blocked from the day it was
  written because the design digests could not be opened, so all sixteen rendered as `▲`, `⚙`,
  `‹`, `⌫` — a deliberate, visible placeholder. They opened. `design/icons/spec/icon_paths.dart`
  holds each mark's verbatim `d`, viewBox, stroke width and caps, and `svg_path.dart` (PURE) turns
  a `d` into a `Path`. **The strings stay strings**: that is the only form in which "transcribed,
  never redrawn" can be checked by reading, because the spec file and the design document then hold
  the same characters. The parser supports `M L H V C S A Z` and **throws on anything else** — a
  quiet skip draws two thirds of a glyph on a screen with a green suite, which the first version
  did. `size` is the **height**, because `mapsTo` is 30×24 and squaring it distorts the arrow.
  The bottom bar's four marks retired a named fork. `nav_glyph_spec.dart` hand-drew three of them
  while the digests were shut, and it was tolerable only because it said so: its own doc comment
  named itself a fork and a counter held the exception to three, so it could not quietly grow a
  fourth. The digests opened, the real `0 0 26 26` paths are in hand, and drawing by eye when the
  data exists became the mistake that file apologised for — so it went, in #80, and
  `brand_glyph.dart` records the retirement where the four names now live. The character sheet
  draws the whole set, because a
  parser test can say the geometry lands inside its viewBox and cannot say the flame looks like a
  flame.
  **`Perfil` is the profile home and `Ajustes` is the stack above it.** Declared rule 1 names the
  bar's homes as *inicio, mapa, progreso y perfil*; the third root was labelled after a settings
  screen, which that rule does not name. The content splits along the seam a player feels — who I
  am is the root, what the app does is the stack — and the stack pushes onto the **tab's own
  navigator** (`TabStack`) so the bar stays underneath, which is what the group badge over 4.1–4.7
  says. `RootScaffold`'s `PopScope` lets a system back pop the tab before the app closes. The list
  holds **five of the design's six rows, plus one it does not draw** — `Cómo se leen los retos`,
  which is in no document and so sits after everything that is. `Ayuda` is the one still absent,
  because there is nowhere for it to go: absent rather than greyed out, since a control that
  cannot act reads as broken rather than as unbuilt and a player cannot tell *not yet* from *not
  for you* (DR-P2). A test pins `Ayuda` absent so it turns red the day somebody draws it. **The nav
  fork is deleted** — all four marks are transcribed, every tab has its own, and the
  house-as-fallback that once made two tabs share a mark is gone as well as caught.
  **`Avance` absorbed into it, and `Mapa` got its door after.** No document draws a progress screen;
  every figure that root held is one `4.1` puts under the identity, and splitting them left two
  half-empty screens where the design has one full one. Perfil now draws the identity, the
  headline pair — a white `DÍAS` card at `flex 1.3` beside a **yellow** `RACHA` at `flex 1`,
  because the filled card is the one the screen is about — and `HISTORIAL`, absent when there is
  nothing true to say. **`AppTab.progress` stays in the enum**: rule 1 names it a home and nobody
  has drawn one, which is a different fact from it not existing, and `rootsPresentToday` is the
  list that moves — nothing in `visibleTabs` has changed on any of the four occasions: none, two,
  three, two, three.
  **A key's fill says what pressing it does** — `KeyRole` in the pure layout, the colour in
  the adapter; all three pads were white, and the design draws digits white, the operator strip
  accent, backspace quiet and submit the action green. Exactly one key on a pad is green, and a
  test says so.
  **The offline loop closes.** `issuePack` and `submitAttempts` had zero callers and the attempt
  journal had zero writers, so seven endpoints, a provisioned database and digest grading were all
  unreachable from actually playing — and `HISTORIAL` could never fill however much anyone played.
  With a session the home **asks for a pack and plays that one**: same six families, same boards,
  every item carrying a `(packId, index)` the server can grade. Without one it plays the bundled
  pack for ever and by design (ADR 0002). Reading an issued pack needed HMAC, which needed a
  DEP-1 call: **`package:crypto` is in**, audited in the allowlist test, two packages net-new to
  the shipping set. `content/answer_digest.dart` is the verifier and is held to
  `contract/fixtures/digest.golden.json`, a table emitted from TypeScript **before** the Dart side
  existed so the two could not drift. `Item.answer` is a sealed `PlainAnswer | DigestAnswer`, and
  `expected` throws on the second — which is how the first digest item played found that
  `diagnose` was re-deciding the verdict by calling `grade`. It takes the verdict now: one
  decision, made once. **An item's id is its address**, `packId#index`, so the thing the round
  carries is the thing the journal needs. `AttemptSync` records on every answer without touching
  the network and flushes when there is a session — including when the session *arrives*, since a
  player links on the profile tab while `IndexedStack` keeps the home alive. **A pack survives a
  relaunch**: the device stores the id and nothing else, and `GET /packs/{packId}` — one of the seven
  operations the Dart client calls — rebuilds it byte for byte, so a fetch is the same pack rather than a row per
  launch per player. `packRefresh` is pure and holds the three branches; **a 404 is the one answer
  that means issue a new one**, while refused, broken or unreachable mint nothing. The id is
  written *before* the pack is adopted, or a device would play one it had not recorded.
  **An issued item explains the mistake it anticipated**: the frozen format keys a distractor by
  the digest of the wrong answer, so the map lives on `ItemAnswer` — one map on `Item` would be one
  map with two meanings. `diagnose` no longer knows what an item is; the key is handed in, the same
  split `gradeItem` made, and the pure half got smaller.
  **Ajustes has a way out.** `features/preferences/` carries the erasure flow: a text door under
  the account, drawn only where `erasureOffered` says a session could carry the request, and a
  full screen rather than a dialog because the question has to fit a sentence about what
  *survives* — the address stays registered with the identity provider, which is not ours to
  delete. `policy/erasure.dart` is pure and holds the copy; `ui/erase_account_route.dart` takes
  the request as a **closure** rather than an `ApiClient`, which is what lets a `testWidgets`
  drive the whole sequence — a real socket inside a fake-async zone hangs on `!timersPending`.
  A 204 is read as a success **without parsing a body**: a client that reads it the way it reads
  `GET /me` turns an erasure into a `FormatException`, and that is the one error here a retry
  cannot fix, because the row is already gone.
  **`api/sync.dart` can ask for a pack and send back what was answered** — `issuePack` and
  `submitAttempts`, the two halves of the offline loop from the device's side. An
  `AttemptSubmission` refuses on the device to name neither source or both, because a 400 a player
  waits for is worse than a batch that never leaves; it carries **no verdict**, because the frozen
  schema has nowhere to put one; and `elapsedMs` travels, because the server cannot derive time on
  task — a pack item has no `issued_at` of its own. The four failures are told apart by what a
  client should *do*: a 400 is a batch to drop, a 404 is a batch that landed nowhere, and
  unreachable is the one worth keeping, because the server drops a duplicate by itself (0004).
  **The device links its player as soon as it has a session**, which is what makes any of the
  server reachable: until it did, an account was created and no player was ever attached, so
  `GET /me` answered 404 for ever and every operation built on it was unreachable. The trigger is
  the *session appearing*, not the sign-in callback, so a session arriving any other way is linked
  too. The id is minted on the device and kept (`PrefsPlayerIdStore`) — a fresh one per launch
  would 409 on every launch after the first — and it is **version 4 by construction**, because the
  frozen `PlayerLink` pins a version and a variant nibble and sixteen random bytes fail that about
  one time in eight. The band travels from the age gate, never off the credential: linking is an
  adult's act and the player need not be an adult. One round trip, because `POST /players/link`
  already answers the frozen `Me`. An account that already has another device's player is
  **`AccountState.otherDevice`** — one account, one player (0003), and which phone it belongs to is
  a choice nobody has designed, so the app says so and offers nothing it cannot do. Still waiting
  on the play loop:
  `features/sync/`, which remembers an answered pack item until the server has it. That journal is
  persisted rather than held in memory, because play is offline and sync is not: a player answers
  on a bus and the batch goes days and several launches later. It keeps at most what one batch can
  carry — the server refuses more than two hundred, so a longer journal could never be flushed —
  and what survives a failed sync is decided in one place: a batch that landed is gone, a batch the
  server could not read is **dropped** because resending a malformed one resends it for ever, and a
  refused session or no answer at all is **kept**, which is what the journal is for.
  **All six frozen stimulus families draw and grade** — arithmetic, number series, matrix,
  analogy, the function machine and figurate. `content/model/stimulus_reader.dart` holds the six
  hand-written parsers and `test/content/model/stimulus_fixture_test.dart` checks each against
  `contract/fixtures/stimulus/`, one golden and one rejection row per kind, reporting
  *6 frozen kinds → 6 readable, 0 pending*. That is R2's remedy moved from grading to layout, and
  it is what makes adding a family mechanical. Four of them share `StimulusTile`; figurate paints
  dots from `design/math/spec/figurate_layout.dart`, the one file excluded from
  `no_geometry_literal_test` and excluded by name rather than by directory.
  Content is a **bundled 70-item JSON pack** (`app/assets/packs/starter.json`) read by
  `content/pack_reader.dart` — the one adapter in `content/`. An expired or malformed pack is
  refused where it is read. **Its order is a product decision under test**: `seriesPlan` takes five
  items in pack order, so `pack_variety_test.dart` holds the pack to showing all six families
  inside the first ten items and no more than two of a kind in any series. **Grading answers to the frozen contract**: `content/model/canon.dart` is
  checked against `contract/fixtures/canon.golden.json` itself, 19 vectors in both modes, which is
  what stops the Dart and TypeScript canonicalisers drifting (R2).
  **All five frozen puzzle formats draw and grade** — KenKen, Killer, the magic square, Kakuro
  and the sopa de letras. `content/model/puzzle_reader.dart` parses them and
  `test/content/model/puzzle_fixture_test.dart` reports *5 frozen kinds → 5 readable, 0 pending*,
  with one exception named rather than hidden: Kakuro's `solution_not_unique` is the builder's,
  because only a solver can see it. Four share `PuzzleScreen` — a board, a keypad sized by
  `PuzzleBoard.highestValue`, and the pure entry policy; the sopa de letras has its own screen
  because it has no keypad, and its drag is resolved by `letterAt` rather than by a detector per
  cell. **Every one of them is reachable**: `home_route_test.dart` walks the shipped pack, opens
  each puzzle from the home and comes back, reporting *5 shipped → 5 kinds reachable*. That gate
  exists because the home once held `pack.puzzles.first` behind an `is! KenKenPuzzle` guard, and
  four of the five formats were unreachable with every suite green.
- **No longer a scaffold, plus the frozen schema.** `packages/server` routes the contract's nine
  operations — eight to a handler, one to a 501 — and `GET /health` through a pure `route()`
  function, and now also holds the database:
  `migrations/0001_initial.sql` (seven tables, two roles, and the grants that make `attempts`
  append-only) plus seven forward-only ALTERs, the forward-only runner split pure/adapter as `src/migrate.ts` versus
  `src/adapters/migrate-runner.ts`, `src/retention.ts` (PURE — the only home of the 400-day and
  30-day figures) and the committed `schema.sql` snapshot. **466 tests — 331 green and 135 skipped
  for want of a Postgres — 97.00% mutation score with those 135 skipped, 0 clones.** That figure
  is stable — four runs over one unchanged tree agreed file by file, unlike `packages/contract`
  below — and it is down from the 98.92% previously recorded against a smaller `src/`.
  **The two are not
  straightforwardly comparable**: nothing records whether that one was taken against a database,
  and the single biggest drag on this one is `packs.ts` at 48.15%, whose `issue-pack` and
  `offline-packs` suites are both skipped here — it read 44.00% until `contentIdFor` landed with a
  unit test that needs no Postgres, which is the whole reason that decision went into the pure
  module rather than into `shipped-packs.ts`. The rating work itself is not the drop —
  `rating.ts` and `standing.ts` are 100%. Four runtime dependencies, each
  pinned exactly with its DEP-1 audit in `test/dependency-allowlist.test.ts`: `pg`, `hono` +
  `@hono/node-server` (which own the socket — Hono's *router* is deliberately unused, so
  `CONTRACTED_OPERATIONS` stays where the parity gate can read it), and `jose`.
  **It can tell who is asking.** `src/session.ts` reads the `Authorization` header (PURE, three
  cases — absent, malformed, bearer), `src/auth-config.ts` derives the issuer and JWKS URL from
  `NEON_AUTH_BASE_URL` (PURE; a missing or plaintext one **refuses startup** rather than turning
  into a 401 per request), and `src/adapters/session-verifier.ts` verifies the EdDSA JWT against a
  key set that is *injected*, so the tests run the real function against real Ed25519 keys.
  **The server runs.** It had never started, and the recorded reason —
  *`NEON_AUTH_BASE_URL` is not set anywhere yet* — stopped being true the day somebody pasted it
  into `.env.local` and stayed in this file for weeks. All three variables were there; `npm run
  dev` was `tsx watch src/main.ts`, which reads none of them. The three scripts that run against a
  real environment now carry `--env-file-if-exists=.env.local`, and `test/scripts-load-their-env.test.ts`
  keeps it that way — while asserting the **suite** does not, because a test run that picked up a
  live `DATABASE_URL` would be a test run against Neon. **The tolerant spelling matters**: the
  strict `--env-file` fails the process outright when the file is absent, and CI has none — it
  hands the connection strings in as real environment variables against a service container. Where
  both exist the real environment wins, which is the order that makes CI authoritative.
  The refusal to boot without a key set is right and stays: a server answering 401 to everything
  reads as broken authentication rather than as a missing variable.
  **`PORT` defaults to 3000**, and `.env.local` overrides it to 8787 on this machine, which is what
  the app's `--dart-define=AKIMATH_API_BASE_URL` points at.
  **`npm run retention` cannot run here**, which is a different statement from not running at
  all: it runs nightly in Actions — `.github/workflows/retention.yml`, the step *Delete what has
  expired*, gated on `vars.RETENTION_ENABLED == 'true'` and green every night for the last eight —
  from a `RETENTION_DATABASE_URL` that is deliberately its own credential for the `retention_job`
  role rather than a borrow of the request path's. That secret is CI's and only CI's:
  `packages/server/.env.local` holds `MIGRATE_DATABASE_URL`, `DATABASE_URL`, `NEON_AUTH_BASE_URL`
  and `PORT`, and no `RETENTION_DATABASE_URL`, so the command typed on this machine has nothing to
  connect as. A different kind of blocker from a missing flag.
  **Eight endpoints are implemented.** Three are the account's whole life — `GET /me` reads the
  profile, `POST /players/link` creates it, `DELETE /me` erases it — three are the offline loop,
  `POST /packs` issuing, `GET /packs/{packId}` fetching again and `POST /attempts` grading, and two
  read back what the loop wrote: `GET /me/history` a session at a time and `GET /me/standing` the
  rating those sessions moved. Each verifies the
  token and connects through `src/adapters/request-database.ts`, which opens a transaction and
  `SET LOCAL ROLE`s into a role that is never the owner. `GET /me` answers the frozen `Me` shape,
  or **404 and not 401** when the account has no player yet. `POST /players/link` takes the
  account from the *session* and refuses a body that so much as names one; it runs both reads and
  the write in one transaction, so a race loses to a **409** rather than to a constraint.
  `route()` returns *an answer* or *whose handler should produce one*, so the surface stays where
  the parity gate reads it, and `IMPLEMENTED_OPERATIONS` is the contract's 501 list inverted,
  checked in both directions — an endpoint stops advertising itself as unbuilt in the same diff
  that builds it. The one left over — `GET /items/next` — still answers **501**.
  **Erasure is the one handler that does not run as `app_request`.** That role holds DELETE on no
  table, which is what makes the append-only-attempts invariant structural; `DELETE /me` goes
  through `inErasureRole` (`SET LOCAL ROLE retention_job`) and deletes one `players` row, and the
  five tables that reference it go with it by `ON DELETE CASCADE` — `test/delete-me.test.ts`
  counts the rows in every one rather than trusting the schema to still say so, and
  `template_stats` survives by design because it carries no player id. The hole is kept to one:
  `test/one-way-to-erase.test.ts` names the only two files under `src/` allowed to say
  `inErasureRole`, the same shape as `one-way-to-log.test.ts`.
  **An authored item is graded by its digest, which is the only way it can be.** Rederivation
  needs a template reference and an authored item has none — so `(pack_id, pack_index)` could not
  address one and nothing could grade it, which meant *the pack the app actually ships could never
  be synced*: seventy of its eighty items are authored. Migration 0005 renames `template_refs` to
  **`item_refs`**, because it now holds two kinds — `{kind: "template", …}` to rederive and
  `{kind: "digest", digest, skill_id}` to verify — one per item and in the same order, which is
  what makes `(pack_id, index)` address anything. `packages/core`'s `manifest.ts` is the one
  definition of both. Verifying is `HMAC(pack_salt, canonicalize(what was typed))` against what the
  pack already carries, through the same two functions the pack builder used, so **the server never
  learns an authored answer** — it holds a digest and can only confirm or deny a guess, which is a
  stronger position than rederivation leaves it in. A pack of authored items is re-fetched by
  rebuilding the content the row names (migration 0006); a pack that carried digests and named no
  content could not be rebuilt, and nothing writes that combination.
  **`POST /attempts` grades by rederiving, and that is the invariant made true by construction.**
  A submission carries no `ok` — `readAttemptBatch` refuses a body that mentions one, along with
  every other unknown property — so the server resolves the recorded
  `(template_id, template_version, seed, ladder_step)`, regenerates the item and compares canonical
  spellings. Both halves of "canonical" come from `packages/contract`, the package Dart is
  golden-tested against, because a third implementation here is exactly R2. `@akimath/core` and
  `@akimath/contract` are therefore the package's first **first-party** runtime dependencies, kept
  in their own list in `test/dependency-allowlist.test.ts`: DEP-1 exists to summon a human about
  third-party code that phones home, a workspace link has no version to pin, and an unsatisfiable
  rule gets deleted. They are held to `file:../<name>` and to bringing nothing unaudited — today
  `zod`, and the test says so.
  An attempt names **exactly one source**, mirroring `attempts_one_source`, and a batch is one
  transaction: every source is resolved before anything is written, so an unknown item is a 404
  naming its index with nothing recorded. **A retry is harmless**, decided 2026-08-19 and made so
  by migration 0004: an item is answered **once**, two partial unique indexes say so, and the
  insert is `ON CONFLICT DO NOTHING` — the verdicts are recomputed from the same inputs, so the
  second answer is the first, idempotent by nature the way `linkPlayer` is. A batch naming the
  same item twice is refused before any of it is read, because keeping one of two rows and
  answering as if both landed is worse than saying so. The constraint is the thing to argue with
  if replaying a series ever becomes a feature, which is the right place for that argument.
  0004 also persists **`session_id`**, which every submission has carried since the freeze with
  nowhere to land — it is what a `GET /me/history` entry is grouped by.
  **`POST /packs` is the ninth operation, added because there were only eight.**
  `GET /packs/{packId}` fetched a pack by an id and nothing minted one, so `offline_packs` could
  only ever be empty and a pack attempt could never reach `POST /attempts`. Issuing takes no body —
  the player comes from the session — and no `Idempotency-Key`, because issuing is not idempotent
  by nature and a second pack is harmless. **Every item was template-generated once, and none is now**: migration 0005
  made an authored item addressable by digest, the generator went, and what is issued is a copy of
  the shipped pack — eighty authored items whose every manifest entry is a digest. `src/packs.ts` builds the pack
  and its manifest *together and in the same order* — one list seen from the two ends of the
  offline loop — and `test/issue-pack.test.ts` closes it for real: issue, rederive the answer from
  the row the server wrote, sync it, and watch it come back `ok: true`. **What is issued is a copy of the pack the app
  already ships** — eighty items across six families and thirty-five boards. Migration 0006 adds
  `content_id`: the row *names* the content rather than storing it, because the artifact is 158 KB
  and it is the same 158 KB for every player, which is `ARCHITECTURE.md` §4's manifest argument one
  level up. **The name pins the artifact's bytes**, and it did not until 2026-08-29: the column held
  the bare `starter`, which resolves to whatever the build ships today, so editing an item inside
  `packages/core/pack/starter.json` — the ordinary content act `npm run build:pack` exists to make
  easy — silently re-pointed *every outstanding pack*. Within the thirty-day window a device
  re-fetched, was handed today's item at index *i*, answered it correctly, and was graded against
  the digest of the **old** item at index *i*: a right answer recorded `ok: false` in a table the
  request path can neither UPDATE nor DELETE. Constructed rather than argued about, from a two-item
  reorder, in `test/pack-content-is-pinned.test.ts`. `contentIdFor` in `src/packs.ts` now spells the
  id `starter@<sha256 of the file>`, so a moved artifact is the fact migration 0006's own comment
  already anticipated — *an unknown name is a 404 from a server that no longer ships it* — and
  `getOfflinePack` needed **no new branch and no migration**, because a bare `text` column can hold
  a longer string. The client reads that 404 as *ask for a new pack* (`pack_refresh.dart`), so the
  degradation is a fresh pack rather than a stranded device, and an attempt already earned against
  the body a device still holds syncs correctly — grading reads the digest and the salt off the row
  and never touches content. The rating is told the difficulty is **unknown** rather than handed
  whatever item now sits at that index. `readShippedPacks()` is keyed by that versioned id, which is
  what a row holds; `POST /packs` is the one caller that starts from a name and asks for the current
  version of one.
  `GET /packs/{packId}` rebuilds from that id plus the row's own window, so a re-fetch
  is byte-identical and neither instant is digested. A copy shares the content's salt, and that is
  not a leak: the salt ships inside every pack and every player gets the same content. The
  generator that made twenty subtractions is **gone** — after 0005 both kinds were equally
  gradeable, only one was worth playing, and code nothing calls is a claim about the server that is
  not true. `storedAnswer` lives in
  `packages/contract` so the pack builder and the server make one decision about shape and
  spelling — that is the bug from #50 and a second copy is how it returns. **It returned, and it
  is now a gate rather than a sentence.** The decision had **three** implementations while four
  comments said it had one: `lift.ts` read the raw field for a `/` and `gradeAnswer` wrote the
  `denominator === 1n` branch longhand, and every one of those comments named "the server issuing
  a pack" — which copies a pre-built artifact and derives no answer — so the two real copies were
  the two nobody would grep for. Measured before the fix, over 81 pairs and the whole of
  `CANON_INPUTS`, **the three agreed**, so no digest and no artifact moved. There are now two
  doors for the two inputs a caller can hold — `storedAnswer` for a `(numerator, denominator)`,
  `storedAnswerOf` for a canonical string, which validates — and the shape is **derived from** the
  spelling rather than computed beside it, so they cannot come apart. `4/1` stays a fraction:
  pack content may state it and folding it would restate an authored answer. The fourth copy is a
  red build now — `one-way-to-spell-an-answer.test.ts` in `packages/core` and `packages/server`
  walks the AST for two prohibitions, because the halves were copied separately: naming both shape
  words is deciding a shape by hand, calling `renderCanonicalAnswer` is spelling one. Both went
  red on `main`, each on the copy its own package held.
  **`GET /me/history` is a session at a time.** The frozen shape asks for a `score` and a `title`
  and neither means anything about one answered item. `ratingDelta` is the movement the rating
  engine recorded for that session at the moment both ends of the subtraction existed, never
  recomputed here, and it is **null** for the two kinds of session no single figure is a fact
  about — one that spanned two skills, where two ratings moved by different amounts, and one that
  only calibrated, where nothing measured the player and `0` already means *held*. `kind` is always
  `series`, because a puzzle leaves no row in any table so nothing can report one. A session
  spanning two skills is **not** named after either — `min(skill_id)` would call it whichever sorts
  first, which is not a fact about the session. `@akimath/core`'s `skillName()` is where a skill
  gets a name, since `skill_id` is a `smallint` in five tables and a name in none of them. The
  operation declares no parameters, so `HISTORY_LIMIT` is the server's cap and it is stated in
  `src/history.ts` rather than buried in the query.
  **The retention job sweeps what issuance leaves.** `runRetention` used to delete `diag_events`
  and `attempts` and keep every pack for ever; issuance turned that from theoretical into live. It
  now sweeps `offline_packs` past their window and `issued_items` too — last, and behind a
  `NOT EXISTS`, because both are referenced with `ON DELETE CASCADE` and deleting one early would
  take a child's answered history with it. `RETENTION_DAYS.sources` is keyed on when a source
  *stopped being usable*, so a pack outlives every attempt that could reference it by arithmetic,
  and the guard makes it true by construction. **`GET /packs/{packId}` rebuilds rather than
  reads a body back** — `offline_packs` stores a manifest and a salt, not fifty rows of rendered
  item, which is what the manifest is *for*. Every digest comes back identical, because the salt
  is a column and the answers rederive; `test/issue-pack.test.ts` issues a pack and asserts the
  re-fetch equals it exactly. The one thing that can differ is prose — the fallback diagnosis is
  copy and copy gets edited — and prose is in no digest. A pack belonging to somebody else is the
  same **404** as one that never existed, because telling them apart confirms a stranger's pack
  exists. **A path parameter is the router's to extract**: `route()` returns them named on the
  dispatch, so a handler never splits a path it did not match. **It does not delete the Neon Auth
  account** — identity lives in the provider's `neon_auth` schema and this service holds no
  credential that could remove it, so the email and the sign-in survive the call. That scope is
  written into the operation's `description` in `contract/openapi.json` rather than left for a
  caller to infer from a 204. A `204` is rendered by `context.body(null, 204)` and never by
  `context.json`, which throws on a null-body status; `NoContent` is a separate type from
  `Response` so a 204 carrying a body does not compile.
  **There is one way to write a log line.** `src/log.ts` (PURE) turns an event into one JSON
  object — `at`, `level`, `msg`, fields at the top level — and `src/adapters/logger.ts` is the
  **only** file under `src/` allowed to touch a stream, which `test/one-way-to-log.test.ts`
  enforces by scanning for `console.*` and `process.stdout` and reporting a count. **The logger
  cannot print a credential**: redaction runs over *values* as well as field names, at any depth
  and inside `msg` itself, so a JWT, a `Bearer …` header or the password in a connection string is
  replaced wherever it appears — the host and database survive, because that is usually why the
  line was written. Every request leaves one line carrying the **kind** of caller and never the
  caller. `pino` was audited and turned down: 14 transitive packages against this package's floor
  of zero, and path-based redaction that protects the fields you thought of.
  `packages/core`'s three build scripts keep `console.log` on purpose — their output is a developer
  watching `npm run emit`, not a log. The Flutter side needs nothing: `avoid_print` is active via
  `flutter_lints` and `app/lib` has zero prints **by rule**.
  **The database suites need a Postgres and skip without one** — set `TEST_DATABASE_URL` and they
  run; leave it unset and 135 of the 466 report as skipped rather than passing quietly. **At
  vitest's default parallelism the run is flaky on a loaded machine** — 38 to 102 failures, every
  one of them `Hook timed out in 10000ms` inside the `beforeEach` that calls `freshDatabase()`, and
  never an assertion. It predates any one change: excluding the newest test file reproduces it.
  `npm run test:db -- --maxWorkers=3` is green and quick, and CI's service container has not
  reported it.
- **The offline pack format, frozen.** `packages/contract` (`@akimath/contract`) holds the
  pack schema, the answer canonicalizer, the HMAC digest and the puzzle validators — all
  pure, with the emit script as the one adapter. `contract/` holds what it emits: the
  schemas, one golden fixture and one rejection row per stimulus and puzzle kind, their
  recorded normalisations, and `canon.golden.json`. 257 tests, green, 0 clones, and a mutation
  score of **91.15% to 91.85% — the figure is not reproducible**. Four runs over one unchanged
  tree gave 91.15, 91.50, 91.85 and 91.15, the two 91.15s with an identical per-file breakdown; so
  the 91.71% previously recorded sits inside the band and nothing here can be said to have moved.
  Quote a range for this package, not a number, until whatever drifts is found.
  **`npm run mutation` cannot produce any of them as configured**: `test/digest-golden.test.ts`
  reads `contract/fixtures/` by walking three directories up from its own file, and Stryker's
  sandbox is one level deeper than the package, so the initial test run dies on a missing fixture.
  That has been true since the test landed in #86, which is after 91.71% was recorded. The runs
  above put the sandbox where the test's relative path still resolves —
  `npx stryker run --tempDirName ../../tmp`, `tmp/` at the root being gitignored already.
  **Zod 4.4.3 is the repository's first runtime dependency**, pinned exactly
  because the determinism gate is byte-for-byte.
- **Does not exist.** One of the nine contracted endpoints — `GET /items/next`, which needs an
  issuance policy — no dev environment, no deploy, and no deployed *application*. **The database is
  provisioned**: a Neon project (`akimath`,
  `aws-us-east-1`, PostgreSQL 18.4) with all eight migrations applied, its connection strings in
  `packages/server/.env.local`, which is gitignored. `MIGRATE_DATABASE_URL` is the direct string and
  `DATABASE_URL` the pooled one; **`TEST_DATABASE_URL` is deliberately not set there**, because the
  harness drops and recreates the public schema on every run. **The pack builder is written**: `packages/core`'s
  `src/pack/` lifts authored items and template-generated ones into one pack, and
  `npm run build:pack` emits `packages/core/pack/starter.json` — 80 items across six families and
  35 boards, byte-identical on a second run, which is what makes the CI diff mean something.
  **Its CLI suite spawns the real script, and used to spawn it through `npx`.**
  `test/pack/cli.test.ts` is the only place `build-pack.ts` is exercised end to end — the refusal
  paths and the byte-identical re-emit among them — and five of its six cases run it in a
  subprocess. Against the package's 5s default that was green alone and red on a loaded machine:
  at load average 65 three cases failed, at 93 five did and **the failure blocked
  `.claude/hooks/verify-gate.sh` on a `git push`**, every one of them
  `Test timed out in 5000ms` and none of them an assertion — a gate reporting machine load as a
  defect in the pack builder, which is the result that teaches people to re-run until green
  (PROC-14). Two things were wrong and both are fixed. **`npx` was most of the cost**: 2.99–5.48s
  per spawn against 1.49–2.07s for the `node_modules/.bin/tsx` it ends up running, and it is a
  failure mode of its own — with several worktrees running their suites at once it reaches for the
  shared npm lock, answers `ECOMPROMISED` and tries to install from the network. The suite spawns
  that binary directly now, which is also what `npm run build:pack` resolves. **And the five
  spawning cases carry an explicit 30s**, stated per case rather than as a global `testTimeout`,
  so the ~340 cases that do not shell out stay honest at 5s. Measured after: 6/6 green at load 61,
  the slowest case 1492ms and the file 4.64s, down from 21.81s with one case timed out at load 41.
  **Do not copy the old `run()` helper into a new test** — spawn the local binary and say what the
  case is allowed to take.
  **Every generated item in it used to be ungradeable** and is not any more: the answer's *shape*
  and the *spelling* the digest was taken over were computed separately, so a whole answer of −9
  was digested as `-9/1` while the field beside it said `integer` — and `canonicalize("-9")` is
  `-9`. The same mismatch disabled the guard that drops a distractor equal to the right answer,
  so one item shipped a `subtracted_in_reverse` diagnosis whose digest *was* its own answer.
  Latent only because the app ships the authored pack. Both now come from one `shape`.
  Item generation beyond the one template family is still unwritten. **A template declares which
  skill it exercises** (`Template.skillId`), because `attempts.skill_id` is `NOT NULL` and nothing
  on the wire carries it — an attempt names an item, an item is a `TemplateRef`, and neither
  `issued_items` nor `offline_packs.template_refs` records a skill. The pack declaration used to
  state it a second time next to a template source and now **refuses** to: two places stating one
  fact is one place that can be wrong, and the wrong one would be the pack's. The rederivation
  machine is on the package's front door — `registryOf`, `resolve`, `rederive`, `issuable` and
  `coreRegistry()`, the last a *call* because every export is a function and a registry is a `Map`
  behind an interface. **The diagnosis copy is a value**, not `content/misconceptions.json`, which
  is deleted: `packages/server` issues packs inside a request and needs the same words, and reading
  another package's content directory from a request path is ambient IO in the one package that
  forbids it. `misconceptionCopy()` and `fallbackDiagnosis()` are the front door; the prose lives in
  `src/pack/misconception-copy.ts` and is the one file excluded from mutation testing, because every
  mutant there blanks a Spanish sentence and the only test that could kill one would restate it.
  It is parsed **on first use and not at module load**, which is not a style choice: a
  module-scope parse turns a bad edit into an import failure, every file importing it dies before
  its assertions run, and Stryker scores those mutants as survived. `misconceptions.ts` read
  56.31 that way and 93.27 once the parse was deferred, with the same tests. **`toManifestEntry`/`fromManifestEntry` are there too**: how a
  `TemplateRef` is written into `offline_packs.template_refs` and read back is one definition
  now, shared by the builder that will write it and the server that already reads it. It used
  to be a reader matching a comment in ARCHITECTURE, and a mismatch would have made
  `refForPackItem` return null for every real pack — a 404 indistinguishable from a missing row. **The math compositor is
  built**: `EsMxNumber`, `FractionMetrics`, `MathNode` (pure) and `MathView` + `FractionGlyph`
  (adapters) are landed and tested. Spike B cleared its criterion on 2026-08-16 — see
  `openspec/changes/archive/2026-08-26-f1b-math-compositor/spike-b/`.
- **CI exists, narrowed to the code that exists.** `.github/workflows/ci.yml` runs `changes`,
  `secrets` (gitleaks), `dart` (`flutter analyze --fatal-infos`, `flutter test`), `ts`
  (`npm run typecheck`, `npm test` in `packages/server`), `contract` (the same two in
  `packages/contract`, then `npm run emit`, `git add -A -- contract/` and
  `git diff --cached --exit-code -- contract/` — staged, because a bare `git diff` is blind to
  an artifact the author never committed), `core` (the same two in `packages/core`, then that same
  staged byte-diff **twice** — over `golden/` after `npm run emit` and over `pack/` after
  `npm run build:pack` — behind an `npm ci` in `packages/contract`, because core typechecks
  *through* contract's sources and TypeScript resolves `zod` from their real path rather than
  through the `file:` symlink), `spec` and `gate`. **`gate` needs all nine**, `core` among them.
  `protected-paths` and `integration` landed with the schema: the first refuses an unattended edit
  to `packages/server/migrations/**` or `schema.sql` unless a pull request carries the
  `allow-protected-edit` label, and the second runs the database suites and the snapshot diff
  against a **`postgres:18` service container** rather than ARCHITECTURE.md §8's ephemeral Neon
  branch — a container needs no account, no project and no secret, and what those tests assert is
  plain PostgreSQL behaviour. ARCHITECTURE.md §8's remaining jobs — compliance, mutation — are
  deliberately absent because the code they guard does not exist; `contract` now runs its `oasdiff`
  half too, version-pinned, failing only on a **breaking** change — a gate that fires on every
  addition trains people to switch it off — and that break can be **answered** rather than only
  obeyed: an `allow-breaking-contract` label on the pull request passes it, the same shape as
  `allow-protected-edit`, because before v1 ships a breaking change is ordinary and a gate with no
  way to say yes gets deleted instead. `gate` is registered on the `protect-main` ruleset, so **CI blocks a merge into `main`**. Its
  checks report a few seconds after a push and `gh pr merge` refuses until they do, with *"the base
  branch policy prohibits the merge"* — which reads like a permissions problem and is a timing
  one.
- **The workspace is declared but not live.** The root `package.json` names
  `pnpm@11.21.0` and `pnpm-workspace.yaml` carries a `catalog:`, but pnpm is not installed
  and `packages/server` still pins its own `typescript@^5.7.2` against the catalog's
  `^6.0.3`. **The root scripts do not run.** Use the per-stack commands below.

Work is tracked by the phase vocabulary in ARCHITECTURE.md §9 (`F0`…`F8`). There is no
ticket tracker. **The phases have not been walked in order, and F0 through F7 all have code on
disk**: F0 through F2 are done, F3's server answers eight of the nine contracted endpoints, F4's
rating measures a player against the difficulty classes other players have met, F5's map of topics
is computed from the pack, **F6's five puzzle formats are all playable**, and F7's profile, its
settings stack and its edge states are drawn. **F8 is the only one nothing has touched** — Rive is
named in ARCHITECTURE.md §9 and in `docs/IMPLEMENTATION-PLAN.md` and appears in no dependency and
no line of Dart.

## Commands

```sh
# Flutter — from app/
flutter analyze --fatal-infos
flutter test

# Tier 2, on a booted simulator. **`flutter test` does not reach
# `integration_test/`**, which is how three of these suites sat broken for
# weeks against copy that had changed under them. Run them when a screen or a
# flow moves. Seven suites, twelve cases: the playthrough, the shell's three
# roots, every board format opened from the home, the press travel measured in
# the shipping build, the two streak notices reached by seeding the day log,
# what the first run leaves on the device — the only suite that answers a probe
# item, since the shared launch skips `0.5` on purpose — and the account tour,
# which skips itself without endpoints.
#   xcrun simctl list devices booted        # take the id
#   flutter test integration_test -d <id>
#   # the account tour needs the endpoints, and skips itself without them:
#   flutter test integration_test -d <id> \
#     --dart-define=NEON_AUTH_BASE_URL=... --dart-define=AKIMATH_API_BASE_URL=...

# Running it on a simulator against a real backend. **Both steps matter.**
#   `--dart-define` is baked into `kernel_blob.bin` at build time, and a build
#   that reuses a cached kernel silently keeps the old values — so the app comes
#   up with `Endpoints.configured` false and the account row simply absent, with
#   nothing on screen to say why. And `simctl install` over an existing bundle
#   does not reliably replace `App.framework`, so uninstall first.
#   Verify rather than trust: the URL must appear in the *installed* blob.
#     rm -rf build/ios/iphonesimulator .dart_tool/flutter_build
#     flutter build ios --simulator --debug \
#       --dart-define=NEON_AUTH_BASE_URL=... --dart-define=AKIMATH_API_BASE_URL=...
#     xcrun simctl uninstall booted com.akimath.akimathApp
#     xcrun simctl install   booted build/ios/iphonesimulator/Runner.app
#     xcrun simctl launch    booted com.akimath.akimathApp
#   The uninstall takes `shared_preferences` with it, so every run of this
#   starts at `0.2 Bienvenida` again — the bottom bar lives on the home, which
#   is two taps past the first run.

# TypeScript — from packages/server/
npm run verify        # tsc --noEmit && vitest run
npm run mutation      # Stryker over src/, excluding main.ts, adapters/ and cli/
npm run dry           # jscpd duplication
npm run migrate       # apply migrations; needs MIGRATE_DATABASE_URL (the DIRECT string)
npm run schema:dump   # regenerate schema.sql; the tree must not move afterwards
npm run retention     # delete expired rows; needs RETENTION_DATABASE_URL

# A database to run the above against, local:
#   brew install postgresql@18 && brew services start postgresql@18
#   (18, because that is what Neon provisioned and CI mirrors production;
#    `pg_dump` output is byte-identical on 17 and 18, verified)
#   createdb akimath_dev
#   export TEST_DATABASE_URL=postgresql://localhost/akimath_dev

# TypeScript — from packages/core/
npm run verify        # tsc --noEmit && vitest run
npm run mutation      # Stryker over src/, excluding adapters/ and index.ts
npm run dry           # jscpd duplication (src/templates/** is excused — see its README)
npm run emit          # rewrite golden/; the tree must not move afterwards
npm run build:pack    # rebuild pack/starter.json from content/ and the authored asset

# TypeScript — from packages/contract/
npm run verify        # tsc --noEmit && vitest run
npm run mutation      # Stryker over src/, excluding adapters/
npm run dry           # jscpd duplication
npm run emit          # rewrite contract/; the tree must not move afterwards
```

`flutter analyze --fatal-infos` + `flutter test` + `npm run verify` **in all three TypeScript
packages** are the everyday gate, and
they are the *enforced* gate: `.claude/hooks/verify-gate.sh` runs them on every `git commit`
and `git push` and exits 2 (blocking) on a failure, and `.github/workflows/ci.yml` runs the
same commands — both spell the TypeScript half as `npm run typecheck` then `npm test`, which is
what `npm run verify` chains. Run `--fatal-infos` locally or the hook will surprise you.
Mutation and jscpd are the deeper pass (tier 1b below), run when the logic under change is
worth them.

One tool is installed and is **not a command here**: `dart run mutation_test` has no rules XML,
so it is green by construction and is not evidence. The Dart substitute for mutation is the
falsification step in the rulebook's PROC-5.

The metrics tool **is** configured now, and CI runs it:

```sh
# Flutter — from app/, and part of the `dart` CI job
dart run dart_code_linter:metrics analyze lib --set-exit-on-violation-level=warning
```

`--set-exit-on-violation-level` is not optional decoration. Measured: without it — and even with
`--fatal-warnings` — the command prints its warnings and exits **0**, which is the same
green-by-construction trap one level deeper. The thresholds in `analysis_options.yaml` are set at
what the code does today, so the next function past one is a decision somebody makes on purpose;
they ratchet down as the code gets simpler and never up to accommodate it.

## Workflow

TDD, clean code and clean architecture are requirements here, not preferences. Red → green →
refactor; the test is seen failing first. One small, logical commit per coherent change.

Planning runs on [OpenSpec](https://openspec.dev). A unit of work is a **change**, its id is the
change name, and its plan is committed to `openspec/changes/<change-id>/` rather than left in a
scratch directory — so the plan a reviewer reads later is the plan that was approved.

| Phase | One line | Owner |
|---|---|---|
| SPEC | `/opsx:explore` to think, `/opsx:propose` to write. Output is `proposal.md`, `design.md`, `tasks.md` and delta specs whose `#### Scenario:` blocks are the acceptance criteria. **Human approves the proposal before any code.** | main session |
| BUILD | Implement one task from `tasks.md`, test-first, against those scenarios. | `craftsman-engineer` |
| REVIEW | Conventions pass over the diff, citing rule IDs. | `craftsman-reviewer` |
| BUG HUNT | High-severity correctness only, each finding with a concrete trigger. | `craftsman-bug-hunter` |
| EVIDENCE | State the tier reached. | see below |
| LAND | Commit and push only when asked. | main session |
| ARCHIVE | `/opsx:archive`, only after the pull request has merged. | main session |

There is no DEPLOY phase: there is nothing to deploy to.

`/opsx:propose` will not touch project code — the approval gate is enforced by the tool, not by an
agent's restraint. Read the plan back with `openspec show "<change-id>"` and check the gate with
`openspec status --change "<change-id>" --json`; both read disk, which is the point. Project-wide
conventions reach every proposal through `openspec/config.yaml`, so edit that file rather than
repeating the rules in each one.

**Evidence tiers.** Three names, used identically in this file, in the rulebook and in every
agent — if you find a fourth numbering somewhere, that file is wrong.

- **Tier 1 — the committed suite.** The everyday-gate commands above, with the numbers stated.
- **Tier 1b — show the tests bite.** `npm run mutation` (Stryker) and `npm run dry` on the TS
  side; on the Dart side, with no mutation harness configured, a falsification step (see the
  rulebook's PROC-5 for the mechanism, which is not optional — it edits versioned code).
- **Tier 2 — exercise the real thing.** The app run on a device or simulator when the change
  surfaces visually, or the endpoint called for real once endpoints and an environment exist.

"It compiles" and "it should work" are not evidence. Skipping a tier silently is a violation;
asking to skip one is not.

Detail lives in `.claude/agents/`. The rulebook the reviewer cites is
`.claude/conventions/craftsmanship.md` — **this file wins if the two ever conflict**, and the
rulebook gets corrected.

## Architecture rule

**Pure policy separated from IO.** Policy is a function of its inputs with no Canvas, no
socket, no clock and no environment, so it is testable without mocks; the adapter next to it
does the touching. Both precedents are already on disk: `app/lib/design/brand/spec/` versus
the painter beside it, and `packages/server/src/routing.ts` versus
`packages/server/src/adapters/`. New logic follows the same split. On the Dart side the split
is now a red build rather than a precedent: `app/test/architecture/pure_boundary_test.dart`
walks the import graph transitively — through `export` and `part`, so the tokens barrel cannot
smuggle `package:flutter/painting.dart` into a pure root — and reports a per-root file count so
a mistyped root cannot make it vacuously green. Today that bites over `design/**/spec/` and its
22 files, `features/*/policy/` and its 47, and `content/model/` and its 9 — all three roots are on
disk now, and the last two flipped from absent to covered when the round landed. **Import the token
you need, not the barrel:** `tokens.dart` re-exports `brand_typography.dart`, which imports
`package:flutter/painting.dart`, so a pure module reaching for the barrel fails the gate. The root is a **glob, not a list**, so
`design/math/spec/` was covered the moment it existed and no one had to declare it — the next spec
root is free the same way.

## Invariants — do not break without discussing it

**Enforced by a test:**
- Coral (`#FF8A5B`) is error and nothing else; green (`#5ED6A4`) is action and success and
  nothing else; pink is never `error`, `success` or `action` — it is the accent, and
  `BrandColorRole.focus` is an input affordance, not a verdict.
  (`test/design/tokens/brand_colors_test.dart`)
- No blurred shadow, no gradient, no Material elevation. Shadows are hard, blur is always
  zero. (`test/design/no_blurred_shadow_test.dart` walks every screen and asserts exactly
  four things: no gradient, `blurRadius == 0`, `spreadRadius == 0`, and elevation 0 on
  `PhysicalModel` and `PhysicalShape` — add new screens to
  `app/test/design/screen_registry.dart`, which both this gate and `screen_overflow_test.dart`
  read.)
- Every registered screen fits 390x844 at `textScaler` 1.0 and 1.3.
  (`test/design/screen_overflow_test.dart`; the screen list is `test/design/screen_registry.dart`,
  and a viewport can only be excused by an `excused` entry quoting the overflow message that
  earned it.)
- No colour literal outside `app/lib/design/tokens/`, and no `Offset(` literal on a widget
  surface. (`test/architecture/no_color_literal_test.dart` scans all of `app/lib/` except
  `design/tokens/` for `Color(0x`, `Color.fromARGB(`, `Color.fromRGBO(` and `Colors.` — the last
  on a word boundary, since `Colors.` is a substring of `BrandColors.`; `Colors.transparent` is
  the one carve-out. `test/architecture/no_geometry_literal_test.dart` scans `design/widgets/`,
  `design/math/`, `design/painting/`, `design/puzzle/` and `features/` for `Offset(`;
  `design/brand/` is out of scope as the artwork layer, `design/puzzle/spec/` is excluded because
  a board's geometry *is* offsets, and radii and border widths are not scanned at all. Both report
  how many files they scanned and fail at zero.)

- **Nothing you can press is under 48 px**, measured on the rendered screen
  rather than asserted about a widget — a `SizedBox(48)` in a `Row` that ran out of room is 31 px
  wide and the constant says nothing about that. `test/design/touch_target_test.dart` walks every
  registered screen at both viewports and reports the count it swept (today 85 screens, 425
  presses); a screen with nothing to press is legitimate and named in the summary rather than
  failed.

- **Nothing watches you while you work.** `test/design/quiet_while_you_solve_test.dart` walks
  every solving surface — the item in all six families, `0.3 Primer reto`, `0.5 Calibración
  reactivo` and every board, kenken's reference sheet and its pause among them because both are
  drawn mid-solve, 16 registered screens today — and asserts Aki is on none of them and nothing on
  them reads as a clock. `puzzle · solved` is not one of the 16: the solving is over there, which
  is exactly when she is allowed. Both
  halves have their opposite asserted too: she *is* on the verdict screens, in `slip` for a wrong
  answer and `correct` for a right one, and the verdict screen *may* say how long it took. A rule
  that only ever said "absent" would be satisfied by deleting her.

- **A verdict is never drawn by hue alone.** Deuteranopia collapses `#5ED6A4` and `#FF8A5B`, so
  `Verdict` carries an outline and a glyph and **no colour at all** — a call site has to reach for
  a shape because that is all there is, which is the same construction as the sync endpoint
  refusing an `ok` field. What the type cannot prevent is a *second* reach: nothing stops a screen
  pairing `Verdict.correct` with `BrandColorRole.success.color`.
  `test/architecture/verdict_is_not_a_colour_test.dart` scans all 216 files of `lib/` for a file
  naming both, and excuses exactly one — `verdict_ring.dart`, which also draws the ring. It strips
  prose first, because the names it reads for appear in explanations of the rule as often as in
  code.

*(There is nothing left under "encoded as a constant, not yet enforced". Both entries that
lived here — the 48 px floor and the hue-only verdict — now have gates, and the heading comes
back the day something else is written down without one.)*

**Design intent, no code yet to enforce it:**
- Aki has exactly one body part that can be lost and come back: **the curl of her tail** — drawn,
  and `AkiPose.slip` is on the error screen, but nothing checks that the tail is the *only* thing
  that moves. She does not scold and does not look disappointed, which is copy and drawing rather
  than something a predicate can read.

**System invariants for the parts not yet built** (verbatim from ARCHITECTURE.md §4–§5):
- *The prompt travels rendered. The answer never travels online. Offline, a membership
  verifier travels and its verdict is provisional until sync.*
- *`attempts` never accepts UPDATE. It accepts DELETE only through the erasure path
  (`DELETE /v1/me`) and the retention job, both under the `retention_job` role. The request
  path holds no DELETE grant on `attempts`.*
- Rating never runs in Dart. Offline difficulty is fixed by the pack's `ladder_step`.

## Never

- Never add a dependency that collects data, serves ads, or reports analytics.
- Never use `BackdropFilter`. Nothing in `app/lib/` uses one today and no test asserts its
  absence, so this is intent the reviewer enforces by reading, not a red build.
- Never write a color literal outside `app/lib/design/tokens/` — every hue comes from
  `BrandColors`, and state comes from `BrandColorRole`. (`Colors.transparent`, used to switch
  Material's tinting off, is the one exception on disk.)
- Never use a LaTeX library to render math, or the system keyboard for numeric entry.
- Never hand-write authentication crypto — that is Neon Auth's job, and Neon Auth is
  managed Better Auth. It is also why an unlinked device does not sync: it has no
  credential the server could verify, and inventing one is exactly this rule. (HMAC message
  construction for offline verification is ours, and is a cross-stack contract.)
- Never generate puzzles on demand; they go in batches.

## Git

Commit email is `geineryodan@gmail.com` — verify `git config user.email` before committing.

**`main` is the trunk, and `dev` is not the working branch any more.** `dev` stopped at pull
request #6 on 2026-08-17 and everything since — #7 onward — has been merged into `main`, so
`main` is 183 commits ahead, `origin/dev` holds nothing `main` does not, and 881 files differ
between them. **Branch off `main` and diff against `main`**: a review taken against `origin/dev`
is those 183 commits of noise rather than the change. `main` itself is protected by the
`protect-main` ruleset: no direct push, no force-push, no deletion — it is reached through a
pull request from a branch, which is how every change since #6 has landed. Nothing is committed or
pushed unless you were asked to.

**A branch is named after the change it carries**, and where OpenSpec has a change the branch name
*is* its id — `f3-router` is a branch and a change directory with the same name. The id is
`<token>-<kebab-summary>`, the token being the phase (`f0`…`f8`) when the work belongs to one and a
conventional type (`fix`, `docs`, `chore`, `test`, `refactor`, `ci`, `feat`) when it does not.
Lowercase, hyphens, **English** — a change id is an identifier, so LANG-1 governs it, and the three
Spanish ids in the archive are the reason that is spelled out. No date, no author, no ticket id, and
no `spec-` in front of an id that already has a token. GIT-5 in the rulebook.

**A pull request is squashed, so its title is the commit subject on `main`** — it takes the same
conventional prefix as any other subject, lowercase, no ticket id, no scope in parentheses
(`fix: the commit gate scopes itself against the trunk that exists`). That was not being applied:
of the twelve subjects before the rule landed, ten had no prefix and the two that did carried the
parentheses the rulebook bans. The body follows `.github/PULL_REQUEST_TEMPLATE.md`, which GitHub
fills the box with automatically — what lands, why, **the evidence tier with its numbers**, what
the change deliberately does not do, and what has to happen after it merges. Delete a section with
nothing true to say; an empty heading reads as covered. Both halves are GIT-4 in the rulebook.

## Decided

**The game is for adults, and the age gate refuses instead of routing** —
`docs/adr/0004-the-game-is-for-adults.md`, decided 2026-08-29, amending `ARCHITECTURE.md` §1's
audience clarification of 2026-08-17. The opening of this file states what it changed. Its
amendment of the same day answers two of its four open questions — the refusal happens at **link
time** (Reading A), and DEP-1 keeps its **category** refusal on three re-grounded supports — plus
the sequencing note: the `age_band` `CHECK` is **left as it is**, no migration and no contract
change, because the two minor bands go dead by construction. **Two questions are still open and
should not be counted as answered**: what an under-18 actually sees, which is a design request now
on the critical path, and whether a refusal should be recorded anywhere at all. The app-store age
rating is a third, is in `docs/decisions/OPEN.md`, and is being researched separately.

**Auth is Neon Auth, and nothing syncs until an account exists** —
`docs/adr/0002-neon-auth-and-no-sync-until-linked.md`, decided 2026-08-19. Neon Auth is managed
Better Auth with identity in a `neon_auth` schema in our own Postgres and a REST API, so the app
needs no SDK. It exposes **no anonymous plugin** and **no IP-tracking control**, and every
session row carries `ipAddress` and `userAgent` — so a minor's device never gets a session at
all. `player_id` is minted on the device, unlinked play is entirely offline, and linking is an
adult's act and the first server contact. **0002 is not superseded by 0004** and its scope widened
rather than narrowed: the structure kept sessions away from under-13s who were being routed, and
now keeps them away from every minor who is being refused. **An account is made with an email and a password**
(open sign-up, verification required) — decided 2026-08-19, because the alternative was Google on
Neon's shared consent screen plus two new Flutter dependencies to run a browser redirect.

GHSA-qq9h-g4jm-xgf3 is still closed, by a **narrower and load-bearing** condition: the managed
version is 1.4.18 and cannot be patched by us, so what shuts the advisory is that the
**magic-link and email-OTP plugins are off**. It needs a passwordless sign-in path to collide with
a password registration at the same address, and there is none. **Turning magic-link on reopens
it** — that is one toggle in a console, so it is an invariant, not a preference. It stops mattering
the day the managed version passes 1.6.22. ADR 0002's amendment carries the four conditions and
the queries that verify them.

**The Dart API client is hand-written** — `docs/adr/0001-dart-api-client.md`, decided
2026-08-16 by the F0 spike `f0-dart-client-spike`. `swagger_dart_code_generator` is rejected:
its output fails `flutter analyze --fatal-infos` (3 `unused_import` warnings, under files that
open with `// ignore_for_file: type=lint` and so opt themselves out of the lint set), collapses
optional and nullable into one Dart shape and serializes an absent optional as `null`, silently
absorbs unknown enum values via a synthetic `swaggerGeneratedUnknown`, silently defaults a
missing **required** array to empty, and costs 14 net-new runtime packages against a floor of
zero. It won one rubric row of six — its output is byte-identical across cold runs — which is
not enough under §2's asymmetric criterion.

`app/lib/api/` is therefore hand-written, is an **F3** directory, and is a PURE-2 adapter that
holds no decisions. No `build_runner`, and no CI byte-diff job.

**That threshold fired, and `docs/adr/0003-the-dart-client-crossed-its-threshold.md` answered it —
0001 is superseded and its decision reaffirmed** (2026-08-28). Two of the four conditions were met:
the client passed 600 lines (**1944 raw / 1236 code** across ten files) and the envelope machinery
passed the endpoints (**508 : 245**). Neither is a reason to switch, and that is the point 0003
makes: **three of the four triggers measured size, and size is the one rubric row of six that
hand-writing already won** — 0001 rejected the generator on correctness and dependency surface, and
`swagger_dart_code_generator` is *still 4.1.1*, published 2025-12-11, with all four defects present
in the current source. The optional-versus-nullable collapse reads worse than 0001 recorded:
`include_if_null` is one **document-wide** switch, so the distinction has nowhere to live.
Factoring the error envelope — the audit's cheapest move — does **not** move either trigger back:
the envelope's floor is the seven result unions, 257 lines no de-duplication touches, against 245
endpoint lines. **The endpoint count means operations in `contract/openapi.json`** — 8 of 9
modelled, 7 called — because a generator can only act on a document that exists and none describes
the Neon Auth half. All four conditions are retired and replaced by three that bear on the answer:
polymorphism entering the contract, a generator that clears the four correctness objections, or a
second consumer needing the same models. **Line count is no longer a supersede condition.**
