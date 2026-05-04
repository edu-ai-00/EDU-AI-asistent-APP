import 'package:drift/drift.dart';

/// Stores chat conversation sessions.
class ChatSessionsTable extends Table {
  @override
  String get tableName => 'chat_sessions';

  TextColumn get id => text()();
  TextColumn get userId => text()();
  IntColumn get serverId => integer().nullable()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get persona => text().withDefault(const Constant('ai_teacher'))();
  DateTimeColumn get lastMessageAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
