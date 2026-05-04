import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/connectivity/connectivity_service.dart';
import '../../core/database/app_database.dart';
import '../../core/sync/sync_queue.dart';
import '../../models/chat_models.dart';
import '../datasources/local/chat_local_datasource.dart';
import '../datasources/remote/chat_remote_datasource.dart';

/// Repository for chat operations.
/// Uses server-first pattern for messages (requires internet),
/// SyncQueue for feedback only.
class ChatRepository {
  final ChatLocalDataSource _local;
  final ChatRemoteDataSource _remote;
  final ConnectivityService _connectivity;
  final SyncQueue _syncQueue;

  ChatRepository({
    required ChatLocalDataSource localDataSource,
    required ChatRemoteDataSource remoteDataSource,
    required ConnectivityService connectivity,
    required SyncQueue syncQueue,
  })  : _local = localDataSource,
        _remote = remoteDataSource,
        _connectivity = connectivity,
        _syncQueue = syncQueue;

  // === Reactive streams (from local cache) ===

  Stream<List<ChatSessionsTableData>> watchSessions(String userId) =>
      _local.watchSessions(userId);

  Stream<List<ChatMessagesTableData>> watchMessages(String sessionId) =>
      _local.watchMessages(sessionId);

  // === Create session (server-first) ===

  Future<ChatSessionsTableData> createSession(
      String userId, ChatPersona persona) async {
    if (!await _connectivity.isOnline) {
      throw Exception('Requires internet');
    }

    final result = await _remote.createSession(persona: persona.id);
    if (result.isFailure) throw Exception(result.error);

    final serverData = result.data!;
    // API wraps in 'data' key
    final data =
        serverData.containsKey('data') ? serverData['data'] as Map<String, dynamic> : serverData;
    final localId = const Uuid().v4();

    await _local.insertSession(ChatSessionsTableCompanion(
      id: Value(localId),
      userId: Value(userId),
      serverId: Value(data['id'] as int),
      title: Value(data['title'] as String? ?? ''),
      persona: Value(persona.id),
      syncStatus: const Value('synced'),
    ));

    return (await _local.getSessionById(localId))!;
  }

  // === Send message (server-first + SSE) ===

