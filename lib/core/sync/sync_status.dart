/// Represents the synchronization status of a local record.
enum SyncStatus {
  /// Record is synchronized with the server.
  synced,

  /// Record has local changes pending upload.
  pending,

  /// Record has a conflict (server has newer data).
  conflict,
}

/// Extension to convert SyncStatus to/from database int values.
extension SyncStatusExtension on SyncStatus {
  int toInt() {
    switch (this) {
      case SyncStatus.synced:
        return 0;
      case SyncStatus.pending:
        return 1;
      case SyncStatus.conflict:
        return 2;
    }
  }

  static SyncStatus fromInt(int value) {
    switch (value) {
      case 0:
        return SyncStatus.synced;
      case 1:
        return SyncStatus.pending;
      case 2:
        return SyncStatus.conflict;
      default:
        return SyncStatus.synced;
    }
  }
}
