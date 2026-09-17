# AkiMath — Clean Code & Project Conventions

The reviewable rulebook for this repository. Every rule has a stable ID so a review can cite it
against a diff (`PURE-1`, `CMT-1`, …). One repo, two languages: rules apply to Dart under `app/`
and to TypeScript under `packages/` unless the rule says otherwise.

This book starts small on purpose. Forty-one rule IDs — counting `FUN-1a` and `CMT-2a` as the
carve-out and the special case they are rather than as rules — every one of them describing code
that is already on disk today, not a pattern we hope to have. It grows by **PROC-6** and no
other way.

**The count is maintained by hand and had drifted to thirty-two**, three behind, which is the
same shape as a gate that cannot fail: a number nobody checks. It is checkable in one line —
`grep -cE '^- \*\*[A-Z]+-[0-9]+[a-z]?\*\* ' .claude/conventions/craftsmanship.md` — and whoever
adds a rule under PROC-6 runs it rather than incrementing what is written.

`CLAUDE.md` at the repo root is the entry point for *how to work here*; this file is the *contract
the code must satisfy*. Where both cover the same ground this file is the detailed version — and if
they ever conflict, **CLAUDE.md wins and this file must be corrected in the same session** (PROC-6).
`ARCHITECTURE.md` holds the design decisions the rules point at.

Legend: **MUST** = a violation blocks the merge · **SHOULD** = raise it, the author decides ·
**NEVER** = hard prohibition.

---

## PURE — Pure policy, separated from the IO adapter

The one structural pattern the repo already commits to, on both sides of the stack:
`app/lib/design/brand/spec/` vs `app/lib/design/brand/brand_drawing_painter.dart`, and
`packages/server/src/routing.ts` vs `packages/server/src/adapters/http-server.ts`.

- **PURE-1** MUST: every decision — routing, grading, layout geometry, rating, canonicalization,
  what a drawing *is* — lives in a module that performs no IO: no `Canvas`, no `CustomPainter`, no
  widget, no `package:flutter/rendering.dart` or `/material.dart`, no socket, no filesystem, no
  `process.env`, no clock and no randomness. Value types that carry no IO are fine — outside its own
  pure siblings, `app/lib/design/brand/spec/` imports only `dart:ui show Offset, Radius, Rect, Color`
  and `package:meta`, and `routing.ts` imports only `./health.js`. The test
  that decides it: **if proving the decision correct requires faking a canvas, a socket, a clock or
  a seed, the decision is on the wrong side of the boundary.** `app/test/design/brand/aki_spec_test.dart`
  and `packages/server/test/routing.test.ts` both run with zero mocks; that is the bar.

- **PURE-2** MUST: the adapter that performs the IO holds no decisions — it translates and nothing
  else, and stays thin enough that nothing worth testing lives in it.

  ```dart
  // wrong — the adapter now owns a coordinate, so the artwork lives in two places
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(const Offset(68, 96), 16, _inkPaint());  // Aki's left eye
  }

  // right — the adapter walks the spec and knows no geometry of its own
  for (final BrandMark mark in drawing.marks) {
    switch (mark) { case InkDot(): _paintDot(canvas, mark); /* … */ }
  }
  ```

  Same shape on the server: `http-server.ts` owns the socket and knows no route; `routing.ts` owns
  every route and opens no socket.

## FUN — Functions

- **FUN-1** MUST: at most three **positional** parameters on a function or method; past three, use
  Dart named parameters or a TypeScript options object, so every argument is readable at the call
  site. `AkiSpec._face` takes eleven named parameters and complies — the rule is about unreadable
  call sites, not about arity.
  **Carve-out (FUN-1a):** a small private value type may take its fields positionally
  (`_Mouth` in `aki_spec.dart`) when a named constructor would be pure noise; a *function* may not.

- **FUN-2** NEVER take a boolean parameter that selects between two behaviors — a boolean means the
  function does two things. Use a closed enum, or write one function per alternative.

  ```dart
  // wrong
  const SplashScreen({this.onGreen = false});

  // right — the variants are named, and a third one is a compile error away from being handled
  enum SplashVariant { cream, brandGreen }
  const SplashScreen({this.variant = SplashVariant.cream});
  ```

## TYP — Types

- **TYP-1** MUST: in Dart, annotate every declaration explicitly and type every collection literal —
  `final Rect box`, `final double scale`, `<BrandMark>[...]`, not `var` and not a bare `[]`. Nothing
  enforces this: `flutter_lints` does not enable `always_specify_types`, so it is a review rule, and
  the whole `app/lib/` tree already reads this way. On the TypeScript side `strict` and
  `verbatimModuleSyntax` are on in `packages/server/tsconfig.json`, so implicit `any` and a missing
  `import type` are compiler errors already — what the reviewer still checks there is an explicit
  return type on every exported function and `unknown` rather than `any` when a payload is genuinely
  untyped.

- **TYP-2** MUST: **a value type's invariant is a constructor shape, never an `assert` — wherever
  the illegal state is a combination of fields a constructor can refuse.** Dart
  strips asserts in release, so a guarantee written that way holds in every test and in no build a
  player runs — and the tests are then evidence *for the mechanism that is absent*, which is worse
  than no guarantee at all, because the type's doc comment goes on advertising it. Where two
  fields must not both be set, or both be null, make the illegal state unconstructible: the
  generative constructor goes private and one named constructor per legal combination sets the
  other fields itself. Dart privacy is library-scoped, so a private constructor in a
  single-file library is a compile error at every call site outside it.

  Measured in `fix-a-batch-cannot-name-two-sources`, on `app/lib/api/sync.dart`.
  `AttemptSubmission` refused to name neither source or both with
  `assert((itemId == null) != (packRef == null))` under a doc comment reading *"the constructor
  refuses to build either"*, and the whole failure path was wired: both or neither is a 400, the
  client reads a 400 as `SyncMalformed`, and `journalAfter` reads that as a batch there is no point
  resending — up to two hundred answers deleted with nothing on screen and nothing in a log. It is
  now `AttemptSubmission.forPackItem` and `AttemptSubmission.forIssuedItem` over a private
  `AttemptSubmission._`, and naming both no longer compiles.

  **Two consequences for how such a change is tested.** The runtime test that used to
  `expect(…, throwsA(isA<AssertionError>()))` must be *replaced* rather than deleted — assert each
  door leaves exactly one source on the object and on the wire — because an invariant that loses
  its last test on the way to becoming a compile error is a PROC-11 regression even though the type
  got stronger. And PROC-5's tier-1b falsification for it is a **build failure, not a red case**:
  write the illegal call, record the compiler's own words and the nonzero exit status, and say in
  the ledger that no test name is being quoted because there is none to quote.

  **Where the invariant cannot be a constructor *shape*, ask whether it can be a constructor
  *effect* before settling for an assert.** This paragraph said the opposite until 2026-09-02, and
  the code it blessed shipped the defect. `elapsed`'s bound in that same class is the example: an
  out-of-range `Duration` is representable whatever the constructor does, so no combination of
  fields can be refused — from which this rule concluded *still an assert*, and never reached the
  option that was there all along. A constructor cannot make the value unwritable; it can make it
  unobservable. `AttemptSubmission._` now normalises through `reportableTimeOnTask`, which
  `flutter build --release` keeps.

  What the assert cost is the measure of the mistake. It guarded only the negative half, and the
  half it did not guard was the reachable one: `round_screen.dart` measures an item on the wall
  clock and nothing pauses it when the app is backgrounded, so a phone in a pocket for an
  afternoon sends an `elapsedMs` past the frozen `maximum` of 3_600_000, the server refuses the
  whole body with a 400, and `journalAfter` reads a 400 as a batch there is no point resending —
  up to two hundred answered items deleted by an unpaused timer, with nothing on screen and
  nothing in a log. Measured in `fix-a-long-item-cannot-drop-a-batch`.

  Two things that generalise from it. **Normalise rather than throw when the value can arrive from
  storage**: a refusing constructor would have wedged every later flush on one row already on a
  player's disk, and the reachable-row case is also why the clamp belongs at the wire and not at
  the point of measurement — a record-time clamp cannot reach what an older build already wrote.
  And **the bound and its reason live in one pure module the contract's parity test can read**
  (`app/lib/api/time_on_task.dart` against `contract/openapi.json`), never as a literal inside the
  constructor, so the re-derivation cannot drift from the document.

  A file holding both kinds of guarantee and distinguishing neither is a CMT-2 defect waiting for
  its next reader.

