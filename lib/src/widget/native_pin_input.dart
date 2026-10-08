// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Local application PIN input. No SMS reader, account API or platform plugin.
class NativePinInput extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onCompleted;
  final bool autofocus;
  const NativePinInput(
      {super.key,
      required this.controller,
      required this.onCompleted,
      this.autofocus = false});

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
            width: 240,
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 20),
              // Preserve upstream desktop PINs containing non-digit characters.
              inputFormatters: [LengthLimitingTextInputFormatter(4)],
              decoration: const InputDecoration(
                  labelText: 'PIN', border: OutlineInputBorder()),
              onChanged: (value) {
                if (value.length == 4) {
                  onCompleted(value);
                }
              },
            )),
      );
}