  Stream<ChatStreamEvent> sendMessage(
      String sessionId, String content) async* {
    if (!await _connectivity.isOnline) {
      yield ChatStreamError('Requires internet');
      return;
    }

    final session = await _local.getSessionById(sessionId);
    if (session == null || session.serverId == null) {
      yield ChatStreamError('Session not found');
      return;
    }

    // Step 1: POST message -> get both IDs
    final result = await _remote.sendMessage(session.serverId!, content);
    if (result.isFailure) {
      yield ChatStreamError(result.error ?? 'Failed to send');
      return;
    }

    final responseData = result.data!;
    final data = responseData.containsKey('data')
        ? responseData['data'] as Map<String, dynamic>
        : responseData;
    final userMsgData = data['user_message'] as Map<String, dynamic>;
    final assistantMsgData = data['assistant_message'] as Map<String, dynamic>;

    // Insert user message locally
    await _local.insertMessage(ChatMessagesTableCompanion(
      id: Value(const Uuid().v4()),
      sessionId: Value(sessionId),
      serverId: Value(userMsgData['id'] as int),
      role: const Value('user'),
      content: Value(content),
      syncStatus: const Value('synced'),
    ));

    // Insert empty assistant message locally (placeholder for streaming)
    final assistantLocalId = const Uuid().v4();
    await _local.insertMessage(ChatMessagesTableCompanion(
      id: Value(assistantLocalId),
      sessionId: Value(sessionId),
      serverId: Value(assistantMsgData['id'] as int),
      role: const Value('assistant'),
      content: const Value(''),
      syncStatus: const Value('synced'),
    ));

    // Update session lastMessageAt
    await _local.updateSession(
      sessionId,
      ChatSessionsTableCompanion(
        lastMessageAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // Step 2: Open SSE stream
    String fullContent = '';
    try {
      await for (final token in _remote.streamResponse(
        session.serverId!,
        assistantMsgData['id'] as int,
      )) {
        fullContent += token;
        await _local.updateMessageContent(assistantLocalId, fullContent);
        yield ChatStreamToken(token);
      }
      yield ChatStreamDone(fullContent, assistantMsgData['id'] as int);
    } catch (e) {
      if (fullContent.isNotEmpty) {
        await _local.updateMessageContent(assistantLocalId, fullContent);
      }
      yield ChatStreamError(e.toString());
    }
  }

  // === Feedback (SyncQueue for offline resilience) ===

  Future<void> submitFeedback(
      String messageId, String? type, String? detail) async {
    // Update locally first (immediate UI update)
    await _local.updateMessageFeedback(messageId, type, detail);

    // Enqueue sync
    await _syncQueue.enqueue(
      tableName: 'chat_messages',
      recordId: messageId,
      operation: SyncOperation.update,
      payload: {'feedback_type': type, 'feedback_detail': detail},
    );
  }

  // === Delete session ===

  Future<void> deleteSession(String sessionId) async {
    final session = await _local.getSessionById(sessionId);

    if (session?.serverId != null) {
      if (await _connectivity.isOnline) {
        try {
          await _remote.deleteSession(session!.serverId!);
        } catch (_) {
          // If server delete fails, still delete locally and queue
          await _syncQueue.enqueue(
            tableName: 'chat_sessions',
            recordId: sessionId,
            operation: SyncOperation.delete,
            payload: {'server_id': session!.serverId},
          );
        }
      } else {
        await _syncQueue.enqueue(
          tableName: 'chat_sessions',
          recordId: sessionId,
          operation: SyncOperation.delete,
          payload: {'server_id': session!.serverId},
        );
      }
    }

    await _local.deleteSession(sessionId);
  }

  // === Pull history (called by SyncService) ===

  Future<void> pullHistory(String userId, {String? since}) async {
    // Pull sessions
    final sessResult = await _remote.fetchSessions(since: since);
    if (sessResult.isSuccess && sessResult.data != null) {
      final sessions = sessResult.data!;
      for (final item in sessions) {
        final s = item as Map<String, dynamic>;
        final existing = await _local.getSessionByServerId(s['id'] as int);
        if (existing == null) {
          await _local.insertSession(ChatSessionsTableCompanion(
            id: Value(const Uuid().v4()),
            userId: Value(userId),
            serverId: Value(s['id'] as int),
            title: Value(s['title'] as String? ?? ''),
            persona: Value(s['persona'] as String? ?? 'ai_teacher'),
            lastMessageAt: Value(DateTime.parse(s['last_message_at'] as String)),
            syncStatus: const Value('synced'),
          ));
        } else {
          // Update title and last_message_at if server has newer data
          final serverTitle = s['title'] as String? ?? '';
          if (serverTitle.isNotEmpty && serverTitle != existing.title) {
            await _local.updateSessionTitle(existing.id, serverTitle);
          }
        }
      }
    }

    // Pull messages (single endpoint, all sessions)
    final msgResult = await _remote.fetchAllMessages(since: since);
    if (msgResult.isSuccess && msgResult.data != null) {
      final messages = msgResult.data!;
      for (final item in messages) {
        final m = item as Map<String, dynamic>;
        final existing = await _local.getMessageByServerId(m['id'] as int);
        if (existing == null) {
          final localSession =
              await _local.getSessionByServerId(m['chat_session_id'] as int);
          if (localSession == null) continue; // orphan message, skip

          await _local.insertMessage(ChatMessagesTableCompanion(
            id: Value(const Uuid().v4()),
            sessionId: Value(localSession.id),
            serverId: Value(m['id'] as int),
            role: Value(m['role'] as String),
            content: Value(m['content'] as String? ?? ''),
            messageType: Value(m['message_type'] as String? ?? 'text'),
            feedbackType: Value(m['feedback_type'] as String?),
            syncStatus: const Value('synced'),
          ));
        } else {
          // Only update feedback if server has newer data
          final serverFeedback = m['feedback_type'] as String?;
          if (serverFeedback != null && existing.feedbackType == null) {
            await _local.updateMessageFeedback(
              existing.id,
              serverFeedback,
              m['feedback_detail'] as String?,
            );
          }
        }
      }
    }
  }
}
