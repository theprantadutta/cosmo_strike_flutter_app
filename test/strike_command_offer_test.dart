import 'dart:io';

import 'package:cosmo_strike_flutter_app/theme/cosmo_theme.dart';
import 'package:cosmo_strike_flutter_app/utils/title_case.dart';
import 'package:cosmo_strike_flutter_app/widgets/strike_command_offer.dart';
import 'package:flutter_inapp_purchase/flutter_inapp_purchase.dart' as iap;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

iap.SubscriptionOffer _playTrial(String period) => iap.SubscriptionOffer(
      id: 'trial',
      displayPrice: 'Free',
      price: 0,
      type: iap.DiscountOfferType.Introductory,
      pricingPhasesAndroid: iap.PricingPhasesAndroid(pricingPhaseList: [
        iap.PricingPhaseAndroid(
          billingCycleCount: 1,
          billingPeriod: period,
          formattedPrice: 'Free',
          priceAmountMicros: '0',
          priceCurrencyCode: 'BDT',
          recurrenceMode: 2,
        ),
        const iap.PricingPhaseAndroid(
          billingCycleCount: 0,
          billingPeriod: 'P1Y',
          formattedPrice: 'BDT 5,700.00',
          priceAmountMicros: '5700000000',
          priceCurrencyCode: 'BDT',
          recurrenceMode: 1,
        ),
      ]),
    );

const _unifiedWeekTrial = iap.SubscriptionOffer(
  id: 'trial',
  displayPrice: 'Free',
  price: 0,
  type: iap.DiscountOfferType.Introductory,
  paymentMode: iap.PaymentMode.FreeTrial,
  period: iap.SubscriptionPeriod(unit: iap.SubscriptionPeriodUnit.Week, value: 1),
  periodCount: 1,
);

const _quotes = [
  StrikeCommandQuote(plan: StrikeCommandPlan.monthly, price: 'BDT 600.00'),
  StrikeCommandQuote(
    plan: StrikeCommandPlan.annual,
    price: 'BDT 5,700.00',
    trial: FreeTrial(7, FreeTrialUnit.day),
    badge: 'Save 20%',
  ),
];

/// Pumps [child] the way a screen hosts the offer, at [size] logical px.
Future<void> _pump(WidgetTester tester, Widget child, {Size size = const Size(1340, 800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: buildCosmoTheme(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
}

List<String> _texts(WidgetTester tester) => [
      for (final w in tester.widgetList<Text>(find.byType(Text)))
        (w.data ?? w.textSpan?.toPlainText() ?? '').replaceAll('\u00A0', ' ').replaceAll('\u2060', ''),
    ];

void main() {
  group('FreeTrial', () {
    test('Play week phase and unified week offer read the same', () {
      final play = FreeTrial.fromOffers([_playTrial('P1W')]);
      final unified = FreeTrial.fromOffers(const [_unifiedWeekTrial]);
      expect(play, const FreeTrial(7, FreeTrialUnit.day));
      expect(unified, play);
      expect(play!.label, '7-day free trial');
      expect(play.duration, '7 days');
    });

    test('days, months and no offer', () {
      expect(FreeTrial.fromOffers([_playTrial('P3D')])!.label, '3-day free trial');
      expect(FreeTrial.fromOffers([_playTrial('P1M')])!.duration, '1 month');
      expect(FreeTrial.fromOffers(const []), isNull);
      expect(FreeTrial.fromProduct(null), isNull);
    });
  });

  group('StrikeCommandQuote', () {
    test('disclosure uses the localized price and trial length', () {
      expect(_quotes[1].disclosure, 'Free for 7 days, then BDT 5,700.00/yr · cancel anytime');
      expect(_quotes[1].note, '7-day free trial');
      expect(_quotes[0].disclosure, 'BDT 600.00/mo, renews automatically · cancel anytime');
      expect(_quotes[0].note, 'Billed monthly');
    });
  });

  testWidgets('offer renders plans, trial, disclosure and legal links', (tester) async {
    await _pump(tester, StrikeCommandOffer(quotes: _quotes, onSubscribe: (_) {}, onRestore: () {}));
    final texts = _texts(tester);
    expect(texts, contains('7-day free trial'));
    expect(texts, contains('Billed monthly'));
    expect(texts, contains('Free for 7 days, then BDT 5,700.00/yr · cancel anytime'));
    expect(texts, contains('BDT 600.00/mo, renews automatically · cancel anytime'));
    expect(texts, contains('Restore purchases'));
    expect(texts, contains('Terms of Use'));
    expect(texts, contains('Privacy Policy'));
    expect(find.text('SUBSCRIBE'), findsNWidgets(2));
  });

  testWidgets('fine print stays >= 12px on the smallest phone', (tester) async {
    await _pump(
      tester,
      StrikeCommandOffer(quotes: _quotes, onSubscribe: (_) {}, onRestore: () {}),
      size: const Size(640, 360),
    );
    final disclosure = tester.widget<Text>(find.text(_quotes[1].disclosureDisplay));
    expect(disclosure.style!.fontSize, greaterThanOrEqualTo(12));
  });

  testWidgets('feature list never truncates and matches across layouts', (tester) async {
    await _pump(tester, const StrikeCommandFeatureList());
    final oneCol = _texts(tester);
    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      expect(w.maxLines, isNull);
      expect(w.overflow, isNot(TextOverflow.ellipsis));
    }
    await _pump(tester, const StrikeCommandFeatureList(columns: 2, owned: true));
    expect(_texts(tester), oneCol);
    expect(oneCol.any((t) => t.contains('Lucky draw')), isFalse);
    expect(oneCol.any((t) => t.endsWith('premium exhausts')), isTrue);
  });

  test('both Strike Command entry points use the shared offer', () {
    for (final path in ['lib/screens/premium_benefits_screen.dart', 'lib/screens/store_screen.dart']) {
      final src = File(path).readAsStringSync();
      expect(src, contains('StrikeCommandOffer('), reason: path);
      expect(src, contains('StrikeCommandFeatureList('), reason: path);
      expect(src, contains('strikeCommandTagline'), reason: path);
      expect(src.contains('free trial'), isFalse, reason: '$path must not word trials itself');
    }
  });

  test('titleCaseName keeps small words lowercase', () {
    expect(titleCaseName('CITY OF GHOSTS'), 'City of Ghosts');
    expect(titleCaseName('INTO THE HIVE'), 'Into the Hive');
    expect(titleCaseName("QUEEN'S LAIR"), "Queen's Lair");
    expect(titleCaseName('THE LAST STAND'), 'The Last Stand');
    expect(titleCaseName('MOTHERSHIP'), 'Mothership');
  });
}
