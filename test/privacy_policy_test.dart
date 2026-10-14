import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:living_scroll/l10n/supported_languages.dart';
import 'package:living_scroll/widgets/privacy_policy_dialog.dart';

void main() {
  group('PrivacyPolicy', () {
    test('every published language has a bundled policy asset', () {
      for (final lang in PrivacyPolicy.languages) {
        final file = File(PrivacyPolicy.assetFor(lang));
        expect(file.existsSync(), isTrue, reason: file.path);
        expect(file.readAsStringSync().trim(), isNotEmpty);
      }
    });

    test('UI languages without a translation fall back to English', () {
      for (final lang in SupportedLanguages.names.keys) {
        final expected = PrivacyPolicy.languages.contains(lang) ? lang : 'en';
        expect(PrivacyPolicy.languageFor(lang), expected);
        expect(
          PrivacyPolicy.assetFor(lang),
          'site/legal/privacy-policy.$expected.md',
        );
      }
    });

    test('URLs: English at the site root, others under /<lang>/', () {
      expect(
        PrivacyPolicy.urlFor('en'),
        Uri.parse('https://livingscroll.net/privacy/'),
      );
      expect(
        PrivacyPolicy.urlFor('pl'),
        Uri.parse('https://livingscroll.net/pl/privacy/'),
      );
      expect(PrivacyPolicy.urlFor('ja'), PrivacyPolicy.urlFor('en'));
    });

    test('policy assets are declared in pubspec.yaml', () {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('- site/legal/'),
      );
    });
  });
}
