import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/in_app_update_service.dart';
import 'package:cosmo_strike_flutter_app/widgets/play_update_offer_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_analytics_client.dart';

/// The Android update offer: "Update now" hands over to Play's blocking
/// flow (no Restart button to forget); "Later", an outside tap and back
/// snooze. Play's method channel is mocked: it answers the way Play does
/// when the pilot backs out of its update screen.
const _play = MethodChannel('de.ffuf.in_app_update/methods');

void main() {
  late RecordingAnalyticsClient client;
  final playCalls = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    InAppUpdateService().debugReset();
    client = RecordingAnalyticsClient();
    GetIt.I.registerSingleton<AnalyticsFacade>(AnalyticsFacade([client]));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_play, (call) async {
          playCalls.add(call.method);
          throw PlatformException(code: 'USER_DENIED_UPDATE');
        });
  });

  tearDown(() {
    GetIt.I.unregister<AnalyticsFacade>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_play, null);
    playCalls.clear();
  });

  Future<void> open(WidgetTester tester) async {
    // A landscape phone (the 960x432 design frame).
    tester.view.physicalSize = const Size(960, 432);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showPlayUpdateOfferDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  List<Map<String, Object>> updates() => client.named('app_update');
  List<String> stages() => [for (final e in updates()) e['stage'] as String];

  Future<int?> declinedAt() async =>
      (await SharedPreferences.getInstance()).getInt(InAppUpdateService.kDeclinedAtMs);

  testWidgets('shows the offer and logs it', (tester) async {
    await open(tester);
    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('restarts the game by itself'), findsOneWidget);
    expect(find.text('UPDATE NOW'), findsOneWidget);
    expect(find.text('LATER'), findsOneWidget);
    expect(stages(), ['offered']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Later closes, snoozes and never touches Play', (tester) async {
    await open(tester);
    await tester.tap(find.text('LATER'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    expect(stages(), ['offered', 'snoozed']);
    expect(await declinedAt(), isNotNull);
    expect(playCalls, isEmpty);
  });

  testWidgets('tapping outside counts as Later', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    expect(stages(), ['offered', 'snoozed']);
    expect(await declinedAt(), isNotNull);
  });

  testWidgets('back counts as Later', (tester) async {
    await open(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    expect(stages(), ['offered', 'snoozed']);
  });

  testWidgets("Update now hands over to Play's blocking flow; backing out "
      "of Play's screen snoozes like Later", (tester) async {
    await open(tester);
    await tester.tap(find.text('UPDATE NOW'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
    expect(playCalls, ['performImmediateUpdate']);
    expect(stages(), ['offered', 'accepted', 'immediate_result']);
    expect(updates().last['result'], 'userDeniedUpdate');
    expect(await declinedAt(), isNotNull);
    expect(InAppUpdateService().offerPending, isFalse);
  });
}
