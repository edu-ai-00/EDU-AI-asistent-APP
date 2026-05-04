import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// ScrollBehavior that accepts mouse drag in addition to touch/stylus/trackpad.
/// Without this, mouse users on Flutter web (e.g. Edge on Windows) cannot drag
/// horizontal carousels or pull-to-refresh.
class DragScrollBehavior extends MaterialScrollBehavior {
  const DragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}
