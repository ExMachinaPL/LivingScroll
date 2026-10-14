import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

/// The privacy policy: ONE source shared with the project website. The app
/// bundles `site/legal/privacy-policy.<lang>.md` as assets (pubspec.yaml) — the
/// SAME files the website's Pages workflow renders to [urlFor] — so every build
/// carries the current text and shows it offline.
class PrivacyPolicy {
  PrivacyPolicy._();

  /// Languages the policy is published in; any other UI language falls back
  /// to English.
  static const List<String> languages = ['en', 'pl'];

  /// The policy language for a UI [languageCode].
  static String languageFor(String languageCode) =>
      languages.contains(languageCode) ? languageCode : 'en';

  /// Bundled asset holding the policy text in [lang].
  static String assetFor(String lang) =>
      'site/legal/privacy-policy.${languageFor(lang)}.md';

  /// Public URL of the policy in [lang] (English at the site root, other
  /// languages under `/<lang>/`). The English URL is the one registered in
  /// Google Play Console — keep it stable.
  static Uri urlFor(String lang) {
    final code = languageFor(lang);
    return Uri.parse(
      code == 'en'
          ? 'https://livingscroll.net/privacy/'
          : 'https://livingscroll.net/$code/privacy/',
    );
  }

  /// Opens [url] in the system browser. Overridable so tests can capture the
  /// launch instead of starting a real browser.
  @visibleForTesting
  static Future<bool> Function(Uri url) openUrl = (url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
}

/// Shows the privacy policy in a read-only dialog sized like the shared detail
/// dialog (80% of the window height, ISO format-A width = height / √2): the
/// bundled Markdown policy in the UI language (English fallback), scrollable,
/// with **Open in browser** (the online copy) and **OK** grouped at the end of
/// the button row. Links inside the policy open in the system browser too.
///
/// Keys: `settings.privacy.dialog` (sized box), `.body` (Markdown), `.open`
/// and `.ok` (buttons).
Future<void> showPrivacyPolicyDialog(BuildContext context) {
  final windowSize = MediaQuery.sizeOf(context);
  final height = windowSize.height * 0.8;
  // Format A short:long = 1 : √2; the height is the long edge.
  final width = math.min(height / math.sqrt2, windowSize.width - 48);
  final lang = Localizations.localeOf(context).languageCode;
  final policy = rootBundle.loadString(PrivacyPolicy.assetFor(lang));

  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);

      Future<void> open(Uri url) async {
        final messenger = ScaffoldMessenger.maybeOf(ctx);
        var opened = false;
        try {
          opened = await PrivacyPolicy.openUrl(url);
        } catch (_) {
          opened = false;
        }
        if (!opened) {
          messenger?.showSnackBar(
            SnackBar(content: Text(l10n.privacyPolicyOpenFailed('$url'))),
          );
        }
      }

      return Dialog(
        child: SizedBox(
          key: const ValueKey('settings.privacy.dialog'),
          height: height,
          width: width,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: FutureBuilder<String>(
                    future: policy,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return Markdown(
                        key: const ValueKey('settings.privacy.dialog.body'),
                        data: snapshot.data!,
                        padding: EdgeInsets.zero,
                        onTapLink: (text, href, title) {
                          final url = href == null ? null : Uri.tryParse(href);
                          if (url != null) open(url);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('settings.privacy.dialog.open'),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(l10n.privacyPolicyOpenInBrowser),
                      onPressed: () => open(PrivacyPolicy.urlFor(lang)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('settings.privacy.dialog.ok'),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(l10n.dialogOk),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
