// PATH: Home -> Settings -> Privacy policy -> Open in browser -> OK
// EFFECT: none — the dialog shows the BUNDLED policy (site/legal/*.md, the same
// file the website publishes); Open in browser launches the online copy.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:living_scroll/widgets/privacy_policy_dialog.dart';

import 'support/settings_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const urlEn = 'https://livingscroll.net/privacy/';
  const urlPl = 'https://livingscroll.net/pl/privacy/';
  // ENV locale: en — pinned via the lang stub so the test does not depend on
  // the machine's system locale (no lang stub = follow the system).
  const pinnedEn = '{"lang": "en"}';

  // MOCKS: url_launcher — capture the launched URIs instead of opening a
  // browser; [result] is what the "launch" reports.
  late List<Uri> launched;
  late Future<bool> Function(Uri) originalOpenUrl;

  setUp(() {
    launched = [];
    originalOpenUrl = PrivacyPolicy.openUrl;
  });
  tearDown(() => PrivacyPolicy.openUrl = originalOpenUrl);

  void mockLauncher({required bool result}) {
    PrivacyPolicy.openUrl = (url) async {
      launched.add(url);
      return result;
    };
  }

  String bodyData(WidgetTester tester) => tester
      .widget<Markdown>(
        find.byKey(const ValueKey('settings.privacy.dialog.body')),
      )
      .data;

  Future<void> openPolicy(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('nav.settings')));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('settings.privacy.policy'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('settings_privacy_policy: bundled policy, open in browser, OK', (
    tester,
  ) async {
    final harness = SettingsHarness();
    await harness.setUp();
    addTearDown(harness.tearDown);
    mockLauncher(result: true);

    // FIXTURES: UI language pinned to en (the system locale may differ).
    await harness.overridesFile.writeAsString(pinnedEn);
    await harness.pumpApp(tester);

    // STEP 1 + 2 — Settings > Privacy policy shows the bundled English policy.
    await openPolicy(tester);
    expect(
      find.byKey(const ValueKey('settings.privacy.dialog')),
      findsOneWidget,
    );
    expect(
      bodyData(tester),
      File('site/legal/privacy-policy.en.md').readAsStringSync(),
    );
    expect(harness.snapshot(), pinnedEn);

    // STEP 3 — Open in browser launches the English URL; the dialog stays.
    await tester.tap(
      find.byKey(const ValueKey('settings.privacy.dialog.open')),
    );
    await tester.pumpAndSettle();
    expect(launched, [Uri.parse(urlEn)]);
    expect(
      find.byKey(const ValueKey('settings.privacy.dialog')),
      findsOneWidget,
    );

    // STEP 4 — OK closes; nothing written.
    await tester.tap(find.byKey(const ValueKey('settings.privacy.dialog.ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings.privacy.dialog')), findsNothing);
    expect(harness.snapshot(), pinnedEn);
  });

  testWidgets('BRANCH polish_ui: Polish policy and Polish URL', (tester) async {
    final harness = SettingsHarness();
    await harness.setUp();
    addTearDown(harness.tearDown);
    mockLauncher(result: true);

    await harness.overridesFile.writeAsString('{"lang": "pl"}');
    await harness.pumpApp(tester);

    await openPolicy(tester);
    expect(
      bodyData(tester),
      File('site/legal/privacy-policy.pl.md').readAsStringSync(),
    );
    await tester.tap(
      find.byKey(const ValueKey('settings.privacy.dialog.open')),
    );
    await tester.pumpAndSettle();
    expect(launched, [Uri.parse(urlPl)]);
  });

  testWidgets('BRANCH browser_unavailable: SnackBar shows the URL', (
    tester,
  ) async {
    final harness = SettingsHarness();
    await harness.setUp();
    addTearDown(harness.tearDown);
    mockLauncher(result: false);

    await harness.overridesFile.writeAsString(pinnedEn);
    await harness.pumpApp(tester);

    await openPolicy(tester);
    await tester.tap(
      find.byKey(const ValueKey('settings.privacy.dialog.open')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining(urlEn),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings.privacy.dialog')),
      findsOneWidget,
    );
  });
}
