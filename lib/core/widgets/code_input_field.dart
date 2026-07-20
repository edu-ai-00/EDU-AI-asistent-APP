import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../util/pin_formatter.dart';

/// Exposes the current code from a [CodeInputField] to the host page and lets
/// the host clear it. Backed by a single [TextEditingController] so deletion
/// is native TextField behaviour on every keyboard — no hardware-key tricks.
class CodeInputController extends ChangeNotifier {
  final TextEditingController _text = TextEditingController();

  String get code => _text.text;

  /// Programmatically set the code (e.g. prefill from a deep-link PIN). The
  /// bound [CodeInputField] reflects it immediately because it shares [_text].
  set code(String value) => _text.text = value;

  void clear() => _text.clear();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }
}

/// A segmented code entry rendered as [length] boxes but driven by ONE real
/// TextField. Typing auto-fills the next box, backspace deletes the previous
/// char and steps back, and paste distributes across boxes — all for free,
/// because there is only one editable field instead of [length] of them with
/// hand-rolled focus juggling.
class CodeInputField extends StatefulWidget {
  const CodeInputField({
    super.key,
    this.length = 6,
    this.controller,
    this.onChanged,
    this.onCompleted,
    this.autofocus = true,
    this.hasError = false,
  });

  final int length;
  final CodeInputController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final bool autofocus;
  final bool hasError;

  @override
  State<CodeInputField> createState() => _CodeInputFieldState();
}

class _CodeInputFieldState extends State<CodeInputField> {
  late final CodeInputController _owned;
  final FocusNode _focusNode = FocusNode();
  bool _completedFired = false;

  CodeInputController get _ctrl => widget.controller ?? _owned;
  TextEditingController get _text => _ctrl._text;

  @override
  void initState() {
    super.initState();
    _owned = CodeInputController();
    _text.addListener(_onTextChanged);
    _focusNode.addListener(() => setState(() {}));
  }

  void _onTextChanged() {
    final value = _text.text;
    widget.onChanged?.call(value);
    if (value.length == widget.length) {
      if (!_completedFired) {
        _completedFired = true;
        widget.onCompleted?.call(value);
      }
    } else {
      _completedFired = false;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _text.removeListener(_onTextChanged);
    _focusNode.dispose();
    if (widget.controller == null) _owned.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = _text.text;
    final activeIndex = code.length.clamp(0, widget.length - 1);

    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          Row(
            // Boxes stretch to fill the available width (capped by the parent,
            // max 640px) with a tight, constant gap — no large spaceBetween gaps.
            children: List.generate(widget.length * 2 - 1, (i) {
              if (i.isOdd) return const SizedBox(width: 8);
              final index = i ~/ 2;
              final filled = index < code.length;
              final isActive = _focusNode.hasFocus && index == activeIndex;
              final borderColor = widget.hasError
                  ? AppColors.error
                  : isActive
                      ? AppColors.primaryDark
                      : AppColors.primaryDark16;
              return Expanded(
                // Square box: height tracks the (responsive) width.
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                  key: ValueKey('code_box_$index'),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: AppDecorations.radiusM,
                    border: Border.all(
                      color: borderColor,
                      width: isActive ? 1.5 : 1,
                    ),
                  ),
                  // Digit scales with box width so it fills wider boxes
                  // on large screens and shrinks to fit on small ones.
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final fontSize =
                          (constraints.maxWidth * 0.5).clamp(20.0, 34.0);
                      return Text(
                        filled ? code[index] : '',
                        style: AppTextStyles.heading3Alt()
                            .copyWith(fontSize: fontSize),
                      );
                    },
                  ),
                ),
                ),
              );
            }),
          ),
          // The single real input, stretched transparently over the boxes.
          Positioned.fill(
            child: TextField(
              controller: _text,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.characters,
              showCursor: false,
              enableSuggestions: false,
              autocorrect: false,
              style: const TextStyle(color: Colors.transparent, height: 0.01),
              cursorColor: Colors.transparent,
              inputFormatters: [
                UpperCaseAlphanumericFormatter(),
                LengthLimitingTextInputFormatter(widget.length),
              ],
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
