import 'package:flutter/services.dart';

/// Formatter that keeps a text field to a single decimal number.
///
/// Allows digits, one leading `-`, and one `.` or `,` decimal separator —
/// matching the grading path, which parses the answer with
/// `double.tryParse(text.replaceAll(',', '.'))`.
///
/// This is needed on top of `keyboardType: numberWithOptions`: that only hints
/// which soft keyboard to show, so on web and desktop a physical keyboard can
/// still type letters into a numeric question (BR-WAEZE3).
///
/// A separator typed into a field that already has one replaces the existing
/// separator in place, so typing `,` into `3.5` gives `3,5`. Dropping it
/// instead made the comma look impossible to write whenever an English-layout
/// numpad had already put a dot there (BR-M9ZY4D). The cursor stays where the
/// student typed rather than jumping to the end.
///
/// The output side is `formatDecimal` in `decimal_display.dart`, which renders
/// numbers back with the separator of the active locale.
class DecimalNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final input = newValue.text;
    final (start, end) = _insertedRange(oldValue.text, input);
    bool typed(int i) => i >= start && i < end;

    // A separator typed into a field that already has one gives way to it and
    // only lends it its character, so the digits never shift around.
    String? typedSeparator;
    var hasExistingSeparator = false;
    for (var i = 0; i < input.length; i++) {
      if (!_isSeparator(input[i])) continue;
      if (!typed(i)) {
        hasExistingSeparator = true;
      } else {
        typedSeparator ??= input[i];
      }
    }

    // Drops every character that cannot appear in a decimal number, keeping
    // the first `-` (only in leading position) and one decimal separator.
    // `offsets[i]` is how much output input[0..i) produced, i.e. where a
    // cursor at input offset i lands after filtering.
    final buffer = StringBuffer();
    final offsets = List<int>.filled(input.length + 1, 0);
    var hasSeparator = false;

    for (var i = 0; i < input.length; i++) {
      offsets[i] = buffer.length;
      final char = input[i];
      if (_isDigit(char)) {
        buffer.write(char);
      } else if (char == '-') {
        if (buffer.isEmpty) buffer.write(char);
      } else if (_isSeparator(char)) {
        if (hasSeparator) continue;
        if (hasExistingSeparator && typed(i)) continue;
        hasSeparator = true;
        buffer.write(typedSeparator ?? char);
      }
    }
    offsets[input.length] = buffer.length;

    final filtered = buffer.toString();
    if (filtered == input) return newValue;

    int map(int offset) => offsets[offset.clamp(0, input.length)];
    final selection = newValue.selection;
    return newValue.copyWith(
      text: filtered,
      selection: selection.isValid
          ? selection.copyWith(
              baseOffset: map(selection.baseOffset),
              extentOffset: map(selection.extentOffset),
            )
          : TextSelection.collapsed(offset: filtered.length),
      composing: TextRange.empty,
    );
  }

  /// The span of [next] that replaced a span of [previous] — the typed
  /// character, or the pasted string — as `(start, end)` offsets into [next].
  static (int, int) _insertedRange(String previous, String next) {
    var start = 0;
    while (start < previous.length &&
        start < next.length &&
        previous[start] == next[start]) {
      start++;
    }
    var previousEnd = previous.length;
    var nextEnd = next.length;
    while (previousEnd > start &&
        nextEnd > start &&
        previous[previousEnd - 1] == next[nextEnd - 1]) {
      previousEnd--;
      nextEnd--;
    }
    return (start, nextEnd);
  }

  static bool _isSeparator(String char) => char == '.' || char == ',';

  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }
}
