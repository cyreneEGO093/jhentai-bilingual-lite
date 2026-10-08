// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/widget/native_pin_input.dart';

void main() {
  testWidgets('local PIN preserves four-character passwords and confirmation',
      (tester) async {
    final controller = TextEditingController();
    final completed = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: NativePinInput(
      controller: controller,
      onCompleted: (pin) {
        completed.add(pin);
        controller.clear();
      },
    ))));
    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).obscureText, isTrue);
    await tester.enterText(field, '1a2');
    expect(controller.text, '1a2');
    expect(completed, isEmpty);
    await tester.enterText(field, '123456');
    expect(completed, ['1234']);
    expect(controller.text, isEmpty);
    await tester.enterText(field, 'ab12');
    expect(completed, ['1234', 'ab12']);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
