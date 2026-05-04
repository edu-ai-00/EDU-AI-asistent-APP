import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';

/// Local data source for chat operations using Drift (SQLite).
class ChatLocalDataSource {
  final AppDatabase _db;

  ChatLocalDataSource(this._db);

  // === Watch (reactive streams) ===

  /// Watch all sessions for a user, ordered by most recent.
  Stream<List<ChatSessionsTableData>> watchSessions(String userId) {
    return (_db.select(_db.chatSessionsTable)
          ..where((s) => s.userId.equals(userId))
          ..orderBy([(s) => OrderingTerm.desc(s.lastMessageAt)]))
        .watch();
  }

  /// Watch all messages in a session, ordered chronologically.
  Stream<List<ChatMessagesTableData>> watchMessages(String sessionId) {
    return (_db.select(_db.chatMessagesTable)
          ..where((m) => m.sessionId.equals(sessionId))
          ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
        .watch();
  }

  // === CRUD ===

  Future<void> insertSession(ChatSessionsTableCompanion companion) {
    return _db.into(_db.chatSessionsTable).insert(companion);
  }

  Future<void> insertMessage(ChatMessagesTableCompanion companion) {
    return _db.into(_db.chatMessagesTable).insert(companion);
  }

  /// Update message content (used during SSE streaming to append tokens).
  Future<void> updateMessageContent(String messageId, String content) {
    return (_db.update(_db.chatMessagesTable)
          ..where((m) => m.id.equals(messageId)))
        .write(ChatMessagesTableCompanion(
      content: Value(content),
    ));
  }

  /// Update session fields.
  Future<void> updateSession(String id, ChatSessionsTableCompanion companion) {
    return (_db.update(_db.chatSessionsTable)
          ..where((s) => s.id.equals(id)))
        .write(companion);
  }

  Future<void> updateSessionTitle(String id, String title) {
    return (_db.update(_db.chatSessionsTable)
          ..where((s) => s.id.equals(id)))
        .write(ChatSessionsTableCompanion(title: Value(title)));
  }

  /// Update feedback on a message.
  Future<void> updateMessageFeedback(
      String messageId, String? type, String? detail) {
    return (_db.update(_db.chatMessagesTable)
          ..where((m) => m.id.equals(messageId)))
        .write(ChatMessagesTableCompanion(
      feedbackType: Value(type),
      feedbackDetail: Value(detail),
      syncStatus: const Value('pending'),
    ));
  }

  /// Delete a session and cascade-delete its messages.
  Future<void> deleteSession(String id) async {
    await (_db.delete(_db.chatMessagesTable)
          ..where((m) => m.sessionId.equals(id)))
        .go();
    await (_db.delete(_db.chatSessionsTable)
          ..where((s) => s.id.equals(id)))
        .go();
  }

  // === Lookups ===

  Future<ChatSessionsTableData?> getSessionById(String id) {
    return (_db.select(_db.chatSessionsTable)
          ..where((s) => s.id.equals(id)))
        .getSingleOrNull();
  }

  Future<ChatSessionsTableData?> getSessionByServerId(int serverId) async {
    final results = await (_db.select(_db.chatSessionsTable)
          ..where((s) => s.serverId.equals(serverId))
          ..limit(1))
        .get();
    return results.isEmpty ? null : results.first;
  }

  Future<ChatMessagesTableData?> getMessageByServerId(int serverId) async {
    final results = await (_db.select(_db.chatMessagesTable)
          ..where((m) => m.serverId.equals(serverId))
          ..limit(1))
        .get();
    return results.isEmpty ? null : results.first;
  }

  Future<List<ChatMessagesTableData>> getMessagesBySessionId(
      String sessionId) {
    return (_db.select(_db.chatMessagesTable)
          ..where((m) => m.sessionId.equals(sessionId))
          ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
        .get();
  }

  // === Sync helpers ===

  /// Get messages with pending feedback that needs syncing.
  Future<List<ChatMessagesTableData>> getMessagesWithPendingFeedback() {
    return (_db.select(_db.chatMessagesTable)
          ..where((m) => m.syncStatus.equals('pending')))
        .get();
  }
}
