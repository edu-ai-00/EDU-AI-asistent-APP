import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Types of sync operations.
enum SyncOperation {
  create,
  update,
  delete,
}

/// Extension to convert SyncOperation to/from string.
extension SyncOperationExtension on SyncOperation {
  String toValue() {
    switch (this) {
      case SyncOperation.create:
        return 'create';
      case SyncOperation.update:
        return 'update';
      case SyncOperation.delete:
        return 'delete';
    }
  }

  static SyncOperation fromValue(String value) {
    switch (value) {
      case 'create':
        return SyncOperation.create;
      case 'update':
        return SyncOperation.update;
      case 'delete':
        return SyncOperation.delete;
      default:
        throw ArgumentError('Unknown operation: $value');
    }
  }
}

/// Manages the offline sync queue.
///
/// When a local change is made while offline, it's added to the queue.
/// When connectivity is restored, the queue is processed.
class SyncQueue {
  final AppDatabase _db;

  /// Maximum number of retries before giving up on an operation.
  static const int maxRetries = 5;

  /// Base delay for exponential backoff (in seconds).
  static const int baseRetryDelaySeconds = 60;

  SyncQueue(this._db);

  /// Add an operation to the sync queue.
  Future<int> enqueue({
    required String tableName,
    required String recordId,
    required SyncOperation operation,
    required Map<String, dynamic> payload,
    int priority = 0,
  }) async {
    // Check if there's already a pending operation for this record.
    final existing = await _getExistingOperation(tableName, recordId);

    if (existing != null) {
      // Merge operations: delete supersedes create/update.
      if (operation == SyncOperation.delete) {
        // If there's a create that hasn't synced, just remove it entirely.
        if (existing.operation == 'create') {
          await _db.removeSyncQueueEntry(existing.id);
          return -1; // No need to sync a record that was never on server.
        }
        // Otherwise, replace with delete.
        await _db.removeSyncQueueEntry(existing.id);
      } else if (operation == SyncOperation.update &&
          existing.operation == 'create') {
        // Keep as create, but merge the payload (new keys override old).
        final existingPayload =
            jsonDecode(existing.payload) as Map<String, dynamic>;
        final mergedPayload = {...existingPayload, ...payload};
        await _db.updateSyncQueueEntry(
          existing.id,
          SyncQueueTableCompanion(
            payload: Value(jsonEncode(mergedPayload)),
            scheduledAt: Value(DateTime.now()),
          ),
        );
        return existing.id;
      } else {
        // Both are updates — merge payloads (new keys override old).
        final existingPayload =
            jsonDecode(existing.payload) as Map<String, dynamic>;
        final mergedPayload = {...existingPayload, ...payload};
        await _db.updateSyncQueueEntry(
          existing.id,
          SyncQueueTableCompanion(
            payload: Value(jsonEncode(mergedPayload)),
            scheduledAt: Value(DateTime.now()),
          ),
        );
        return existing.id;
      }
    }

    return _db.addToSyncQueue(
      SyncQueueTableCompanion(
        tableName_: Value(tableName),
        recordId: Value(recordId),
        operation: Value(operation.toValue()),
        payload: Value(jsonEncode(payload)),
        priority: Value(priority),
        scheduledAt: Value(DateTime.now()),
      ),
    );
  }

  /// Get an existing operation for a record.
  Future<SyncQueueTableData?> _getExistingOperation(
    String tableName,
    String recordId,
  ) async {
    final operations = await _db.getPendingSyncOperations(limit: 1000);
    try {
      return operations.firstWhere(
        (op) => op.tableName_ == tableName && op.recordId == recordId,
      );
    } catch (_) {
      return null;
    }
  }

  /// Get all pending operations.
  Future<List<SyncQueueTableData>> getPendingOperations({int limit = 50}) {
    return _db.getPendingSyncOperations(limit: limit);
  }

  /// Get count of pending operations.
  Future<int> getPendingCount() {
    return _db.getPendingSyncCount();
  }

  /// Mark an operation as successfully synced (removes from queue).
  Future<void> markSynced(int id) async {
    await _db.removeSyncQueueEntry(id);
  }

  /// Mark an operation as failed and schedule retry.
  Future<void> markFailed(int id, String error) async {
    final operations = await _db.getPendingSyncOperations(limit: 1000);
    final operation = operations.where((op) => op.id == id).firstOrNull;

    if (operation == null) return;

    final newRetryCount = operation.retryCount + 1;

    if (newRetryCount >= maxRetries) {
      // Give up — remove from queue entirely.
      // The SyncService._cleanupDeadEntries() handles resetting local
      // syncStatus, but in case markFailed is called directly, just delete.
      await _db.removeSyncQueueEntry(id);
      return;
    } else {
      // Exponential backoff.
      final delaySeconds = baseRetryDelaySeconds * (1 << newRetryCount);
      final nextAttempt = DateTime.now().add(Duration(seconds: delaySeconds));

      await _db.updateSyncQueueEntry(
        id,
        SyncQueueTableCompanion(
          retryCount: Value(newRetryCount),
          lastError: Value(error),
          scheduledAt: Value(nextAttempt),
        ),
      );
    }
  }

  /// Clear all pending operations for a specific record.
  Future<void> clearForRecord(String tableName, String recordId) {
    return _db.clearSyncQueueForRecord(tableName, recordId);
  }

  /// Check if there are any pending operations.
  Future<bool> hasPendingOperations() async {
    final count = await getPendingCount();
    return count > 0;
  }
}
