// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;
import 'package:jhentai/src/translation/image_preprocessor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('compression bounds image size; crop preserves the selected pixels',
      () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xffff0000), ui.BlendMode.src);
    canvas.drawRect(const ui.Rect.fromLTWH(1500, 0, 1500, 1000),
        ui.Paint()..color = const ui.Color(0xff0000ff));
    final picture = recorder.endRecording();
    final image = await picture.toImage(3000, 1000);
    final whole = await prepareTranslationImage(image);
    expect(whole.width, 1280);
    expect(whole.height, 427);
    final crop = await prepareTranslationImage(image,
        crop: const ui.Rect.fromLTWH(.5, 0, .5, 1));
    final jpg = base64Decode(crop.dataUrl.split(',').last);
    expect(jpg.length, lessThan(3 * 1024 * 1024));
    final decoded = raster.decodeJpg(jpg)!;
    expect(decoded.width, 1280);
    expect(decoded.height, 853);
    final pixel = decoded.getPixel(500, 300);
    expect(pixel.b, greaterThan(240));
    expect(pixel.r, lessThan(10));
    image.dispose();
    picture.dispose();
  });
}
