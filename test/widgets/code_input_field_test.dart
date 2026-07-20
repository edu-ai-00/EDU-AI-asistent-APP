import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eduai/core/widgets/code_input_field.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('renders `length` boxes', (tester) async {
    await tester.pumpWidget(_host(const CodeInputField(length: 6)));

    expect(find.byKey(const ValueKey('code_box_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('code_box_5')), findsOneWidget);
    expect(find.byKey(const ValueKey('code_box_6')), findsNothing);
  });

  testWidgets('typing reports uppercased, filtered value via onChanged',
      (tester) async {
    final values = <String>[];
    await tester.pumpWidget(_host(
      CodeInputField(length: 6, onChanged: values.add),
    ));

    await tester.enterText(find.byType(TextField), 'ab-3');
    await tester.pump();

    expect(values.last, 'AB3');
  });

  testWidgets('each typed char shows in its box', (tester) async {
    await tester.pumpWidget(_host(const CodeInputField(length: 6)));

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('code_box_0')),
        matching: find.text('A'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('code_box_2')),
        matching: find.text('C'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('caps input at `length`', (tester) async {
    final values = <String>[];
    await tester.pumpWidget(_host(
      CodeInputField(length: 6, onChanged: values.add),
    ));

    await tester.enterText(find.byType(TextField), 'ABCDEFGHIJ');
    await tester.pump();

    expect(values.last, 'ABCDEF');
    expect(values.last.length, 6);
  });

  testWidgets('onCompleted fires once when full code entered',
      (tester) async {
    final completed = <String>[];
    await tester.pumpWidget(_host(
      CodeInputField(length: 6, onCompleted: completed.add),
    ));

    await tester.enterText(find.byType(TextField), 'ABC12');
    await tester.pump();
    expect(completed, isEmpty);

    await tester.enterText(find.byType(TextField), 'ABC123');
    await tester.pump();
    expect(completed, ['ABC123']);
  });

  testWidgets('shortening the value (delete) reports shorter string',
      (tester) async {
    final values = <String>[];
    await tester.pumpWidget(_host(
      CodeInputField(length: 6, onChanged: values.add),
    ));

    await tester.enterText(find.byType(TextField), 'ABCD');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'AB');
    await tester.pump();

    expect(values.last, 'AB');
  });

  testWidgets('external controller exposes the current code', (tester) async {
    final controller = CodeInputController();
    await tester.pumpWidget(_host(
      CodeInputField(length: 6, controller: controller),
    ));

    await tester.enterText(find.byType(TextField), 'xy9');
    await tester.pump();

    expect(controller.code, 'XY9');
  });
}
