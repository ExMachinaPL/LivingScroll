import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:living_scroll/widgets/unsaved_guard.dart';

/// The app-wide isDirty guard registry consulted on application close.
void main() {
  setUp(UnsavedGuards.clear);

  test('no guards -> the close proceeds', () async {
    var closed = 0;
    expect(
      await UnsavedGuards.handleCloseRequest(() async => closed++),
      isTrue,
    );
    expect(closed, 1);
  });

  test('guards are asked TOPMOST first; a refusal cancels the close', () async {
    final asked = <String>[];
    UnsavedGuards.register(() async {
      asked.add('bottom');
      return true;
    });
    UnsavedGuards.register(() async {
      asked.add('top');
      return false;
    });
    var closed = 0;
    expect(
      await UnsavedGuards.handleCloseRequest(() async => closed++),
      isFalse,
    );
    expect(asked, ['top'], reason: 'stops at the first refusal');
    expect(closed, 0);
  });

  test('all guards allow -> every one is asked, then the close runs', () async {
    final asked = <String>[];
    UnsavedGuards.register(() async {
      asked.add('bottom');
      return true;
    });
    UnsavedGuards.register(() async {
      asked.add('top');
      return true;
    });
    var closed = 0;
    expect(
      await UnsavedGuards.handleCloseRequest(() async => closed++),
      isTrue,
    );
    expect(asked, ['top', 'bottom']);
    expect(closed, 1);
  });

  test('a second close request while a prompt is open is ignored', () async {
    final gate = Completer<bool>();
    UnsavedGuards.register(() => gate.future);
    var closed = 0;
    final first = UnsavedGuards.handleCloseRequest(() async => closed++);
    expect(
      await UnsavedGuards.handleCloseRequest(() async => closed++),
      isFalse,
    );
    gate.complete(true);
    expect(await first, isTrue);
    expect(closed, 1);
  });

  testWidgets('UnsavedGuardScope registers while mounted and holds the '
      'system back until its guard allows it', (tester) async {
    var allow = false;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: nav, home: const Text('base')),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => UnsavedGuardScope(
          guard: () async => allow,
          child: const Text('guarded'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(UnsavedGuards.length, 1);

    // ignore: invalid_use_of_protected_member
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('guarded'), findsOneWidget, reason: 'guard refused');

    allow = true;
    // ignore: invalid_use_of_protected_member
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('guarded'), findsNothing);
    expect(find.text('base'), findsOneWidget);
    expect(UnsavedGuards.length, 0, reason: 'unregistered on dispose');
  });
}
