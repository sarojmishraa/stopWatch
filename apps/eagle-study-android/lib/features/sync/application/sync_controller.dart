import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/auth_controller.dart';
import '../data/sync_repository.dart';

final syncRepositoryProvider = Provider<SyncRepository>(
  (ref) => SyncRepository(
    ref.watch(studyDatabaseProvider),
    ref.watch(neonAuthClientProvider),
  ),
);

class SyncState {
  const SyncState({
    this.syncing = false,
    this.lastSyncedAt,
    this.lastError,
  });

  final bool syncing;
  final DateTime? lastSyncedAt;
  final String? lastError;

  SyncState copyWith({
    bool? syncing,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncState(
      syncing: syncing ?? this.syncing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);

class SyncController extends Notifier<SyncState> {
  Future<void>? _inFlight;

  @override
  SyncState build() {
    unawaited(_loadLastSync());
    return const SyncState();
  }

  Future<void> _loadLastSync() async {
    try {
      final last = await ref.read(syncRepositoryProvider).lastSyncedAt();
      if (ref.mounted && last != null) {
        state = state.copyWith(lastSyncedAt: last);
      }
    } catch (_) {
      // Ignore if the database was closed during test teardown.
    }
  }

  /// Syncs with the Go + PostgreSQL backend. Coalesces concurrent calls.
  Future<SyncResult?> syncNow() {
    final running = _inFlight;
    if (running != null) return running.then((_) => null);

    final completer = Completer<SyncResult?>();
    _inFlight = completer.future;
    () async {
      if (ref.mounted) {
        state = state.copyWith(syncing: true, clearError: true);
      }
      try {
        final result = await ref.read(syncRepositoryProvider).syncNow();
        if (!ref.mounted) {
          completer.complete(result);
          return;
        }
        if (result != null) {
          state = state.copyWith(
            syncing: false,
            lastSyncedAt: result.syncedAt,
            clearError: true,
          );
          if (result.pushed > 0 || result.pulled > 0) {
            ref.invalidate(studySummaryProvider);
          }
        } else {
          state = state.copyWith(syncing: false);
        }
        completer.complete(result);
      } catch (e) {
        if (ref.mounted) {
          state = state.copyWith(syncing: false, lastError: e.toString());
        }
        completer.complete(null);
      } finally {
        _inFlight = null;
      }
    }();
    return completer.future;
  }

  /// Fire-and-forget sync used after local writes or app resume.
  void syncSilently() {
    unawaited(syncNow());
  }
}
