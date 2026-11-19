// Renders the Directives right column with the real fonts for visual review.
// Run: flutter test test/screenshots --update-goldens --run-skipped
@Tags(['screenshot'])
library;

import 'dart:io';

import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/directives/directives_board.dart';
import 'package:cosmo_strike_flutter_app/widgets/directives/weekly_ops_strip.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
  }
  await loader.load();
}

DailyChallenge _d(String id, String title, String desc, ChallengeType type, ChallengeDifficulty diff,
        int progress, int target, int coins, int xp, {bool claimed = false}) =>
    DailyChallenge(
      id: id,
      title: title,
      description: desc,
      type: type,
      difficulty: diff,
      targetValue: target,
      currentProgress: progress,
      isCompleted: progress >= target,
      claimedReward: claimed,
      coinReward: coins,
      xpReward: xp,
    );

void _noop() {}

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

  final challenges = [
    _d('a', 'Trigger Warmup', 'Destroy 15 hostiles today', ChallengeType.enemiesKilled,
        ChallengeDifficulty.easy, 7, 15, 8, 20),
    _d('b', 'Dodge Ace', 'Stay in the fight for 120 seconds in a single run', ChallengeType.survival,
        ChallengeDifficulty.medium, 120, 120, 15, 35),
    _d('c', 'Combat Tour', 'Fly 10 sorties today', ChallengeType.gamesPlayed, ChallengeDifficulty.hard,
        10, 10, 30, 60, claimed: true),
  ];

  for (final (name, size) in [('phone', Size(832, 384)), ('tablet', Size(1340, 800)), ('small', Size(640, 360))]) {
    testWidgets('directives $name', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        debugShowCheckedModeBanner: false,
        theme: buildCosmoTheme(),
        home: CsScaffold(
          title: 'Directives',
          body: CsSplit(
            left: const ColoredBox(color: CsColors.raised),
            right: DirectivesBoard(
              challenges: challenges,
              onClaim: (_) {},
              onFly: () {},
              weeklyStrip: const WeeklyOpsStrip(
                completed: 2,
                total: 5,
                claimable: 1,
                resetsIn: Duration(days: 3),
                onOpen: _noop,
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2)); // bars fill after mount
      await expectLater(find.byType(CsScaffold), matchesGoldenFile('goldens/directives_$name.png'));
    });
  }
}
