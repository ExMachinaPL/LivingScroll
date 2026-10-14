import 'package:flutter_test/flutter_test.dart';
import 'package:living_scroll/create/cover_crop.dart';
import 'package:living_scroll/create/game_systems.dart';
import 'package:living_scroll/npcs/npcs_controller.dart';
import 'package:living_scroll/npcs/second_sea/second_sea.dart';
import 'package:living_scroll/npcs/stat_template.dart';

/// A controller bound to the 2nd Sea system, with images staged so [canSave]
/// passes. Returns it mid-edit of a fresh NPC.
NpcsController _editing({required String kind, String name = 'Nemo'}) {
  final c = NpcsController(newId: () => 'new-uuid');
  c.setTemplate(SecondSea.template,
      systemId: SecondSea.systemId, pruneHiddenStats: true);
  c.loadFrom({'npcs': []});
  c.beginNew();
  c.editName = name;
  c.stageFull('/tmp/full.png');
  c.stageIcon(const CoverCrop(left: 0, top: 0, width: 1, height: 0.7));
  c.setStat('kind', kind);
  return c;
}

Map<String, dynamic> _savedStats(NpcsController c) {
  expect(c.save(), isTrue);
  return Map<String, dynamic>.from(c.toJson().first['stats'] as Map);
}

