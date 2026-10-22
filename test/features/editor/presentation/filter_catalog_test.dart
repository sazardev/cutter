import 'dart:io';

import 'package:cutter/features/editor/domain/clip.dart';
import 'package:cutter/features/editor/presentation/clip_tools.dart';
import 'package:cutter/l10n/app_localizations_en.dart';
import 'package:cutter/l10n/app_localizations_es.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every filter has a name in each language', () {
    for (final l10n in [AppLocalizationsEn(), AppLocalizationsEs()]) {
      for (final id in filterIds) {
        expect(
          filterLabel(l10n, id),
          isNot(id),
          reason: '$id in ${l10n.localeName}',
        );
      }
    }
  });

  test('the editor lists exactly the filters the engine renders', () {
    final source = File('rust/src/render/effects.rs').readAsStringSync();
    final block = RegExp(r'FILTER_IDS: &\[&str\] = &\[(.*?)\];', dotAll: true)
        .firstMatch(source)!
        .group(1)!;
    final engine = RegExp(r'"(\w+)"').allMatches(block).map((m) => m.group(1)!);
    expect(filterIds, engine.toList());
  });

  test('every animation has a name in each language', () {
    for (final l10n in [AppLocalizationsEn(), AppLocalizationsEs()]) {
      for (final id in clipAnimationIds) {
        expect(
          animationLabel(l10n, id),
          isNot(id),
          reason: '$id in ${l10n.localeName}',
        );
      }
    }
  });

  test('the editor lists exactly the animations the engine renders', () {
    final source = File('rust/src/render/animation.rs').readAsStringSync();
    final block =
        RegExp(r'ANIMATION_IDS: &\[&str\] = &\[(.*?)\];', dotAll: true)
            .firstMatch(source)!
            .group(1)!;
    final engine = RegExp(r'"(\w+)"').allMatches(block).map((m) => m.group(1)!);
    expect(clipAnimationIds, engine.toList());
  });
}
