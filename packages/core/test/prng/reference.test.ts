import { describe, expect, it } from "vitest";

import { wordAt } from "../../src/prng/splitmix64.js";

/**
 * **The external anchor. Correctness enters the repository here and nowhere
 * else.**
 *
 * `ARCHITECTURE.md` §3: "vendored PRNG with a golden vector *emitted from the
 * code* — the canonical cyrb128+sfc32 snippet does not produce the vector that
 * was claimed, which is exactly the kind of thing a hand-written golden test
 * enshrines as wrong forever."
 *
 * So none of the numbers below were recalled, copied from a blog post, or
 * produced by the implementation they check. They were **derived by compiling
 * Sebastiano Vigna's own reference C and running it**, which makes the C
 * compiler the oracle and his source the authority. Anyone can redo it:
 *
 *   curl -sS -o splitmix64.c https://prng.di.unimi.it/splitmix64.c
 *   # sha256: 071795a8e29978a5cbd7015ce8f7d772e7ab4631e574e9102b748fe99105ff3d
 *   # append: void seed(uint64_t s) { x = s; }  and a main() printing next()
 *   clang -O2 -o vigna_run vigna_run.c && ./vigna_run
 *
 * Fetched and run 2026-08-17. The checksum is part of the citation: it pins
 * which bytes were compiled, so "I fetched his file" is checkable rather than
 * asserted.
 *
 * **Vigna publishes the algorithm and no test vector.** That is why this had to
 * be derived rather than transcribed — and it is precisely the situation in
 * which a plausible-looking recalled vector gets enshrined.
 *
 * The seeds span the range rather than sampling the middle: zero, one, the sign
 * boundary at 2^63 (a `bigint` seed arrives from a Postgres `bigint`, which is
 * signed), the top of the range, and one arbitrary value.
 */
const VIGNA: ReadonlyArray<{ seed: bigint; words: readonly bigint[] }> = [
  {
    seed: 0n,
    words: [
      16294208416658607535n,
      7960286522194355700n,
      487617019471545679n,
      17909611376780542444n,
      1961750202426094747n,
      6038094601263162090n,
      3207296026000306913n,
      14232521865600346940n,
    ],
  },
  {
    seed: 1n,
    words: [
      10451216379200822465n,
      13757245211066428519n,
      17911839290282890590n,
      8196980753821780235n,
      8195237237126968761n,
      14072917602864530048n,
      16184226688143867045n,
      9648886400068060533n,
    ],
  },
  {
    seed: 9223372036854775808n,
    words: [
      5196802822362493915n,
      14154714916085338130n,
      7036458801432265024n,
      6426116064599561977n,
      903114586442990803n,
      5584017301749351935n,
      9628024607338875747n,
      7084241770554260413n,
    ],
  },
  {
    seed: 18446744073709551615n,
    words: [
      16490336266968443936n,
      16834447057089888969n,
      4048727598324417001n,
      7862637804313477842n,
      13015481187462834606n,
      15212506146343009075n,
      17388166129998380965n,
      4638043754431676516n,
    ],
  },
  {
    seed: 1477776061723855037n,
    words: [
      1985237415132408290n,
      2979275885539914483n,
      13511426838097143398n,
      8488337342461049707n,
      15141737807933549159n,
      17093170987380407015n,
      16389528042912955399n,
      13177319091862933652n,
    ],
  },
];

describe("the vendored kernel agrees with Vigna's reference", () => {
  for (const { seed, words } of VIGNA) {
    it(`reproduces the reference stream for seed ${seed}`, () => {
      const produced = words.map((_, index) => wordAt(seed, index));
      expect(produced).toEqual(words);
    });
  }

  it("compared a stream at every seed, because a loop over an empty table passes silently (PROC-10)", () => {
    const total = VIGNA.reduce((sum, v) => sum + v.words.length, 0);
    expect(VIGNA.length).toBe(5);
    expect(total).toBe(40);
    // eslint-disable-next-line no-console
    console.log(`  prng reference · ${total} words across ${VIGNA.length} seeds`);
  });

  it("the vectors are not all the same stream, which a table generated from an ignored seed would be", () => {
    const firsts = new Set(VIGNA.map((v) => v.words[0]));
    expect(firsts.size).toBe(VIGNA.length);
  });
});
