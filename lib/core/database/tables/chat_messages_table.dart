import 'package:drift/drift.dart';

/// Individual messages within a chat session.
class ChatMessagesTable extends Table {
  @override
  String get tableName => 'chat_messages';

  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  IntColumn get serverId => integer().nullable()();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get messageType => text().withDefault(const Constant('text'))();
  TextColumn get metadata => text().withDefault(const Constant('{}'))();
  TextColumn get feedbackType => text().nullable()();
  TextColumn get feedbackDetail => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
