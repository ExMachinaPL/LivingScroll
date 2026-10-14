import 'package:flutter_test/flutter_test.dart';
import 'package:living_scroll/l10n/app_localizations_en.dart';
import 'package:living_scroll/l10n/app_localizations_pl.dart';
import 'package:living_scroll/npcs/second_sea/second_sea.dart';
import 'package:living_scroll/npcs/second_sea/second_sea_l10n.dart';

void main() {
  final en = AppLocalizationsEn();
  final pl = AppLocalizationsPl();

  group('field / page labels', () {
    test('English', () {
      expect(seaLabel(en, 'npcSeaPageKind'), 'NPC type');
      expect(seaLabel(en, 'npcSeaPageDetails'), 'Details');
      expect(seaLabel(en, 'statSeaStrength'), 'Strength');
      expect(seaLabel(en, 'statSeaVillainyRank'), 'Villainy Rank');
    });

    test('Polish', () {
      expect(seaLabel(pl, 'statSeaStrength'), 'Siła');
      expect(seaLabel(pl, 'statSeaInfluence'), 'Wpływy');
      expect(seaLabel(pl, 'statSeaVillainyRank'), 'Ranga Nikczemności');
    });
  });

  group('kind labels', () {
    test('every kind resolves to a non-empty label in both locales', () {
      for (final k in SecondSea.kinds) {
        expect(seaKindLabel(en, k), isNotEmpty);
        expect(seaKindLabel(pl, k), isNotEmpty);
      }
      expect(seaKindLabel(en, 'villain'), 'Villain');
      expect(seaKindLabel(en, 'brute_squad'), 'Brutes, Monsters, Allies');
      expect(seaKindLabel(en, 'monster'), 'Story character');
      expect(seaKindLabel(pl, 'villain'), 'Złoczyńca');
      expect(seaKindLabel(pl, 'brute_squad'), 'Łotry, Potwory, Sojusznicy');
      expect(seaKindLabel(pl, 'monster'), 'Postać fabularna');
    });
  });
}
