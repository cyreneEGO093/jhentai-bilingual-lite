// Modified for Bilingual Lite (2026-10-07); see NOTICE. Original JHenTai portions: Apache-2.0.
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/widget/native_pin_input.dart';

import '../config/ui_config.dart';

class EHAppPasswordSettingDialog extends StatefulWidget {
  const EHAppPasswordSettingDialog({Key? key}) : super(key: key);

  @override
  State<EHAppPasswordSettingDialog> createState() => _EHAppPasswordSettingDialogState();
}

class _EHAppPasswordSettingDialogState extends State<EHAppPasswordSettingDialog> {
  String? firstPassword;
  late String hintText;

  TextEditingController controller = TextEditingController();

  @override
  void initState() {
    hintText = 'setPasswordHint'.tr;
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      children: [
        SizedBox(
          height: UIConfig.authDialogPinHeight,
          width: UIConfig.authDialogPinWidth,
          child: NativePinInput(
            controller: controller,
            autofocus: true,
            onCompleted: (String value) {
              if (firstPassword == null) {
                setState(() {
                  firstPassword = value;
                  hintText = 'confirmPasswordHint'.tr;
                  controller.clear();
                });
              } else {
                if (firstPassword == value) {
                  Get.back(result: value);
                } else {
                  setState(() {
                    firstPassword = null;
                    hintText = 'passwordNotMatchHint'.tr;
                    controller.clear();
                  });
                }
              }
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.only(bottom: 4),
          alignment: Alignment.center,
          child: Text(hintText),
        ),
      ],
    );
  }
}
