// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:html/dom.dart' as dom;
import 'package:jhentai/src/model/gallery_comment.dart';
import 'package:jhentai/src/pages/details/comment/eh_comment.dart';

void main() {
  for (final width in [320.0, 430.0, 700.0]) {
    testWidgets('real detail comment keeps translation button inside at $width',
        (tester) async {
      final comment = GalleryComment(
          id: 1,
          username: 'Reader',
          score: '+3',
          scoreDetails: [],
          content: dom.Element.tag('div')
            ..text = List.filled(60, 'Synthetic preview text.').join(' '),
          time: '2026-01-01 00:00',
          fromMe: false,
          votedUp: false,
          votedDown: false);
      await tester.pumpWidget(GetMaterialApp(
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: width,
                      height: 230,
                      child: EHComment(
                          comment: comment,
                          inDetailPage: true,
                          disableButtons: true))))));
      final card = tester.getRect(find.byType(Card));
      final action = tester.getRect(find.byKey(const Key('translate-text')));
      expect(card.contains(action.topLeft), isTrue);
      expect(card.contains(action.bottomRight), isTrue);
      expect(action.bottom,
          lessThanOrEqualTo(tester.getRect(find.text('+3')).top));
      expect(tester.takeException(), isNull);
    });
  }
}
