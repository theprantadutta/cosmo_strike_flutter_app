// Renders gameplay overlays with the real fonts to PNGs for visual review.
// Run: flutter test test/screenshots --update-goldens --run-skipped
// Tagged "screenshot" (skipped by default, see dart_test.yaml).
@Tags(['screenshot'])
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:cosmo_strike_flutter_app/game/run_upgrades.dart';
import 'package:cosmo_strike_flutter_app/theme/cosmo_theme.dart';
import 'package:cosmo_strike_flutter_app/widgets/gameplay/upgrade_draft_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFont('Syne', [for (final w in [400, 500, 600, 700, 800]) 'assets/fonts/syne/Syne-$w.ttf']);
    await _loadFont('IBMPlexMono', [
      'assets/fonts/IBMPlexMono-Regular.ttf',
      'assets/fonts/IBMPlexMono-Medium.ttf',
      'assets/fonts/IBMPlexMono-SemiBold.ttf',
    ]);
    final home = Platform.environment['LOCALAPPDATA'] ?? '';
    final symbols = Directory('$home/Pub/Cache/hosted/pub.dev')
        .listSync()
        .whereType<Directory>()
        .lastWhere((d) => d.path.contains('material_symbols_icons-'));
    await _loadFont('packages/material_symbols_icons/MaterialSymbolsRounded',
        ['${symbols.path}/lib/fonts/MaterialSymbolsRounded.ttf']);
  });

  for (final (name, size) in [('phone', Size(832, 384)), ('tablet', Size(1340, 800)), ('small', Size(640, 360))]) {
    testWidgets('upgrade draft $name', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final up = RunUpgrades()
        ..take(UpgradeId.rapidServos)
        ..take(UpgradeId.wingman);
      final options = [
        UpgradeCatalog.byId(UpgradeId.rapidServos),
        UpgradeCatalog.byId(UpgradeId.overcharge),
        UpgradeCatalog.byId(UpgradeId.heavyRounds),
      ];
      expect(up.draft(math.Random(1)).length, 3);
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCosmoTheme(),
        home: Scaffold(
          backgroundColor: CsColors.bgGame,
          body: UpgradeDraftOverlay(options: options, upgrades: up, nextLevel: 3, onPick: (_) {}),
        ),
      ));
      await tester.pump(const Duration(seconds: 2));
      await expectLater(find.byType(UpgradeDraftOverlay), matchesGoldenFile('goldens/draft_$name.png'));
    });
  }
}
