import 'package:flutter/material.dart';

/// Bottom line of the phone Knihovna card: the course meta (lessons ·
/// duration · version) on the left, the Stáhnout / Aktualizovat / Spustit
/// action at the card's end.
///
/// On a narrow card the two don't fit side by side. The action keeps its full
/// size at the end instead of overflowing the row and pushing the button past
/// the card, off-screen (BR-NF887W). The meta wraps onto further lines beside
/// it rather than running under it, so no piece — the version least of all —
/// is cut off (BR-5DRQ8T).
class CourseCardMetaRow extends StatelessWidget {
  /// The meta pieces in reading order. Each one is kept whole on its line;
  /// the pieces that don't fit move to the next line.
  final List<Widget> meta;

  final Widget action;

  const CourseCardMetaRow({
    super.key,
    required this.meta,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: meta,
          ),
        ),
        const SizedBox(width: 8),
        action,
      ],
    );
  }
}
