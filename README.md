# Large Print Nonogram

A picture-logic puzzle (nonogram / picross / griddler) built for older adults.
Fill the right squares from the numbers around the edge and a picture appears.

**No timers. No streak-shaming. No account. Works with the network switched
off.**

---

## Why this exists

Every mainstream puzzle app makes the same three mistakes for this audience:
small type, a countdown clock, and a full-screen ad the moment you finish
thinking. This one inverts all three.

| Decision | Reason |
|---|---|
| Opens at **1.15× text scale** | The app opens large. Shipping at 1.0 and expecting people to find a settings screen is the mistake every competitor makes. |
| **Elapsed clock only, never a countdown** | Time pressure is the single most common complaint from older players. |
| **Every puzzle is solvable without guessing** | Verified by computer on every puzzle. "I got stuck and had to guess" is indistinguishable, to the person holding the phone, from "this app is broken". |
| Mistakes shown by **colour + shape + shake** | Never colour alone. |
| **Drag to paint** | Tapping 60 squares one at a time is what makes big grids unpleasant, and repeated precise tapping is exactly what arthritic hands struggle with. |
| Music **defaults to off** | Audio that starts unasked is an uninstall trigger — many players are in shared rooms, care settings, or wearing hearing aids. |
| Hints **explain the technique** | A hint that just fills a square teaches nothing and leaves you equally stuck next time. |
| No cognitive or medical claims, anywhere | Lumosity paid a **$2M FTC settlement** for exactly that kind of copy. |

---

## The engine

Pure Dart, no Flutter imports, so it unit-tests on a bare VM.

A nonogram is fully determined by its picture — the clues are just a summary of
it — so unlike sudoku there is nothing to "dig out". The only real questions
are whether the clues have one answer, and whether a **human** can reach it.

Two invariants, both asserted on every generated puzzle:

1. **Exactly one solution**, checked by an independent solution counter.
2. **Line-solvable** — finishable by reasoning about one row or column at a
   time, with no trial-and-error branch. This is strictly stronger than
   uniqueness and is the one players actually feel.

Most hand-drawn pictures fail (2) on their own. Rather than discard them — they
are the entire appeal of the game — the generator **reveals the fewest starting
squares that make the puzzle line-solvable**, always choosing a square at the
exact point where the solver is stuck. Nothing is wasted and the picture is
preserved as drawn.

Measured over 240 generations across all four sizes:

| Metric | Result |
|---|---|
| Uniquely solvable | **240 / 240** |
| Solvable with no guessing | **240 / 240** |
| Worst generation time | **5 ms** |
| Average revealed squares | **0.22** |

## The pictures

**90 hand-authored pictures** stored as ASCII pixel art — reviewable in a diff,
no binary asset, no licence, no download. Roughly three months of daily puzzles
before the first repeat.

Random noise grids are technically valid nonograms and are what cheap apps
ship. They are also joyless: the picture is the reward. Solved pictures are
collected in an album, which rewards having played at all rather than only
rewarding never missing a day.

The library is audited by test: no duplicate artwork (the first draft of *Kite*
was pixel-identical to *Diamond*), nothing blank, nothing impossible.

---

## Accessibility

* Text scale slider 0.85–1.6 with a **live preview** while you drag.
* High-contrast mode: pure black on white, heavier grid lines.
* Dark mode.
* Touch targets ≥56 dp; grid cells never below 34 dp.
* The crossed-out mark differs from the filled mark **in hue, not just
  lightness**, so the two survive colour-blindness — there is a test asserting
  at least 40° of hue separation.
* Semantic labels throughout; the timer announces "there is no time limit".
* Every line of copy is plain English. No jargon, no "picross", no "griddler".

## Audio

Eight sound effects and three music tracks, all **CC0** (Kenney *Interface
Sounds*, MintoDog *Cozy Puzzle*). Provenance in
[`ATTRIBUTION.md`](ATTRIBUTION.md); `tool/verify_assets.sh` checks in CI that
every path referenced in Dart exists, decodes, is audible, is declared in
`pubspec.yaml` and is attributed.

A wrong entry plays a soft click, never a buzzer. If the audio plugin is
unavailable the app runs silently rather than crashing.

---

## Daily puzzle

Derived from a hash of the calendar date, so everyone worldwide gets the same
puzzle with **no server and no account**. Difficulty ramps Monday → Saturday
following newspaper convention, and eases off on Sunday so a weekly player is
not left on a cliff edge.

The date hash is hand-rolled rather than using `Object.hash`, which is
explicitly not stable across Dart versions — using it would silently change
everyone's puzzle on an SDK bump.

---

## Building

```bash
flutter pub get
flutter test                 # 59 tests
flutter analyze              # clean
bash tool/verify_assets.sh   # audio integrity
python tool/generate_icons.py
flutter build apk --release --target-platform android-arm64
```

Full toolchain setup, verified artifact sizes, and the three build failures
that recur on low-memory machines are documented in
[`RELEASE.md`](RELEASE.md).

## Status

Analyzer clean, 59 tests passing, release APK (23.2 MB) and Play bundle
(49.5 MB) both building.

**Not yet run on a physical device.** Everything is verified by test and static
analysis on a headless machine; nothing has been in a human hand. See
`RELEASE.md` for the four blockers before this can be published — the release
build is still debug-signed and still carries Google's AdMob test IDs.

## Licence

MIT © 2026 Aviral Gupta. See [`LICENSE`](LICENSE).
