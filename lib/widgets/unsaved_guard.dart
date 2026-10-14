import 'package:flutter/material.dart';

/// Asks whether the screen that registered it may be LEFT: `true` = go ahead
/// (nothing dirty, or the user chose Save / Abandon in the unsaved-changes
/// prompt), `false` = stay (the user chose Cancel, or a Save was rejected).
/// A guard on a pristine screen must return `true` WITHOUT showing anything.
typedef LeaveGuard = Future<bool> Function();

/// App-wide registry of the isDirty guards of every screen currently on screen,
/// consulted when the APPLICATION is about to close (desktop window close).
///
/// Screens register on mount and unregister on dispose ([UnsavedGuardScope]
/// does both), so the registry mirrors the live screen stack: the most
/// recently registered guard is the TOPMOST screen. [confirmAll] asks them
/// top-down, so the user resolves the form they are looking at first.
class UnsavedGuards {
  UnsavedGuards._();

  static final List<LeaveGuard> _guards = [];

  static void register(LeaveGuard guard) => _guards.add(guard);

  static void unregister(LeaveGuard guard) => _guards.remove(guard);

  /// Number of registered guards (tests).
  static int get length => _guards.length;

  /// Asks every registered guard, topmost first. Returns `false` as soon as one
  /// refuses (the close is cancelled), `true` when all allow leaving.
  static Future<bool> confirmAll() async {
    for (final guard in _guards.reversed.toList()) {
      if (!_guards.contains(guard)) continue; // unregistered meanwhile
      if (!await guard()) return false;
    }
    return true;
  }

  /// Handles an APPLICATION close request (desktop window close): asks every
  /// guard ([confirmAll]) and runs [close] only when all allow it. Returns
  /// whether the app was closed.
  static Future<bool> handleCloseRequest(Future<void> Function() close) async {
    if (_closing) return false; // a close prompt is already open
    _closing = true;
    try {
      if (!await confirmAll()) return false;
      await close();
      return true;
    } finally {
      _closing = false;
    }
  }

  static bool _closing = false;

  /// Resets the registry (tests).
  @visibleForTesting
  static void clear() {
    _guards.clear();
    _closing = false;
  }
}

/// Wraps a screen whose data can be dirty: registers [guard] in
/// [UnsavedGuards] (so closing the app asks it) and intercepts the SYSTEM back
/// action (Android back button / gesture, `Navigator.maybePop`) on this route —
/// the back is held, [guard] decides, and only an allowed leave pops the route
/// ([onLeave] overrides what "leave" does, e.g. exiting the app at the root).
/// Programmatic `Navigator.pop` / `popUntil` are NOT intercepted; callers that
/// navigate in code run their own guard first.
class UnsavedGuardScope extends StatefulWidget {
  const UnsavedGuardScope({
    super.key,
    required this.guard,
    required this.child,
    this.onLeave,
  });

  final LeaveGuard guard;
  final Widget child;

  /// What an allowed system back does. Null => pop this route.
  final VoidCallback? onLeave;

  @override
  State<UnsavedGuardScope> createState() => _UnsavedGuardScopeState();
}

class _UnsavedGuardScopeState extends State<UnsavedGuardScope> {
  bool _busy = false;

  // A stable wrapper so the registry entry survives widget rebuilds that pass
  // a new closure.
  Future<bool> _guard() => widget.guard();

  @override
  void initState() {
    super.initState();
    UnsavedGuards.register(_guard);
  }

  @override
  void dispose() {
    UnsavedGuards.unregister(_guard);
    super.dispose();
  }

  Future<void> _onBack() async {
    if (_busy) return;
    _busy = true;
    try {
      if (!await widget.guard() || !mounted) return;
      if (widget.onLeave != null) {
        widget.onLeave!();
      } else {
        Navigator.of(context).pop();
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: widget.child,
    );
  }
}
