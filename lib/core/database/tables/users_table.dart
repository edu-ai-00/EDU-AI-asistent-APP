import 'package:drift/drift.dart';

/// Drift table definition for local users.
/// Stores user profile data locally with email validation status.
class UsersTable extends Table {
  @override
  String get tableName => 'users';

  /// Local unique identifier (UUID).
  TextColumn get id => text()();

  /// User's email address.
  TextColumn get email => text()();

  /// User's display name.
  TextColumn get name => text()();

  /// Selected avatar index (0-5).
  IntColumn get avatarIndex => integer().withDefault(const Constant(0))();

  /// Selected subjects as JSON array of indices.
  TextColumn get selectedSubjects => text().withDefault(const Constant('[0]'))();

  /// Whether the email has been validated.
  BoolColumn get isEmailValidated => boolean().withDefault(const Constant(false))();

  /// Whether this is the currently active/logged in user.
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();

  /// Sync status: 0=synced, 1=pending, 2=conflict.
  IntColumn get syncStatus => integer().withDefault(const Constant(1))();

  /// When the user was created.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// When the user was last updated.
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