void main() {
  group('SecondSea model', () {
    test('system identity', () {
      expect(SecondSea.systemId, '2ndsea');
      expect(SecondSea.systemName, '2nd Sea');
      expect(SecondSea.kinds, ['villain', 'brute_squad', 'monster']);
    });

    test('villainy rank = strength + AVAILABLE influence', () {
      expect(SecondSea.villainyRank({'strength': 5, 'influence': 3}), 8);
      expect(SecondSea.villainyRank({'strength': 7}), 7); // missing influence -> 0
      expect(SecondSea.villainyRank(const {}), 0);
      expect(SecondSea.derive('villainy_rank', {'strength': 2, 'influence': 9}), 11);
    });

    test('villainy rank is recalculated when influence is invested in schemes', () {
      final stats = {
        'strength': 6,
        'influence': 10,
        'schemes': [
          {'type': 'scheme', 'name': 'A', 'cost': 4},
          {'type': 'scheme', 'name': 'B', 'cost': 3},
        ],
      };
      // 6 + (10 - 7) = 9, not 6 + 10.
      expect(SecondSea.villainyRank(stats), 9);
      expect(SecondSea.derive('villainy_rank', stats), 9);
      // Rank == strength + available influence, always.
      expect(SecondSea.villainyRank(stats),
          6 + SecondSea.availableInfluence(stats));
    });

    test('3-digit numeric bound', () {
      expect(SecondSea.statDigits, 3);
      expect(SecondSea.statMax, 999);
    });
  });

  group('schemes / intrygi', () {
    Map<String, dynamic> statsWith(List<Map<String, dynamic>> schemes,
            {int influence = 10}) =>
        {
          'kind': 'villain',
          'strength': 5,
          'influence': influence,
          'schemes': schemes,
        };

    test('scheme types', () {
      expect(SecondSea.schemeTypeScheme, 'scheme');
      expect(SecondSea.schemeTypeCost, 'cost');
      expect(SecondSea.schemeTypes, ['scheme', 'cost']);
    });

    test('schemes() reads the list; empty when absent/invalid', () {
      expect(SecondSea.schemes(const {}), isEmpty);
      expect(SecondSea.schemes({'schemes': 'nope'}), isEmpty);
      final list = SecondSea.schemes(statsWith([
        {'type': 'scheme', 'name': 'A', 'cost': 3}
      ]));
      expect(list, hasLength(1));
      expect(list.first['name'], 'A');
    });

    test('cost total sums every scheme cost', () {
      expect(
          SecondSea.schemeCostTotal(statsWith([
            {'type': 'scheme', 'name': 'A', 'cost': 3},
            {'type': 'scheme', 'name': 'B', 'cost': 4},
          ])),
          7);
      expect(SecondSea.schemeCostTotal(statsWith(const [])), 0);
    });

    test('available influence = influence − committed costs', () {
      final s = statsWith(influence: 10, [
        {'type': 'scheme', 'name': 'A', 'cost': 3},
        {'type': 'scheme', 'name': 'B', 'cost': 4},
      ]);
      expect(SecondSea.availableInfluence(s), 3); // 10 - 7
      // Editing index 1 frees its own cost from the budget.
      expect(SecondSea.availableInfluence(s, excludeIndex: 1), 7); // 10 - 3
      expect(SecondSea.availableInfluence(s, excludeIndex: 0), 6); // 10 - 4
    });

    test('template: schemes is a villain-only list field of {type,name,cost}', () {
      final f = SecondSea.template.fieldFor('schemes')!;
      expect(f.type, StatType.list);
      expect(f.showWhen!.matches({'kind': 'villain'}), isTrue);
      expect(f.showWhen!.matches({'kind': 'monster'}), isFalse);
      expect(f.item.map((s) => s.key), ['type', 'name', 'cost']);
      expect(f.item.firstWhere((s) => s.key == 'name').required, isTrue);
      expect(f.item.firstWhere((s) => s.key == 'cost').required, isTrue);
    });

    test('save keeps schemes for a Villain, prunes them for other kinds', () {
      final villain = _editing(kind: 'villain');
      villain.setStat('influence', 10);
      villain.setStat('schemes', [
        {'type': 'scheme', 'name': 'Plot', 'cost': 4}
      ]);
      final vStats = _savedStats(villain);
      expect(vStats['schemes'], [
        {'type': 'scheme', 'name': 'Plot', 'cost': 4}
      ]);

      // A Brute has no influence/schemes -> both pruned.
      final brute = _editing(kind: 'brute_squad');
      brute.setStat('schemes', [
        {'type': 'scheme', 'name': 'X', 'cost': 1}
      ]);
      expect(_savedStats(brute).containsKey('schemes'), isFalse);
    });
  });

  group('template', () {
    final t = SecondSea.template;

    test('two pages: kind then details', () {
      expect(t.pages.length, 2);
      expect(t.pages[0].key, 'npc.2ndsea.page.kind');
      expect(t.pages[1].key, 'npc.2ndsea.page.details');
    });

    test('kind field defaults to villain and is required', () {
      final kind = t.fieldFor('kind')!;
      expect(kind.type, StatType.enumField);
      expect(kind.options, SecondSea.kinds);
      expect(kind.defaultValue, 'villain');
      expect(kind.required, isTrue);
      expect(kind.showWhen, isNull); // always present (the discriminator)
    });

    test('strength shows for villain + brute, influence for villain only', () {
      final strength = t.fieldFor('strength')!;
      expect(strength.max, 999);
      expect(strength.showWhen!.matches({'kind': 'villain'}), isTrue);
      expect(strength.showWhen!.matches({'kind': 'brute_squad'}), isTrue);
      expect(strength.showWhen!.matches({'kind': 'monster'}), isFalse);

      final influence = t.fieldFor('influence')!;
      expect(influence.showWhen!.matches({'kind': 'villain'}), isTrue);
      expect(influence.showWhen!.matches({'kind': 'brute_squad'}), isFalse);
    });

    test('villainy_rank is derived (never a plain input)', () {
      final rank = t.fieldFor('villainy_rank')!;
      expect(rank.isDerived, isTrue);
      expect(rank.derived, 'villainy_rank');
      expect(rank.showWhen!.matches({'kind': 'villain'}), isTrue);
    });

    test('there is NO advantages field (removed from the 2nd Sea template)', () {
      expect(t.fieldFor('advantages'), isNull);
    });
  });

  group('validation', () {
    test('a valid villain stats map passes', () {
      final errors = validateStats(SecondSea.template, {
        'kind': 'villain',
        'strength': 5,
        'influence': 4,
      });
      expect(errors, isEmpty);
    });

    test('a legacy stored advantages list is ignored (still valid)', () {
      final errors = validateStats(SecondSea.template, {
        'kind': 'villain',
        'strength': 5,
        'influence': 4,
        'advantages': ['sorcery', 'not_a_real_advantage'],
      });
      expect(errors, isEmpty);
    });
  });

  group('save prunes stats to the chosen kind', () {
    test('monster stores only its kind (no strength/influence)', () {
      final stats = _savedStats(_editing(kind: 'monster'));
      expect(stats, {'kind': 'monster'});
    });

    test('brute squad stores kind + strength only', () {
      final c = _editing(kind: 'brute_squad')..setStat('strength', 8);
      final stats = _savedStats(c);
      expect(stats, {'kind': 'brute_squad', 'strength': 8});
    });

    test('villain stores kind + strength + influence + schemes, not rank', () {
      final c = _editing(kind: 'villain')
        ..setStat('strength', 6)
        ..setStat('influence', 3);
      final stats = _savedStats(c);
      expect(stats, {
        'kind': 'villain',
        'strength': 6,
        'influence': 3,
        'schemes': <Map<String, dynamic>>[], // present (empty) for a villain
      });
      expect(stats.containsKey('villainy_rank'), isFalse); // derived, never stored
    });

    test('a legacy villain\'s stored advantages are DROPPED on the next save',
        () {
      final c = NpcsController(newId: () => 'new-uuid');
      c.setTemplate(SecondSea.template,
          systemId: SecondSea.systemId, pruneHiddenStats: true);
      c.loadFrom({
        'npcs': [
          {
            'npc_uuid': 'v1',
            'name': 'Old villain',
            'full_image': 'full-1',
            'icon_image': 'icon-1',
            'stats': {
              'kind': 'villain',
              'strength': 2,
              'influence': 1,
              'advantages': ['sorcery'],
            },
          },
        ],
      });
      c.beginEdit('v1');
      c.editName = 'Old villain (edited)';
      final stats = _savedStats(c);
      expect(stats.containsKey('advantages'), isFalse);
      expect(stats['strength'], 2);
      expect(stats['influence'], 1);
    });
  });

  group('GameSystems registration', () {
    test('2nd Sea is a supported, selectable system', () {
      expect(GameSystems.ids, contains('2ndsea'));
      expect(GameSystems.names['2ndsea'], '2nd Sea');
      expect(GameSystems.templateFor('2ndsea'), same(SecondSea.template));
      expect(GameSystems.pruneHiddenStatsFor('2ndsea'), isTrue);
      expect(GameSystems.pruneHiddenStatsFor('basic'), isFalse);
    });
  });
}