## NAM — Naming

- **NAM-1** MUST: identifiers are self-descriptive without their surrounding context, and carry no
  data-type prefix (`strCode`, `blnOk`, `arrMarks`) — the type annotation already says that. Name by
  role. Length scales inversely with scope: a public entry point is short and abstract (`route`,
  `body(pose)`), a private one-job function is long and precise (`_buildFace`, `_paintStroke`,
  `buildHealthReport`). If a comment is needed to say what a function does, rename the function.

## CMT — Comments & documentation

- **CMT-1** MUST: **no comment inside a function body.** Extract the code it would explain into a
  function whose name says what the comment would have said. The non-obvious **why** goes on the
  symbol's doc comment — `///` in Dart, `/** */` in TypeScript — and longer rationale belongs in the
  plan, `ARCHITECTURE.md`, or an ADR under `docs/adr/`.

  **Amended 2026-09-16, and the escape hatch it closes was the whole rule.** This clause used to
  allow a body comment that survived the extraction test, capped at three lines. The cap is gone
  and the allowance with it: a body comment has no home now, because the reason a body comment
  exists is almost always that a function is doing two things and one of them has no name.

  The argument is not Martin's *"every comment is a failure"* — this book does not hold that, and
  `clean-coder` still carries Ousterhout's rebuttal for the doc comment. The argument is this
  section's own history. **CMT-2, CMT-2a, CMT-3, CMT-4 and CMT-5 are five rules and every one of
  them was written after a comment lied** — the first-run flag that claimed answering was the only
  path, the *"first run does not record"* sentence that went stale when the first run grew four
  screens, the gate that did not exist, the three `storedAnswer` implementations behind a comment
  saying there was one, and the kill switch one reader bypassed. Five incidents, one failure mode.
  A sentence inside a body is the least visible, least reviewed and least greppable place that
  failure can happen, and deleting the surface is cheaper than five more rules policing it.

  **What this does not license.** A doc comment is still where rationale lives, and CMT-2 through
  CMT-5 now bear on it entirely — they got narrower in scope and heavier in weight. Deleting a body
  comment that carried a *decision* without moving that decision somewhere a reader will find it is
  not compliance with this rule; it is the loss the rule is trying to avoid. Move it to the symbol,
  or to `docs/`, or make it a gate (PROC-10). The comments that go without ceremony are the ones
  that restate the line beneath them.

  **Tool directives are not comments for this purpose.** `// ignore: avoid_print`,
  `// eslint-disable-next-line`, `@ts-expect-error` and their kind are instructions to a tool that
  happen to use comment syntax; they stay, and the rule they suppress is the thing to argue with.

- **CMT-2** MUST: **a comment that states behaviour the code does not have is a defect**, and it is
  fixed with the code in the same commit — a comment is not a softer artifact than the code above
  which it sits. CMT-1 governs whether a comment should exist and what it may say; this one governs
  whether it is true. Found in `f2-onboarding-first-run`, where three doc comments claimed the
  first-run flag was *"set by answering, not by escaping"* and that answering was *"the only path
  that completes the first run"*, while the skip control one row below the close control completed it
  with nothing solved; and where `FirstItemScreen` said *"it measures nothing"* above a screen whose
  verdict displayed `RACHA 1`. A reviewer reading a comment believes it, which is exactly why a false
  one is worse than none: it retires the question.

- **CMT-2a** MUST: **scope a claim to the thing it is true of, and name that thing — a claim
  scoped to a container goes stale when the container grows.** CMT-2's subtler half, and the
  difference matters because the ordinary remedy does not apply: these comments are not
  describing code they sit above, and they were **exact on the day they were written**. Nobody
  edited them and nobody edited the code under them; the *subject widened* under a sentence that
  named it by its shape at the time, and a comment cannot notice that.

  Two, found together in `fix-the-calibration-counts-where-it-should`, both load-bearing:

  - `app/lib/features/stats/data/answer_record_store.dart` opened *"The first run does not
    record"*. True on 2026-08-20, when the first run was `0.2` and `0.3`. `0.4`–`0.7` landed on
    **2026-08-21**, and the sentence went on asserting a rule about four screens it had never
    been written about — which is how the calibration probe came to grade ten real pack items and
    record none of them, with the one question a reviewer would ask already answered in prose.
    The rule it *meant* is *the teaching item does not record*, and that names the thing.
  - `app/lib/features/home/ui/home_route.dart` said the route was *"the only place that can
    keep"* that rule. Exact when written, false as soon as `MapRoute` recorded, and false twice
    over afterwards. That is also CMT-4, and the two rules meet here: a claim about callers
    scoped to *"this route"* is a container claim about a set that only ever grows.

  `docs/solid/shell-and-entry.md`'s finding 6 lists three more of the same shape —
  *"today only the in-memory side of it exists"*, *"`AppBottomNav` arrives with the second root
  at F5"*, *"the shell has always accepted and never been given"* — each a sentence about the
  state of a growing thing rather than about a fact.

  **The test:** if a sentence would be falsified by *adding* a screen, a caller, a file or a
  phase — rather than by editing the code it describes — rewrite it to name what it is true of.
  Where a count is the point, make it a gate that counts rather than a sentence that states
  (PROC-10). And when you widen a container, grep the words that name one: *"the first run"*,
  *"the only"*, *"today"*, *"not yet"*, *"arrives with"*.

- **CMT-3** MUST: **a comment that claims a test or a gate exists is a claim to `grep` for, and it
  is checked the moment it is read.** This is CMT-2's nastiest special case, because it does not
  merely mislead — it retires the very question that would have found the gap, and it leaves an
  invariant advertised as guarded while nothing guards it. Found in `req-me-standing`:
  `packages/server/src/adapters/http-server.ts` said its missing-handler branch was *"unreachable
  while the test holding `IMPLEMENTED_OPERATIONS` to these keys passes"*, and **no such test had
  ever been written** — so `route()` could dispatch to a name with no handler behind it, a 500 that
  only production would find. Two obligations follow. When you **write** such a comment, name the
  file (`test/every-built-operation-has-a-handler.test.ts`), never the claim in the abstract, so the
  assertion is one `ls` from being falsified. When you **read** one while working nearby, grep for
  it before relying on it; if it is not there, the missing gate is part of the change that needed
  it, because the next author will believe the comment too.

