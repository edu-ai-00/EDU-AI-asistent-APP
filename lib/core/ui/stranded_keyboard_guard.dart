import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Takes down an iOS keyboard that no text field is holding (BR-KDKQBR).
///
/// On iOS 26 UIKit resigns Flutter's hidden text view when the student
/// switches apps. The engine reports that to the framework as a closed
/// connection, so the field unfocuses, but the engine keeps the field as its
/// client, and on the way back UIKit makes the same view first responder
/// again: the keyboard returns with nothing focused behind it. Every way a
/// widget takes the keyboard down — unfocusing, being disposed — goes through
/// the connection the framework has already dropped, so none of them sends
/// anything, and the keyboard stays until the app is killed. In the chat it
/// sat over the conversation list and the bottom navigation, so the student
/// could not leave (flutter/flutter#189051, #189263; the engine fix,
/// flutter/flutter#191781, is newer than the Flutter the app is built with).
///
/// Whenever the keyboard comes up, or focus moves, while the keyboard is on
/// screen and no text field has focus, this sends the engine the two messages
/// the framework sends when a field lets go — `TextInput.clearClient`, then
/// `TextInput.hide`. Clearing the client also stops UIKit bringing the view
/// back. When the framework has already let go itself, they change nothing,
/// and a keyboard a native view owns (the Microsoft sign-in web page) is not
/// on Flutter's text view, so `TextInput.hide` does not reach it.
///
/// iOS only: Android and the web keep the keyboard in step with the framework.
class StrandedKeyboardGuard extends StatefulWidget {
  final Widget child;

  const StrandedKeyboardGuard({super.key, required this.child});

  @override
  State<StrandedKeyboardGuard> createState() => _StrandedKeyboardGuardState();
}

class _StrandedKeyboardGuardState extends State<StrandedKeyboardGuard>
    with WidgetsBindingObserver {
  /// Decided once: the platform does not change under a running app.
  late final bool _active =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  double _lastInset = 0;

  @override
  void initState() {
    super.initState();
    if (!_active) return;
    _lastInset = _keyboardInset;
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    if (_active) {
      WidgetsBinding.instance.removeObserver(this);
      FocusManager.instance.removeListener(_onFocusChanged);
    }
    super.dispose();
  }

  /// The keyboard's height across the app's views, in physical pixels.
  double get _keyboardInset {
    var inset = 0.0;
    for (final view in WidgetsBinding.instance.platformDispatcher.views) {
      if (view.viewInsets.bottom > inset) inset = view.viewInsets.bottom;
    }
    return inset;
  }

  @override
  void didChangeMetrics() {
    final inset = _keyboardInset;
    final rising = inset > _lastInset;
    _lastInset = inset;
    // Only a keyboard coming up: one going down is the framework's own hide
    // playing out.
    if (rising) _hideIfStranded(inset);
  }

  /// Leaving a page with a stranded keyboard moves focus, so this is also
  /// what takes it down when the student backs out of the chat.
  void _onFocusChanged() => _hideIfStranded(_keyboardInset);

  void _hideIfStranded(double inset) {
    if (inset <= 0 || _textFieldHasFocus) return;
    SystemChannels.textInput.invokeMethod<void>('TextInput.clearClient');
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  /// A focused text field owns the keyboard, whatever its height does.
  static bool get _textFieldHasFocus {
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null &&
        context.findAncestorStateOfType<EditableTextState>() != null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
