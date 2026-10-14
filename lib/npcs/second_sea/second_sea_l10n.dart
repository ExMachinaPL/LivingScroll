import '../../l10n/app_localizations.dart';

/// Resolves a 2nd Sea template `labelKey` / `titleKey` (a stable string stored in
/// the [SecondSea] template) to its localized text. The form chrome and field
/// labels are localized in EN + PL (other languages fall back to the English
/// placeholder).
String seaLabel(AppLocalizations l, String key) {
  switch (key) {
    // Page titles.
    case 'npcSeaPageKind':
      return l.npcSeaPageKind;
    case 'npcSeaPageDetails':
      return l.npcSeaPageDetails;
    // Field labels.
    case 'npcSeaKindLabel':
      return l.npcSeaKindLabel;
    case 'statSeaStrength':
      return l.statSeaStrength;
    case 'statSeaInfluence':
      return l.statSeaInfluence;
    case 'statSeaVillainyRank':
      return l.statSeaVillainyRank;
    case 'statSeaSchemes':
      return l.statSeaSchemes;
    default:
      return key;
  }
}

/// The localized label of an NPC kind (`villain` / `brute_squad` / `monster`).
String seaKindLabel(AppLocalizations l, String kind) {
  switch (kind) {
    case 'villain':
      return l.npcSeaKindVillain;
    case 'brute_squad':
      return l.npcSeaKindBrute;
    case 'monster':
      return l.npcSeaKindMonster;
    default:
      return kind;
  }
}
