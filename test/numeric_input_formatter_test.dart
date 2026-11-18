// Numeric question input filtering (BR-WAEZE3).
//
// A `type: numeric` question is graded with
// `double.tryParse(text.replaceAll(',', '.'))`, so anything the field lets
// through that is not a number scores as wrong without telling the student why.
// `keyboardType` does not help on web/desktop, where a physical keyboard writes
// into the field directly — the formatter is the only filter that runs there.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eduai/core/util/numeric_formatter.dart';

void main() {
  final formatter = DecimalNumberFormatter();

  /// Runs the formatter over a whole string as if it were pasted in one go.
  String paste(String text) => formatter
      .formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      )
      .text;

  /// Runs the formatter character by character, the way typing hits it.
  String type(String text) {
    var value = TextEditingValue.empty;
    for (final char in text.split('')) {
      final next = value.text + char;
      value = formatter.formatEditUpdate(
        value,
        TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        ),
      );
    }
    return value.text;
  }

  /// Field state "text with the cursor at the `|`", e.g. `3|.5`.
  TextEditingValue field(String marked) {
    final offset = marked.indexOf('|');
    return TextEditingValue(
      text: marked.replaceFirst('|', ''),
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  /// Types [char] at the cursor of [marked] and returns the result in the
  /// same `|` notation, so a test pins both the text and where the cursor
  /// ended up.
  String typeAt(String marked, String char) {
    final before = field(marked);
    final at = before.selection.baseOffset;
    final next = before.text.replaceRange(at, at, char);
    final after = formatter.formatEditUpdate(
      before,
      TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: at + char.length),
      ),
    );
    final cursor = after.selection.baseOffset;
    return after.text.replaceRange(cursor, cursor, '|');
  }

  group('DecimalNumberFormatter — accepts numbers', () {
    test('keeps plain digits', () {
      expect(type('42'), '42');
      expect(paste('42'), '42');
    });

    test('keeps a decimal point and a Czech decimal comma', () {
      expect(type('2.5'), '2.5');
      expect(type('2,5'), '2,5');
    });

    test('keeps a leading minus', () {
      expect(type('-3'), '-3');
      expect(type('-0,75'), '-0,75');
    });

    test('allows the intermediate states typing a decimal goes through', () {
      expect(type('-'), '-');
      expect(type('12,'), '12,');
      expect(type(',5'), ',5');
    });

    test('leaves an empty field empty', () {
      expect(paste(''), '');
    });
  });

  group('DecimalNumberFormatter — rejects non-numbers', () {
    test('drops letters, the reported case', () {
      expect(type('ggggg'), '');
      expect(paste('ggggg'), '');
    });

    test('drops letters mixed into a number', () {
      expect(type('1a2'), '12');
      expect(paste('12 kusů'), '12');
    });

    test('keeps only one decimal separator', () {
      expect(type('1.2.3'), '1.23');
      expect(type('1,2,3'), '1,23');
      expect(paste('1.2,3'), '1.23');
    });

    test('keeps a minus only in leading position', () {
      expect(type('1-2'), '12');
      expect(paste('--5'), '-5');
    });

    test('drops whitespace and separators the grader cannot parse', () {
      expect(paste('1 000'), '1000');
      expect(paste('4 %'), '4');
    });
  });

  // BR-M9ZY4D: with a dot already in the field (an English-layout numpad
  // types one), a typed comma used to vanish and throw the cursor to the end,
  // so the comma looked impossible to write.
  group('DecimalNumberFormatter — a second separator swaps the first', () {
    test('a comma typed after a dot turns the dot into a comma', () {
      expect(typeAt('3.|', ','), '3,|');
      expect(typeAt('3.5|', ','), '3,5|');
      expect(type('1.2,3'), '1,23');
    });

    test('a dot typed after a comma turns the comma into a dot', () {
      expect(typeAt('3,5|', '.'), '3.5|');
    });

    test('a separator typed in front of the existing one changes it', () {
      expect(typeAt('3|.5', ','), '3|,5');
    });

    test('the digits never move, only the separator character changes', () {
      expect(typeAt('12.34|', ','), '12,34|');
      expect(typeAt('12|.34', ','), '12|,34');
      expect(typeAt('1|2.34', ','), '1|2,34');
    });
  });

  group('DecimalNumberFormatter — the cursor stays where the student typed', () {
    test('a dropped letter leaves the cursor in place', () {
      expect(typeAt('1|2', 'a'), '1|2');
      expect(typeAt('|12', 'x'), '|12');
    });

    test('a dropped minus in the middle leaves the cursor in place', () {
      expect(typeAt('1|2', '-'), '1|2');
    });

    test('an accepted digit lands at the cursor', () {
      expect(typeAt('1|2', '5'), '15|2');
    });
  });

  group('DecimalNumberFormatter — output stays gradable', () {
    // Mirrors the parse in `_applyAnswer` (block_step_engine.dart).
    double? grade(String typed) =>
        double.tryParse(typed.trim().replaceAll(',', '.'));

    test('every accepted complete answer parses as a double', () {
      for (final input in ['42', '2,5', '-3', '-0,75', '0.5', ',5']) {
        expect(grade(type(input)), isNotNull, reason: 'input: $input');
      }
    });
  });
}