- **CMT-4** MUST: **a comment that claims who the callers of a shared decision are is a claim to
  `grep` for, and the durable form of it is a gate rather than a sentence.** CMT-3's sibling: that
  one is about a comment claiming a *test*, this one about a comment claiming a *property of code
  in other files* — "anything that does X calls this", "the only two producers are". Both retire
  the question that would have found the gap, and this one does it across a package boundary,
  where nobody is reading.

  Found in `fix-one-storedanswer-not-three`, on the highest-consequence rule in the repository.
  `packages/contract`'s `storedAnswer` exists to hold one decision — how an exact answer is written
  down, shape and spelling together — and closed with *"anything that turns a `(numerator,
  denominator)` into a stored answer calls this — the builder, and the server when it issues a
  pack — so the two cannot disagree again."* There were **three** implementations. Two did not call
  it: `packages/core/src/pack/lift.ts` decided the shape from a `/` in the raw field, and
  `packages/server/src/attempts.ts` wrote the `denominator === 1n` branch out longhand. The named
  second caller — the server *issuing* a pack — copies a pre-built artifact and derives no answer,
  so it did not exist. Three more comments repeated it, including one in a test.

  That is bug #50's exact shape, and #50 is *why* the function was moved into the contract: it
  shipped a whole answer of −9 digested as `-9/1` beside a field saying `integer`, made every
  generated item in the built pack ungradeable, disabled the distractor-equals-answer guard in the
  same stroke, and turned no suite red. The comments are what stopped anyone finding the copies,
  because they said there was nothing to look for.

  Two obligations, the same shape as CMT-3's. When you **write** such a claim, name the gate file
  that holds it (`test/one-way-to-spell-an-answer.test.ts`) rather than asserting the property in
  prose, so it is one `ls` from being falsified — and if no gate exists, writing one is part of the
  change that needed the claim. When you **read** one while working nearby, grep for the callers
  before believing it. The repository already had the idiom for the gate — `one-way-to-log.test.ts`
  and `one-way-to-erase.test.ts` — and nobody had pointed it at a decision that spans packages.

  **A corollary worth its own line: a claim about callers needs one gate per package that could
  grow one.** A package cannot scan a sibling it does not depend on, and each suite has to be able
  to go red on its own regression.

- **CMT-5** MUST: **a comment that claims a switch turns something off is a claim to check every
  reader against, and a kill switch with one reader that bypasses it is not a switch.** The third
  sibling of CMT-3 and CMT-4: those are a comment claiming a *test* and a comment claiming a
  *caller set*; this is a comment claiming a *control*. It fails worse than either, because the
  claim invites an action — somebody flips the flag, believes the thing is off, and ships.

  Found in `fix-only-what-the-product-can-prove`. `app/lib/demo/demo_figures.dart` held every
  figure the product could not compute behind `DemoFigures.enabled`, whose doc comment read *"a
  build that flips this to false shows only what the product can prove, which is what shipping
  looks like."* Of the four readers, **three** sat behind `if (DemoFigures.enabled)` and the
  fourth — `series_summary_screen.dart`'s `_ratingTile()` — was called unconditionally from
  `_tiles()`. Flipping the switch would have removed `QUÉ MEJORÓ` and `QUÉ SIGUE` and left
  `+ 12 RATING` on the screen, which is the single figure the recorded decision most forbids:
  `CLAUDE.md` keeps a rating off the verdict screens *"so nothing on them is a figure sync could
  later contradict"*. It shipped that way against the live API on 2026-09-02, printing an identical
  `+ 12` for two structurally different series.

  Three obligations. When you **write** a switch, its doc comment names the gate that holds every
  reader to it, not the intention — one `ls` from being falsified, the same close CMT-3 and CMT-4
  ask for. When you **read** one, grep its readers before believing it; the count is cheap and the
  belief is not. And when the switch's only job is to hide something unfinished, prefer **deleting
  the thing** to switching it off: a `false` constant leaves the render paths, the values and their
  doc comments in the tree, one flip from returning, and `CLAUDE.md` already makes that argument
  about the pack generator it removed — *code nothing calls is a claim about the product that is
  not true*.

  **The durable form is a rendered gate, not a source scan.** What the switch was standing in for
  here is now `app/test/design/only_what_it_can_prove_test.dart`, which pumps every registered
  screen and fails on a figure nothing produces. A scan for the constant would have been green
  with `_ratingTile` exactly as it was, because the bypassing reader *did* name the file it
  bypassed the switch of.

## WIRE — What crosses between the stacks

- **WIRE-1** NEVER branch on a server's human-readable `message`. The frozen `Error` shape is
  `{error, message}`: `error` is the tag a client may switch on and `message` is prose for a
  developer reading a log. A client that reads the sentence has coupled its behaviour to copy, so a
  reword on the server silently changes what a player is told — a defect that passes every test on
  both sides. Found in `f7-conflicto-de-cuenta`: `linkOutcome` refuses a link for **two** distinct
  reasons and `conflictResponse` sends both as `already_linked`, with the difference surviving only
  in English prose the client already held and was discarding.

  When two outcomes genuinely have to be told apart, in order of preference: **derive it from
  another contracted operation** if one answers the same question — the `GET /me` probe there is
  *exact* rather than heuristic, because the server checks `playerForAccount` before
  `accountForPlayer` and `GET /me` is `playerForAccount` — or **add a distinct `error` tag**, which
  is cheaper than it looks and is measured rather than assumed: `ErrorSchema.error` is
  `z.string()`, not an enum, so a new tag changes no schema, leaves `contract/openapi.json`
  byte-identical, and needs no `allow-breaking-contract` label. What is never acceptable is a
  client that says *"the message contains …"*.

  **The state that claims the least is a real state**, not a placeholder. Where the direction
  cannot be established, say only what the status code said; falling through to either specific
  answer is inventing one, which is the failure being fixed rather than a smaller version of it.

## LANG — Language

- **LANG-1** MUST: code, identifiers, file names, comments, doc comments, test names, commit
  messages and documentation are in **English**. Only strings the player reads are in **Mexican
  Spanish**, and they read as a person talking, not as a system reporting
  (`'Se me desenroscó la cola. Ya vuelve.'`). **Not a register for children** — the warmth in that
  example is Aki's voice, not the reader's age, and this clause said *"to a child"* until
  2026-08-29 even though the product had stopped being child-directed on 2026-08-17 and stopped
  admitting children at all on 2026-08-29 (ADR 0004). There is no i18n layer yet, so player-facing Spanish
  sits inline in the widget that shows it; when a layer arrives this rule gains a clause under
  PROC-6. **A verbatim quotation of a Spanish design document, or of player-facing copy, may stand
  inside an English comment** provided the rationale around it is in English — `banner_visual.dart`'s
  *"Sin conexión no es un error del usuario: va en amarillo"* is the reason a decision was taken, and
  paraphrasing a source into English loses the ability to check it against the source. Quoting is not
  writing the comment in Spanish.

- **LANG-2** MUST: **player-facing copy that asserts a fact is checkable against the policy that
  produces it, and a caption no input can make true is a defect.** CMT-2 says a comment stating
  behaviour the code does not have is a defect and is fixed with the code; this is the same rule
  one audience further out, and it is the more serious half — a false comment misleads the next
  author, a false caption misleads a player, who has no `grep`. Found in
  `req-streak-lost-caption`: `4.13 Racha perdida` captioned its left counter **`AYER`**, and
  `StreakState.broken` requires `streakLength` to return 0, which requires the day log to hold
  neither today *nor yesterday* — so the run that screen reports on always ended two or more days
  ago and the caption was false on **every reachable input**, not on an edge case. On the test
  simulator it labelled 2026-08-21 as *yesterday* on 2026-08-26.

  Two obligations. **The test asserts the claim, not the string** — see PROC-11's sixth bullet,
  which is this incident from the testing side. **And the design does not settle it**: the
  archived plan records the design as drawing `AYER 13 → HOY 1`, so the drawn screen and the state
  machine disagreed and *the state machine was right*. Where a design document asserts a fact the
  policy contradicts, the policy wins, the departure is written down at the call site with its
  reason, and the design is reported back — a screen is not permitted to say a false thing because
  a document said it first. This is the same reading as *"say the true half rather than approximate
  the whole"*, which `openspec/specs/states/spec.md` already applies to the rating on that very
  screen.

## TEST — Tests are code

- **TEST-1** MUST: **a test is production code.** It is named, reviewed, refactored and held to the
  rules in this file like anything else, and it is the deliverable rather than the receipt — PROC-1
  already says a behaviour change with no test in its commit is incomplete. What TEST-1 adds is the
  other direction: **a test that cannot fail is a defect of the first order here**, because in this
  project the suite *is* the evidence, and a green suite that proves nothing is worse than no suite,
  which at least does not lie. This is not theoretical. Found in one week: a reviewer diffing against
  a branch abandoned at pull request #6; `dart_code_linter` exiting 0 without its flag; a CI guard
  whose command failed on an unknown option before it read the file it guarded; `packages/contract`
  with no dependency allowlist at all; `expect(solved, 0)` that was `expect(0, 0)`, in a case named
  *"a key pressed while it is open does nothing"* that never pressed a key; the *"the answer never
  travels"* test pinned on a code path with no production callers; and a first-run branch that no
  integration suite had ever executed. **When a test starts really running, treat what it says as
  the finding, not as an inconvenience.**

- **TEST-2** MUST: **the four A's — Arrange, Act, Assert, Annihilate**, in that order, and the
  fourth is the one that gets dropped. Arrange the state the test needs; act once; assert on what
  the act produced; **annihilate what the test created, so the next test starts where this one
  began.** The first three are Bill Wake's 2001 pattern, popularised by Kent Beck's *Test Driven
  Development: By Example*; the fourth step is usually called teardown in the literature and
  **Annihilate is this project's name for it**, chosen because "teardown" sounds optional and this
  is not.

  Read the A's as obligations rather than as three comment headers:

  - **Arrange means establish, not discover.** A test that branches on the state it finds is a test
    whose assertions may never run. Six integration suites gated their first-run walk on
    `if (find.byType(WelcomeScreen)...isNotEmpty)` against a device carrying `onboarding_complete`,
    so that whole half executed in none of them while all six reported green.
  - **Act once.** Two acts in one case make a failure ambiguous about which one caused it.
  - **Assert the claim, not the render.** `expect(find.text('AYER'), findsOneWidget)` passes for any
    string; what it should pin is that the run being labelled cannot be yesterday's. A test that
    would survive the defect it is named for is not covering it.
  - **Annihilate what you made.** Not only files: a database, a simulator's preferences, an
    environment variable, a mutated source file during a falsification. Two live violations sit in
    this repository as the reason this clause is explicit — the vitest harness has left **453**
    `akimath_test_w*` databases on the local cluster and drops none, and a Tier 2 run overwrote a
    simulator's `akimath.day_log.v1` without capturing what was there first. PROC-8 is this rule
    applied to one case: prove the restore, and not with `git diff --quiet` on a path git does not
    track.

  Where a framework owns the fourth A — `tearDown`, `afterEach`, `addTearDown` — use it, because a
  cleanup that only runs when the assertions pass is not cleanup.

## DEP — Dependencies & what they send

- **DEP-1** NEVER add a dependency that sends data off the device — analytics, ads, attribution,
  crash reporting, remote config, remote fonts, any SDK that "phones home". **This is a category
  refusal, not a per-dependency question**, and since 2026-08-29 it is no longer child-derived:
  ADR 0004 made the product adults-only and its amendment §2 re-grounded the standing "no" on three
  supports that name no audience — the supply-chain surface of the four closures `CLAUDE.md` counts,
  the recurring-per-version audit cost ADR 0003 measured, and data minimisation, which adults are
  owed under the LFPDPPP as much as anyone. **The rule did not move; the sentence under it did**, and
  that is worth knowing before anyone reopens the category on the strength of a premise that is gone.
  The compliance posture in `ARCHITECTURE.md` §11 is still minimization by construction.
  Before adding *any* dependency, audit what network calls it makes and what it
  collects; "it's only a util" is not an audit. **The audit lives in
  `app/test/architecture/dependency_allowlist_test.dart`, beside the allowlist entry, in the same
  change** — not in a pull-request body, which is not greppable, not versioned next to the thing it
  describes, and fails no build. `shared_preferences`, added 2026-08-16, is the worked example: the
  gate went red on the addition, and the entry carries the publisher, what the package wraps, what it
  stores, and a verified negative for `HttpClient`, `package:http`, `Socket` and `WebSocket` across
  the facade, the platform interface and both mobile implementations. A **dev** dependency is out of
  the allowlist's scope because it does not ship, and the reason is stated at its declaration. Assets ship bundled for the same reason — the
  brand typefaces live in `app/assets/fonts/` precisely so that first launch makes no third-party
  request.

## BRD — Brand invariants

These are not taste. Most of them are enforced by committed tests
(`app/test/design/no_blurred_shadow_test.dart`, `app/test/design/tokens/brand_colors_test.dart`,
`app/test/design/brand/aki_spec_test.dart`), and a change that breaks one of those breaks the build.
Where a clause below is **not** test-backed it says so — an invariant a reviewer must read for is
still an invariant, but claiming a test behind it that does not exist is how a rulebook loses its
credit.

- **BRD-1** MUST: success and error are distinguishable by **shape**, never by hue alone — `AkiPose.correct`
  and `AkiPose.slip` differ in the tail, the ears and the mouth curve, not only in color. Coral means
  error and nothing else; green means action and success and nothing else; pink is never `error`,
  `success` or `action` — it is the accent, and `BrandColorRole.focus` is an input affordance, not a
  verdict. Ask `BrandColorRole` for a role, not `BrandColors` for a hue, in anything that
  communicates state.

- **BRD-2a** NEVER draw a blurred shadow, a gradient, a backdrop filter, or anything with Material
  elevation — shadows are hard, `blurRadius: 0` and `spreadRadius: 0`, offset from `BrandShape`.
  `no_blurred_shadow_test.dart` walks every screen and asserts four of those: no gradient,
  `blurRadius == 0`, `spreadRadius == 0`, and elevation 0 on `PhysicalModel` and `PhysicalShape`.
  It does **not** look for `BackdropFilter`, and none exists in `app/lib/` — that clause is a
  reviewer's read, not a red build, until someone adds
  `expect(find.byType(BackdropFilter), findsNothing)` to that test.

- **BRD-2b** NEVER write a color literal outside `app/lib/design/tokens/` — `brand_colors.dart` says
  so itself and is the single source of the palette; ask `BrandColorRole` for a role rather than
  `BrandColors` for a hue in anything that communicates state. **Carve-out, matching CLAUDE.md
  verbatim:** `Colors.transparent`, used to switch Material's surface tinting off, is the one
  exception on disk (`app/lib/design/theme.dart:37,42,48,53`). Nothing else loosens, and this is a
  red build rather than a `grep` a reviewer has to remember to run:
  `app/test/architecture/no_color_literal_test.dart` scans all of `app/lib/` except
  `design/tokens/` for `Color(0x`, `Color.fromARGB(`, `Color.fromRGBO(` and `Colors.`, with
  comments stripped first. The last is matched on a word boundary — `(?<![A-Za-z0-9_$])Colors\.` —
  because `Colors.` is a substring of `BrandColors.` and a naive match reports **94 correct lines**
  across 12 files. It carves out `Colors.transparent` by name, asserts the `Colors.` arm alone
  returns exactly the four `theme.dart` hits *before* that carve-out is applied, and reports how
  many files it scanned so a mistyped root cannot make it vacuously green. It does not match
  `#RRGGBB` text: the character sheet prints four brand hexes as swatch labels and is correct code.

- **BRD-2c** SHOULD: take geometry from `BrandShape` — radii, stroke widths, spacing — and give any
  deliberate departure a one-line reason next to it. The worked example is the 260px face tile in
  `splash_screen.dart`, whose doc comment justifies its 60px radius; that radius is now the screen's
  only unexplained-looking number and it is the one that has a reason, because the `width: 4` border
  beside it became `BrandShape.borderWidth` in `f0-token-scale` and the screen's uniform 26px rhythm
  is one named `_gap` constant carrying its own one-line reason. Hard-shadow offsets on widget
  surfaces are enforced rather than reviewed: `app/test/architecture/no_geometry_literal_test.dart`
  scans `app/lib/design/widgets/` and `app/lib/features/` for `Offset(`, leaving `app/lib/design/brand/`
  out because that is the artwork layer, where geometry *is* the content. Radii and border widths are
  **not** scanned — a bare `24` is not greppable without parsing — so on those two this stays a
  reviewer's read.

- **BRD-2d** MUST: any interactive target is at least `BrandShape.minTouchTarget` (48 logical
  pixels) in both dimensions — keypad keys and puzzle-board cells alike.

- **BRD-2e** MUST: **a banner action cannot wrap, so a long label does not belong in one.**
  `InlineBanner` lays out glyph, `Flexible(Text)` and `BrandButton.text` in one `Row`; the button
  is inflexible and its label is a single line, so once the label plus the message's longest word
  exceed the width, the row overflows and the chip is squeezed under the 48 px floor. Measured in
  `f7-conflicto-de-cuenta`: *"Cerrar sesión"* beside a two-line Spanish sentence overflowed by
  **65 px** at textScaler 1.3 and failed `touch_target_test` as well as `screen_overflow_test`.
  A one-word chip — *"Detalle"*, *"Reintentar"* — is what the banner is sized for. Anything longer
  goes below the surface as a full-width `BrandButton`, which is the idiom `ProfileScreen` already
  uses for the refused session's sign-in door. **Register the new state's screen before believing
  it fits**: both gates read `app/test/design/screen_registry.dart`, and a state that is not in it
  is a state neither gate has ever measured.

## GIT — Commits & branches

- **GIT-1** MUST: `git config user.email` is `geineryodan@gmail.com` — verify before committing —
  and **NEVER** add a `Co-Authored-By` trailer or any other tool-attribution line to a commit
  message.

- **GIT-2** MUST: one coherent change per commit, small and logical; subject is a conventional prefix
  plus a short lowercase description with no ticket id and no scope in parentheses
  (`chore: name the server package @akimath/server for the workspace`). Never bundle an unrelated
  edit — a `.gitignore` tweak, a formatting sweep, a refactor the change did not need — into a
  commit that describes something else.

- **GIT-5** MUST: **a branch is named after the change it carries**, and where OpenSpec has a
  change the branch name **is** its id, character for character. That is already the practice — 
  `f3-router`, `f6-a-week-of-each`, `ci-pg-client-install-is-bounded` and `docs-email-signup-is-open`
  are each a branch and a change directory with the same name — it had simply never been written
  down, which is why it drifts.

  The id itself is `<token>-<kebab-summary>`: the token is the **phase** (`f0`…`f8`, and `f1-5` for
  the half-phase that exists) when the work belongs to one, and otherwise a **conventional type** —
  `fix`, `docs`, `chore`, `test`, `refactor`, `ci`, `feat` — the same vocabulary GIT-2 uses for a
  subject. Lowercase, hyphens, English. Nothing else: **no date, no author, no ticket id** (there is
  no tracker), and no `spec-` prefix in front of a change id that already has a token — a proposal
  for `f3-deletion-web` is branched as `f3-deletion-web`, because the branch and the change are the
  same unit of work seen from two directories.

  The summary says what the change *does*, in the voice a subject would use: `f3-link-carries-the-band`,
  not `f3-band-changes`. Long is better than cryptic — `fix-chevron-reads-as-greater-than` earns
  every character.

  **English is not decoration here**: a change id is an identifier, so LANG-1 governs it. Three
  archived changes are in Spanish — `f7-estados-de-racha`, `f7-perfil-absorbe-avance`,
  `f7-perfil-es-la-raiz` — and they are the reason this clause is explicit. They stay as they are;
  renaming an archived change would break the record.

  Branches a tool creates for itself — `worktree-agent-*` from an isolated subagent — are never
  pushed and are deleted with their worktree. `.gitignore` covers the directory; nothing covers the
  branch, so that is a discipline rather than a gate.

- **GIT-4** MUST: **a pull request has a title that obeys GIT-2 and a body that follows
  `.github/PULL_REQUEST_TEMPLATE.md`.** Merges here are squashes, so the title box *is* the commit
  subject that lands on `main` — the same conventional prefix, the same short lowercase
  description, the same ban on a ticket id and on a scope in parentheses. This is not a second
  convention, it is GIT-2 reaching the one subject nobody was reading it against: of the twelve
  subjects on `main` before this rule, ten carried no prefix at all and the two that did —
  `fix(app):`, `feat(app):` — carried the parentheses GIT-2 bans by name.

  The template is the repository's one shape for a body, and its sections are the ones this
  project argues from: what lands, why, **the evidence tier with its numbers**, what the change
  deliberately does not do, and what has to happen after it merges. Delete a section that has
  nothing true to say — an empty heading reads as covered, which is the same defect as a gate that
  cannot fail. GitHub fills the box from the template automatically; a body that ignored it is a
  review finding, not a style note.

- **GIT-3** MUST: **`main` is the trunk.** It is protected by the `protect-main` ruleset — no
  direct push, no force-push, no deletion — and is reached only by a pull request from a branch cut
  from `main`, never from another feature branch. The diff base for any review or audit is
  **`origin/main`**, stated explicitly rather than left to `origin/HEAD`.

  **`dev` is not the working branch and has not been since 2026-08-17**, when it stopped at pull
  request #6. Everything since — #7 through #108 — merged into `main`, which is 155 commits ahead
  and differs in 656 files, and `dev` is a strict ancestor holding nothing `main` does not. This
  rule said the opposite until 2026-08-26; a review that took `origin/dev` as its base read those
  155 commits as the change under it.

## PROC — Process

- **PROC-1** MUST: **TDD.** The test is written first and lands in the same commit as the behavior it
  describes — tests are committed here, they are the deliverable, and a behavior change with no test
  in its commit is incomplete. `app/test/`, `packages/server/test/` and `packages/contract/test/`
  are the three homes; a test that needs a mock to describe a decision is a PURE-1 finding, not a
  test problem.

- **PROC-5** MUST: a change is proven by **evidence**, and the tier reached is stated in words. The
  tier names here are the same three CLAUDE.md uses; an agent file that numbers them differently is
  wrong and gets corrected under PROC-6.
  - **Tier 1 — the committed suite, always.** Run these, verbatim, per package:

    ```sh
    cd app               && flutter analyze --fatal-infos
    cd app               && flutter test
    cd packages/server   && npm run verify      # tsc --noEmit && vitest run
    cd packages/contract && npm run verify      # tsc --noEmit && vitest run
    cd packages/core     && npm run verify      # tsc --noEmit && vitest run
    ```

    `--fatal-infos` is not decoration: these are the commands `.claude/hooks/verify-gate.sh` runs
    as a `PreToolUse` hook on every `git commit` and `git push`, exiting **2** (blocking) on a
    failure, and the same commands `.github/workflows/ci.yml` runs in its `dart`, `ts` and
    `contract` jobs.
    (The hook and CI spell the TypeScript half as `npm run typecheck` then `npm test`, which is
    exactly what `npm run verify` chains — same two checks, one script.)
    The rulebook, the hook and CI must name one set of commands; if they ever diverge, reconcile
    them in the same session (PROC-6). The baseline is **zero**: as of 2026-08-26 the Flutter suite is 3275,
    `packages/server` 325 of 454 (129 skip without a Postgres), `packages/contract` 248 and
    `packages/core` 340, all passing, and every analyzer reports clean, so there is no pre-existing noise to hide a new failure in. Green before, green after,
    stated with the counts.
  - **Tier 1b — SHOULD, when the change is in the pure core: show the tests bite.** A green suite
    that would stay green with the logic inverted is not evidence.
    - TypeScript: `npm run mutation` (Stryker, `break: 70`) and `npm run dry` (jscpd) in the
      package under change — `packages/server` scores 100.00 with 0 clones today,
      `packages/contract` 91.71 with 0 clones. **jscpd's `threshold: 1` means `npm run dry`
      exits 0 with real clones in it**, so the number to read is "clones found", not the exit
      code.
    - Dart: there is **no configured mutation harness** — `mutation_test` is a dev dependency but
      the rules XML that would define its test commands does not exist, so do not write that
      command as if it ran. The substitute is a **falsification step**, and because it edits
      versioned production code its mechanism is part of the rule, not a detail:
      0. **Commit the change first, then falsify.** Every restore below is a restore *to
         something*, and until the work is committed there is nothing safe to restore to. This
         is the cheap fix for both traps in step 1, and it costs one commit.
      0b. **A mutant Stryker calls survived, and a hand falsification kills, is a finding about
         the code — usually module-scope work.** Anything a module *does* at import time
         (`const PARSED = parse(...)`) turns a bad edit into an **import** failure, and an import
         failure is not a test failure: every file importing it dies before its assertions run,
         and Stryker scores the mutant as survived. The fix is not to argue with the tool. Defer
         the work to first use, and the mutant fails where it can be seen. *(2026-08-19:
         `packages/core`'s `misconceptions.ts` read 56.31 with 42 survivors while a hand
         falsification of one of them went red. Making the parse lazy took it to 93.27 with the
         same tests.)*
      1. For a **tracked file with no uncommitted changes**, `git checkout -- <file>` is correct.
         For a **tracked file carrying this session's uncommitted work**, it is not: it restores
         to HEAD and silently deletes the change you are testing, mutation and feature together —
         a green suite afterwards is green because the feature is gone. Use
         `git stash push -- <file>` / `git stash pop`, or the copy below. For an **untracked**
         file — a new file in a session that has not committed — neither works: `git stash push`
         will not take an untracked path and `git checkout --` has nothing to restore from. Copy
         it out of the tree first, and record a `shasum -a 256` of it.
         *(All three failed in one run on 2026-08-19: four falsifications restored with
         `git checkout --` across two tracked files holding uncommitted work and two untracked
         ones. Two reverted to HEAD, two kept the mutation, and the suite was green either way.
         Step 0 is the rule that run bought.)*
      2. Invert one assertion or return value, run `cd app && flutter test`, and record the
         **named** test that went red. **Red is the runner's exit status, never a grep over its
         output.** A pattern matching the failure line is one ANSI escape away from finding
         nothing, and a Tier 1b check that cannot see red reports the mutation as survived — the
         one direction that turns evidence into its opposite. Get the name from the output by all
         means; decide pass or fail from `$?`. *(Reported "STILL GREEN" twice on 2026-08-19 for
         mutations that did bite.)*
      3. Restore: `git checkout -- <file>` (or `git stash pop`, or the copy), then prove it with
         **two** things pasted into the ledger. Tracked: `git diff --quiet -- <file>` and a
         `flutter test` run back to the count you recorded before the mutation. Untracked:
         `git diff --quiet` is **vacuous** — it exits 0 for any path git does not track, whether or
         not the mutation is still in the file — so the proof is the `shasum -a 256` from step 1
         repeated and matching (`diff -q <backup> <file>` is the accepted equivalent for a single
         file), plus that same returned test count. PROC-8 is the general form of this trap.

      A falsification step without that closing proof is not evidence, it is an uncommitted
      mutation waiting to be staged by the next `git add`.
    - **Never report a score you did not produce in this session.**
  - **Tier 2 — exercise the real thing.** The app run on a device or simulator when the change
    surfaces on screen — the 48px touch area, shape-not-hue, the absence of blur are judged there
    and not in a widget test — or the endpoint called for real once endpoints and an environment
    exist. There is no endpoint, dev environment, deploy or database today, so on the server side
    tier 2 is currently unreachable and saying so is the correct outcome. "It should work" and "it
    compiles" are not evidence; neither is a passing suite that was never executed.
  - **`dart run dart_code_linter:metrics analyze lib
    --set-exit-on-violation-level=warning` is tier-1 evidence and is part of the everyday gate.**
    This bullet said the opposite until 2026-08-21 and was stale: it read *"not evidence at any
    tier, `app/analysis_options.yaml` carries no `dart_code_linter:` block"*, and that block has
    since landed (line 43, with the thresholds set at what the code does today). CI runs the step
    in its `dart` job and CLAUDE.md documents it, so CLAUDE.md won and this was corrected in the
    session that noticed — one agent had been told by three documents not to run a gate CI enforces.
    **The flag is not decoration**: without it the command prints its warnings and exits **0**,
    which is the green-by-construction trap the old bullet correctly described, one level deeper.
    The thresholds ratchet *down* as the code gets simpler and never up to accommodate it.
    `.claude/agents/*.md` may still carry the old prohibition; an agent file that does is wrong and
    is corrected under this rule.
  - The root `package.json` `verify`/`typecheck` scripts delegate to `pnpm -r`; **pnpm is not
    installed on this machine**, so they do not run. Use the per-package commands above until the
    pnpm migration lands.

  *(The IDs `PROC-5` and `PROC-6` are preserved verbatim from the parent workflow, gaps and all —
  `PROC-5` is the evidence rule there too — so cross-project references keep resolving. Do not
  renumber either.)*

- **PROC-6** MUST: **this rulebook and the agent instructions are living documents.** Whenever a
  correction lands — the user overrules a decision, a review finding turns out to be wrong, a
  carve-out is discovered, or a failure mode bites twice — write it down in the same session: as a
  new or edited rule here (with an ID), and in the affected `.claude/agents/*.md` when it changes how
  an agent should behave. A lesson that lives only in a chat reply will be relearned the hard way.
  **Corollary:** a review finding's **proposed fix** is a claim to verify against this rulebook, not
  an instruction to apply — findings have suggested rule-violating fixes before.
  A rulebook that did not grow this month is not stable; it means nobody wrote down what they
  learned.

- **PROC-7** MUST: a convention that has to reach **planning** lives in `openspec/config.yaml`, not
  only here. Its `context:` block is what every `/opsx:propose` run reads, and its per-artifact
  `rules:` are what shape `proposal.md`, the delta specs and `tasks.md`. A rule added here and not
  there is invisible at the moment it would have done the most good — before the code exists. Edit
  both in the same commit, or neither.
  Keep `config.yaml` pointing at files rather than restating them: a paraphrase of this rulebook
  copied into it goes stale silently, and nothing will ever fail to warn you.

- **PROC-8** MUST: **git cannot prove anything about a path it does not track.** `git diff
  --quiet -- <file>` and `git diff --exit-code -- <dir>` both exit **0** for an untracked path —
  not because nothing changed, but because git has nothing to compare against. The proof is
  therefore vacuous exactly when the file is new, which is exactly when a session is most likely
  to reach for it. Use a `shasum -a 256` recorded before and repeated after instead, and **say
  which form you used**: for a single file the checksum (or `diff -q <backup> <file>`), for a
  whole directory a checksum of the sorted file list — `find <dir> -type f | sort | xargs shasum
  -a 256` — compared before and after. PROC-5's tier-1b falsification step carries the mechanism;
  this rule is why it has two branches. **For a *tracked* file `git diff --quiet -- <file>` is
  itself the proof** — the checksum is the substitute for the untracked case, not a replacement for
  git. A ledger that reads "the file is versioned, so `shasum` is the proof, not `git diff`" has
  inverted this rule; it was written that way once, in `f2-onboarding-first-run`, by an author who
  had taken in only the rule's first sentence. Found twice independently, in `f0-invariant-tests` (a
  falsification step on a new test file) and in `f0-pack-contract` (a byte-determinism gate over
  an untracked `contract/`), which is what promoted it to a rule.

  **A third branch, and the nastiest, because the file is tracked and the proof still lies: `git
  diff` compares the working tree to the *index*, not to `HEAD`.** Anything that writes to the
  index — `git checkout <commit> -- <paths>`, a stray `git add` — moves what the proof is measured
  against, so a restore that put the *wrong* content back exits **0** and reads as clean. Measured
  in `fix-the-puzzle-gates-can-fail`: a tier-1b counterfactual reverted three files with
  `git checkout c328cf3 -- <paths>`, which stages; the follow-up `git checkout -- <paths>` then
  restored the working tree *from that index*, and `git diff --quiet` exited 0 with the reverted
  files still in the tree. It was caught only because `git status --short` showed three staged
  `M`s. **So: restore with `git checkout HEAD -- <paths>`, and close with `git status --short`
  empty *and* `git diff --quiet HEAD`** — the second names the commit, which is the thing the
  restore was supposed to reach.

- **PROC-9** MUST: a mutation score is only evidence if the run's **initial test run** passed.
  Stryker copies the package into a sandbox, so any test that reads a path outside the package
  must discover that path by walking up rather than by counting `..` segments — otherwise the dry
  run dies and there is no score at all, which is not the same as a low one. Measured in
  `f0-pack-contract`: the fixture tests' hard-coded `../../../contract` resolved to nothing under
  the sandbox. Never report a number from a run you did not watch complete.

- **PROC-10** MUST: a gate driven by a registry asserts its registry is **non-empty**. Measured in
  `f0-invariant-tests`: pointing `no_blurred_shadow_test.dart` at an empty `screen_registry.dart`
  took it from 6 tests to `No tests ran. No tests were found.` and **exited 0** — the whole suite
  dropped 72 to 66 in that session and reported success. A gate whose input list silently reaches
  zero is indistinguishable from a gate that found nothing wrong. `expect(registeredScreens,
  isNotEmpty)` in `app/test/design/screen_overflow_test.dart` and the per-root counts in
  `app/test/architecture/pure_boundary_test.dart` are the two forms this takes today. The same
  applies to a path-filtered scan: report how many files it walked, and fail at zero.
- **PROC-11** MUST: **an assertion that holds for any input is not a test.** Green that carries no
  information is worse than a gap, because a gap is visible. Six instances, all in this repository,
  all found by review rather than by the suite:
  - **An `expect` whose sides are algebraically equal.** `round_screen_test.dart` asserted
    `text.width * (slot.width / text.width) <= slot.width + 0.5`, which reduces to
    `slot.width <= slot.width + 0.5`. It was written to hold down a painting defect that had shipped,
    and it held nothing.
  - **A `hasLength` or value-set check over an enum whose arms nothing exercises.** `MathTone.values`
    was pinned at two members while the adapter arm behind one was unreachable;
    `BannerPlacement.values` was pinned at two while neither placement's radius was rendered in a
    test.
  - **A `catch` no test reaches.** Both arms of `PrefsDayLogStore` were unreached, because the only
    backend in the tests never fails — and the write arm was the half the original incident was on.
  - **A test whose name claims more than its body checks.** `'a notice banner renders with its
    glyph'` checked a widget type, a string and a rect ordering, so a grep for glyph coverage
    returned a false positive.
  - **Fixture data that satisfies the mutant as well as the code.** The assertion is sound and the
    *inputs* make it insensitive, which no amount of reading the assertion reveals. In
    `req-me-standing`, `get-standing.test.ts` pinned `ORDER BY skill_id` with rows seeded
    4→900, 1→1200.5, 2→1050 — whose rating-descending order is the same `[1, 2, 4]`, so
    `ORDER BY rating DESC` passed it untouched. The fix was the data, not the assertion: give the
    highest rating to the highest skill id and the two orders disagree. **Whenever a test pins a
    choice between two columns, two keys or two orderings, the fixture must make the alternatives
    produce different output** — otherwise the test documents an intention it cannot enforce.

  - **A `find.text` that pins player-facing copy without pinning its truth.** The string form of
    the first bullet, and the one that let a false statement reach a player.
    `streak_screens_test.dart` asserted `expect(find.text('AYER'), findsOneWidget)` on
    `4.13 Racha perdida` — which passes for *any* caption whatsoever, so it could not tell a true
    one from a false one, and the caption was false on every reachable input (LANG-2). The remedy
    is to make the test walk the chain the screen is reached through and assert the *relationship*:
    a pure sweep over `streakStateFor` pinning that `broken` implies the newest recorded day is
    older than yesterday, and a screen test that establishes that state before it reads the
    caption. A test that pins copy and nothing else documents the spelling, not the claim.

  The remedy is the same in every case: **state the mutation the test would catch, then make it.**
  When a test is the record of a defect that shipped, PROC-5's tier-1b falsification is not optional
  — invert the fix and watch that specific test go red.

- **PROC-13** MUST: **a value that flows from a parent into a child is asserted on the *second*
  frame, not the first.** A test that pumps a widget once and reads what it drew has checked
  construction and nothing else — and construction is the half that never breaks. Measured in
  `f7-cuenta-y-perfil`: `TabStack` built its root through `onGenerateRoute`, which the Navigator
  calls **once**, so the `pageBuilder` closure captured whichever `child` the first build passed.
  Every later `RootScaffold.setState` produced a root widget that was constructed and never
  mounted. The session the shell holds travels that way, so **signing in changed nothing in the
  running app** — no address, no `POST /players/link`, no history, no sync — while the suite was
  green and `CLAUDE.md` described the behaviour as working. Nothing had ever pumped the shell
  twice.

  The remedy is two lines: `pumpWidget` with one value, `pumpWidget` with another, and assert the
  screen moved. Where the parent is also meant to preserve the child's state — the shell's
  `IndexedStack` exists so the home does not re-read its pack — assert **both halves in one test**,
  because they pull against each other and a fix for either alone is a regression in the other
  (`app/test/features/shell/ui/tab_stack_test.dart`'s `a root keeps its state while a changed
  field reaches it` counts `initState` calls and reads the new value in the same run).

  The general form, beyond Flutter: **any framework callback documented as running once is a place
  a data path can die silently.** `onGenerateRoute`, a route's `builder`, a `late final` field, a
  `Future` created in `initState` — each captures its inputs, and each keeps handing back the
  first ones for ever. Grep for the capture, not for the symptom.

- **PROC-15** MUST: **a callback that reports *upward* is started off the frame that triggered
  it.** PROC-13's mirror image: that rule is about a value arriving from a parent, this one is
  about a fact travelling back. A child may not mark an ancestor dirty while the ancestor is
  building, and `initState` and `didUpdateWidget` are both inside that build — so a root that
  calls `widget.onSomethingChanged?.call(…)` from either one throws
  `setState() or markNeedsBuild() called during build`.

  **`unawaited` is not deferral, and that is the half that surprises people.** An `async` body
  runs *synchronously up to its first `await`*, so `unawaited(_link(session))` still executes
  everything before that await inside the build. Measured in
  `fix-pack-waits-for-a-linked-player`: `ProfileRoute._link`'s first statement moves the account
  state, that state started reporting to `RootScaffold`, and seven cases in
  `session_survives_a_relaunch_test.dart` went red at once — none of them about the account.

  The remedy is one hop: start the work on a `Future.microtask`, re-check `mounted` inside it, and
  say in the doc comment that the deferral is load-bearing rather than incidental
  (`ProfileRoute._linkOffThisFrame`). Prefer deferring the *work* over deferring the
  *notification*: a network call had no business starting inside a build in the first place, and
  a notification posted a frame late is a second thing to reason about.

  **The trigger to watch for**: adding a `ValueChanged` to a widget that already assigns the field
  it reports, when any caller of that assignment is reachable from `initState` or
  `didUpdateWidget`. Funnel the assignments through one setter first — that is what makes the new
  callback one edit instead of seven, and it is what makes this rule checkable by reading.

- **PROC-14** MUST: **read the exception before you name the defect.** `flutter_test` fails a case
  when *any* rendering exception is thrown during layout, whatever that case asserts — so one
  overflow turns every gate that pumps the screen red at once, each under its own name. A failing
  case called *"nothing under 48px"* is therefore **not** evidence of a press under 48 px; it is
  evidence that something went wrong while the screen was laid out, and the exception says which.

  Measured here, on `4.12 Racha en riesgo`. It was reported as two defects — an overflow *and* a
  BRD-2d violation at two viewports — and the second was recorded in `screen_registry.dart` as the
  reason the screen was left unregistered. There was one defect: a horizontal `RenderFlex` overflow
  in `StreakBadge`. Probing the same four viewports measured every press at 354×110, 354×69,
  366×110 and 366×69 — nothing within 60 px of the floor — and fixing the overflow turned all four
  cases green with no press having moved. The wrong half of that report is the half that had
  outlived its session, in a comment, arguing against measuring the screen at all.

  The remedy is cheap and it is the one that was skipped: when a gate goes red, read what the
  runner printed above the case name, and where the failure is derived rather than direct, **verify
  the derived claim independently** — a throwaway probe that swallows the exception with
  `tester.takeException()` and prints what the gate would have measured takes one run. Cite the
  exception's own words in whatever you write down, the way an `excused` entry has to (`BRD-2e`),
  so the next reader can tell a measurement from an inference.

- **PROC-12** MUST: **the change satisfies its approved delta spec.** `CLAUDE.md` makes the
  `#### Scenario:` blocks under `openspec/changes/<id>/specs/**` the acceptance criteria, and each one
  names the test file that must cover it with a `→`. A scenario with no covering test, a `→` pointing
  at a file that does not exist, or a `SHALL` the code does not meet is a **blocking** finding, and it
  is citable as this rule. Added because a reviewer holding two real spec violations — a first run
  completed with no item solved, against `req-first-run`; a tutorial displaying a streak, against
  `req-teaching-item-unrated`'s *"contributing to no rating or streak"* — had to attach both to
  PROC-11 to give them an ID at all.


---

## What is deliberately not here

Rules must describe code that exists, or a reviewer will fire them at innocent code. These wait for
their subject:

| Not yet a rule | Because |
|---|---|
| Layering (`handler → controller → model`) | there are no handlers, controllers or models — PURE-1/PURE-2 is the layering this repo actually has |
| Data access, ORM, migrations, SQL | Neon and Drizzle are planned in `ARCHITECTURE.md` §5, not built |
| i18n mechanics | no i18n layer; LANG-1 covers the language split until there is one |
| Static-auditor gate (`fallow`) | the binary resolves (`fallow 3.15.0`, homebrew) but is a **global, not a project devDependency** — adapting.md §5's named silent-fail mode, where the terminal finds it and a fresh clone does not. It also analyzes TS/JS only: at this root it discovers 7 files and **0 of the 18 Dart files**. `.claude/hooks/verify-gate.sh` replaced it with the toolchains this repo owns. The self-ignoring `.fallow/` cache directory is a by-product of running it, not a tool. |
| Deploy, environments, release train | none exist |
| Ticket ids in branches, commits or PRs | there is no tracker; the backlog is `ARCHITECTURE.md` §9, phases F0–F8 |
| Compliance CI, protected-paths job, `Verdict` without `.color` | designed in `ARCHITECTURE.md` §6–§8, not written |

Each of these becomes a rule the day it becomes code — by PROC-6, in the session where it lands.
