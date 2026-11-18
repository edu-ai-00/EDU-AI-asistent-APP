import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The parts of a [ChipsHeadingBar].
enum ChipsHeadingBarSlot { heading, chips, action }

/// A section heading with a row of filter chips and a trailing action link.
///
/// The three share one line (heading, chips, the action at the far end) only
/// while every chip fits on it whole. When they do not, the chips drop to a
/// line of their own under the heading and the action.
///
/// Squeezing a scrolling chip row into whatever the heading and the link leave
/// over cuts a chip off mid-word at the row's edge, which reads as a broken
/// button (BR-QRTHCM). The choice is made at layout time from the children's
/// intrinsic widths, so it follows the real labels: the locale, the user's
/// text scale, and a web font that only arrives after the first frame (the
/// text relayouts then, and this with it; a width measured in `build` would
/// stay stale).
class ChipsHeadingBar
    extends
        SlottedMultiChildRenderObjectWidget<ChipsHeadingBarSlot, RenderBox> {
  const ChipsHeadingBar({
    super.key,
    required this.heading,
    required this.chips,
    required this.action,
    this.gap = 32,
    this.runSpacing = 12,
  });

  final Widget heading;

  /// Usually a [FilterChipRow]. It gets the rest of a shared line, or the full
  /// width on a line of its own, so it should scroll rather than overflow.
  final Widget chips;

  final Widget action;

  /// Space between the parts that share a line.
  final double gap;

  /// Space between the heading's line and the chips once they have dropped.
  final double runSpacing;

  @override
  Iterable<ChipsHeadingBarSlot> get slots => ChipsHeadingBarSlot.values;

  @override
  Widget childForSlot(ChipsHeadingBarSlot slot) => switch (slot) {
    ChipsHeadingBarSlot.heading => heading,
    ChipsHeadingBarSlot.chips => chips,
    ChipsHeadingBarSlot.action => action,
  };

  @override
  RenderChipsHeadingBar createRenderObject(BuildContext context) =>
      RenderChipsHeadingBar(gap: gap, runSpacing: runSpacing);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderChipsHeadingBar renderObject,
  ) {
    renderObject
      ..gap = gap
      ..runSpacing = runSpacing;
  }
}

/// Where [RenderChipsHeadingBar] puts its children, and how big it is then.
typedef _Arrangement = ({
  Size size,
  Offset heading,
  Offset chips,
  Offset action,
});

class RenderChipsHeadingBar extends RenderBox
    with SlottedContainerRenderObjectMixin<ChipsHeadingBarSlot, RenderBox> {
  RenderChipsHeadingBar({required double gap, required double runSpacing})
    : _gap = gap,
      _runSpacing = runSpacing;

  double get gap => _gap;
  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  double get runSpacing => _runSpacing;
  double _runSpacing;
  set runSpacing(double value) {
    if (value == _runSpacing) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  RenderBox get _heading => childForSlot(ChipsHeadingBarSlot.heading)!;
  RenderBox get _chips => childForSlot(ChipsHeadingBarSlot.chips)!;
  RenderBox get _action => childForSlot(ChipsHeadingBarSlot.action)!;

  /// The width the three need side by side with every chip whole.
  double get _oneLineWidth =>
      _heading.getMaxIntrinsicWidth(double.infinity) +
      gap +
      _chips.getMaxIntrinsicWidth(double.infinity) +
      gap +
      _action.getMaxIntrinsicWidth(double.infinity);

  _Arrangement _arrange(BoxConstraints constraints, ChildLayouter layoutChild) {
    assert(constraints.hasBoundedWidth);
    final width = constraints.maxWidth;
    final loose = BoxConstraints(maxWidth: width);

    if (_oneLineWidth <= width) {
      final heading = layoutChild(_heading, loose);
      final action = layoutChild(_action, loose);
      // An Expanded between the two: the chips get the rest of the line, which
      // is at least their own width, since that is what fitting means.
      final chips = layoutChild(
        _chips,
        BoxConstraints.tightFor(
          width: math.max(0.0, width - heading.width - action.width - 2 * gap),
        ),
      );
      final height = math.max(
        heading.height,
        math.max(chips.height, action.height),
      );
      double centred(Size child) => (height - child.height) / 2;
      return (
        size: constraints.constrain(Size(width, height)),
        heading: Offset(0, centred(heading)),
        chips: Offset(heading.width + gap, centred(chips)),
        action: Offset(width - action.width, centred(action)),
      );
    }

    final action = layoutChild(_action, loose);
    // Should even these two crowd the line, the heading wraps rather than
    // running under the link.
    final heading = layoutChild(
      _heading,
      BoxConstraints(maxWidth: math.max(0.0, width - action.width - gap)),
    );
    final chips = layoutChild(_chips, BoxConstraints.tightFor(width: width));
    final lineHeight = math.max(heading.height, action.height);
    return (
      size: constraints.constrain(
        Size(width, lineHeight + runSpacing + chips.height),
      ),
      heading: Offset(0, (lineHeight - heading.height) / 2),
      chips: Offset(0, lineHeight + runSpacing),
      action: Offset(width - action.width, (lineHeight - action.height) / 2),
    );
  }

  @override
  void performLayout() {
    final arrangement = _arrange(constraints, ChildLayoutHelper.layoutChild);
    size = arrangement.size;
    _place(_heading, arrangement.heading);
    _place(_chips, arrangement.chips);
    _place(_action, arrangement.action);
  }

  void _place(RenderBox child, Offset offset) =>
      (child.parentData! as BoxParentData).offset = offset;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _arrange(constraints, ChildLayoutHelper.dryLayoutChild).size;

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _heading.getMinIntrinsicWidth(double.infinity) +
        gap +
        _action.getMaxIntrinsicWidth(double.infinity),
    _chips.getMinIntrinsicWidth(double.infinity),
  );

  @override
  double computeMaxIntrinsicWidth(double height) => _oneLineWidth;

  @override
  double computeMinIntrinsicHeight(double width) =>
      getDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      getDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in children) {
      final parentData = child.parentData! as BoxParentData;
      context.paintChild(child, parentData.offset + offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in children) {
      final parentData = child.parentData! as BoxParentData;
      final isHit = result.addWithPaintOffset(
        offset: parentData.offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (isHit) return true;
    }
    return false;
  }
}
