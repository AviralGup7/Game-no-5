# Asset Attribution & Licences

Every third-party asset in this repository is **CC0 1.0 Universal (public
domain dedication)**. CC0 imposes **no attribution requirement** — this file
exists as a provenance record, not a legal obligation.

Keeping it matters anyway: if a licence is ever questioned (Play review, an
acquirer, a takedown claim), this is the evidence trail. Never ship an asset
you cannot trace to a source URL and a licence.

---

## Music — `assets/audio/music/`

All by **MintoDog** via OpenGameArt.org, released **CC0**.

| File in repo | Original | Source | Licence |
|---|---|---|---|
| `music_gameplay_a.ogg` | `cozy_puzzle_in-game_2_bpm90.ogg` | [Cozy Puzzle In-Game 2](https://opengameart.org/content/cozy-puzzle-in-game-2) | [CC0 1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `music_gameplay_b.ogg` | `cozy_puzzle_in-game_3_bpm108.ogg` | [Cozy Puzzle In-Game 3](https://opengameart.org/content/cozy-puzzle-in-game-3) | [CC0 1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `music_menu.ogg` | `cozy_puzzle_stage_select_bpm100.ogg` | [Cozy Puzzle Stage Select](https://opengameart.org/content/cozy-puzzle-stage-select) | [CC0 1.0](http://creativecommons.org/publicdomain/zero/1.0/) |

Artist page: <https://opengameart.org/users/mintodog>

**Modifications:** loudness-normalised to −18 LUFS (TP −2 dBTP) and
re-encoded to Vorbis q2 for mobile size. Musical content unchanged.

---

## Sound effects — `assets/audio/sfx/`

All from **Kenney** ([kenney.nl](https://www.kenney.nl)), *Interface Sounds*
pack v1.0, released **CC0**.

| File in repo | Original | Used for |
|---|---|---|
| `select_start.ogg` | `select_001.ogg` | Finger touches a square |
| `word_found.ogg` | `confirmation_001.ogg` | A correct number is entered |
| `word_wrong.ogg` | `drop_001.ogg` | An entry contradicts the puzzle |
| `puzzle_complete.ogg` | `confirmation_004.ogg` | Puzzle solved |
| `streak_up.ogg` | `confirmation_002.ogg` | Daily streak extended |
| `hint_used.ogg` | `bong_001.ogg` | Hint revealed |
| `button_tap.ogg` | `click_001.ogg` | Any button press |
| `navigate_back.ogg` | `back_001.ogg` | Leaving a screen |

Pack: <https://kenney.nl/assets/interface-sounds> · Licence: [CC0 1.0](http://creativecommons.org/publicdomain/zero/1.0/)

**Modifications:** loudness-normalised to −16 LUFS, downmixed to mono,
resampled to 22.05 kHz, re-encoded Vorbis q1 (~4 KB each).

---

## Design notes on the audio

Choices here follow the same accessibility thesis as the rest of the app:

- **`word_wrong` is a soft click, not a buzzer.** Older players who have just
  entered a wrong number are already mildly frustrated; a harsh error tone reads
  as being told off. Kenney's `error_*.ogg` files were deliberately rejected.
- **Music defaults to OFF.** Audio that starts unprompted is an uninstall
  trigger for this audience — many play near others, in care settings, or with
  hearing aids. It is opt-in via Settings.
- **SFX are mono and quiet.** They confirm an action; they are not the
  experience.
- **Everything is bundled, nothing streams.** The app stays 100% offline.

---

## Adding new assets

1. Confirm the licence is **CC0** or **Pixabay Content Licence**. Avoid CC-BY
   unless you will genuinely maintain the attribution screen; avoid CC-BY-SA and
   any NonCommercial (`NC`) licence entirely — `NC` is incompatible with an
   ad-monetised app.
2. Record the source URL and licence **in this file, in the same commit**.
3. Normalise loudness so it matches the existing set.
4. Re-run `tool/verify_assets.sh`.
