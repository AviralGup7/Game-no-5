library;

import 'package:flutter/material.dart';
import '../services/settings.dart';

/// Plain language, no jargon, worked example.
///
/// Nonogram clue notation is the single biggest barrier to this game: a grid
/// fringed with numbers means nothing until someone explains it once. Most
/// nonogram apps either skip this or bury it behind a "?" that nobody presses,
/// so this is shown automatically on first run and is always one tap away.
class HowToPlayScreen extends StatelessWidget {
  final Settings settings;
  const HowToPlayScreen({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    final fs = settings.fontScale;
    final scheme = Theme.of(context).colorScheme;

    TextStyle h() =>
        TextStyle(fontSize: 21 * fs, fontWeight: FontWeight.w700, height: 1.3);
    TextStyle b() => TextStyle(fontSize: 17 * fs, height: 1.45);

    return Scaffold(
      appBar: AppBar(title: const Text('How to play')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text('The idea', style: h()),
            const SizedBox(height: 6),
            Text(
              'Fill in the right squares and a picture appears. The numbers '
              'around the edge tell you which squares those are.',
              style: b(),
            ),
            const SizedBox(height: 22),

            Text('What the numbers mean', style: h()),
            const SizedBox(height: 6),
            Text(
              'Each number is a run of filled squares, all touching, in that '
              'row or column.\n\n'
              'A row marked 3 has three filled squares in a row — somewhere in '
              'that line. You do not know where yet.\n\n'
              'A row marked 2 1 has two filled squares, then AT LEAST one gap, '
              'then one filled square, in that order.\n\n'
              'A row marked 0 has none at all.',
              style: b(),
            ),
            const SizedBox(height: 22),

            _example(context, fs, scheme),
            const SizedBox(height: 22),

            Text('The trick that gets you started', style: h()),
            const SizedBox(height: 6),
            Text(
              'Take a row of 5 squares marked 4.\n\n'
              'Push the block of four as far LEFT as it goes: it covers '
              'squares 1, 2, 3, 4.\n\n'
              'Now push it as far RIGHT as it goes: it covers squares 2, 3, 4, '
              '5.\n\n'
              'Squares 2, 3 and 4 are covered both times. Wherever the block '
              'really sits, those three must be filled. You can fill them in '
              'now, without guessing.',
              style: b(),
            ),
            const SizedBox(height: 22),

            Text('Cross out what you rule out', style: h()),
            const SizedBox(height: 6),
            Text(
              'Use the Cross out button to mark squares you know are empty. '
              'This is the real skill — it is much easier to see what is left '
              'when the empties are marked, rather than trying to hold it all '
              'in your head.\n\n'
              'When a line is finished, its numbers go grey, and the app can '
              'cross out the rest of that line for you.',
              style: b(),
            ),
            const SizedBox(height: 22),

            Text('Drag to work faster', style: h()),
            const SizedBox(height: 6),
            Text(
              'You do not have to tap each square. Press and drag across '
              'several squares to mark them all at once.',
              style: b(),
            ),
            const SizedBox(height: 22),

            Text('If you get stuck', style: h()),
            const SizedBox(height: 6),
            Text(
              'Press Hint. It fills one square AND tells you the reasoning, so '
              'next time you can spot it yourself.\n\n'
              'Press Fix to clear any squares you have marked wrongly.\n\n'
              'There is never a time limit, and you can put the puzzle down '
              'and come back to it whenever you like.',
              style: b(),
            ),
            const SizedBox(height: 22),

            Text('Every puzzle can be solved by thinking', style: h()),
            const SizedBox(height: 6),
            Text(
              'You will never have to guess. Every puzzle in this app has been '
              'checked by computer: it has exactly one answer, and that answer '
              'can always be reached one row or column at a time.',
              style: b(),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Start playing', style: TextStyle(fontSize: 19 * fs)),
            ),
          ],
        ),
      ),
    );
  }

  /// A tiny worked board. Drawn with widgets rather than an image so it scales
  /// with the text-size setting and needs no asset.
  Widget _example(BuildContext context, double fs, ColorScheme scheme) {
    const rows = ['2', '1 1', '3'];
    const grid = [
      [1, 1, 0],
      [1, 0, 1],
      [1, 1, 1],
    ];
    const cols = ['3', '2', '2'];
    final cellSize = 42.0 * fs.clamp(0.9, 1.25);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A finished 3 × 3',
                style:
                    TextStyle(fontSize: 18 * fs, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(width: cellSize * 1.1),
                ...cols.map((c) => SizedBox(
                      width: cellSize,
                      child: Text(c,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 16 * fs,
                              fontWeight: FontWeight.w700)),
                    )),
              ],
            ),
            const SizedBox(height: 4),
            ...List.generate(3, (r) {
              return Row(
                children: [
                  SizedBox(
                    width: cellSize * 1.1,
                    child: Text(rows[r],
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 16 * fs, fontWeight: FontWeight.w700)),
                  ),
                  ...List.generate(3, (c) {
                    final on = grid[r][c] == 1;
                    return Container(
                      width: cellSize,
                      height: cellSize,
                      decoration: BoxDecoration(
                        color: on ? scheme.onSurface : Colors.transparent,
                        border: Border.all(
                            color: scheme.outline.withValues(alpha: .7)),
                      ),
                      child: on
                          ? null
                          : Icon(Icons.close,
                              size: cellSize * 0.5,
                              color: scheme.onSurface.withValues(alpha: .45)),
                    );
                  }),
                ],
              );
            }),
            const SizedBox(height: 12),
            Text(
              'Read the middle row: 1 1. One filled square, a gap, one filled '
              'square. That is exactly what you see.',
              style: TextStyle(fontSize: 15.5 * fs, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
