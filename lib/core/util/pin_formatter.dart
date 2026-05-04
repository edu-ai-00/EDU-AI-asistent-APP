import 'package:flutter/services.dart';

/// Formatter that converts input to uppercase and allows only alphanumeric characters.
/// Used by course PIN and student login code inputs.
class UpperCaseAlphanumericFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final filtered = newValue.text
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toUpperCase();
    return newValue.copyWith(
      text: filtered,
      selection: TextSelection.collapsed(offset: filtered.length),
    );
  }
}
