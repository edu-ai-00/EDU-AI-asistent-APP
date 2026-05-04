import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/practice_repository.dart';
import '../database/app_database.dart';
import '../practice/practice_service.dart';
import 'core_providers.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Practice Repository Provider
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider for the practice repository.
final practiceRepositoryProvider = Provider<PracticeRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return PracticeRepository(db: db);
});

// ═══════════════════════════════════════════════════════════════════════════════
// Practice Service Provider
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider for the practice service.
final practiceServiceProvider = Provider<PracticeService>((ref) {
  final repo = ref.watch(practiceRepositoryProvider);
  return PracticeService(repo: repo);
});

// ═══════════════════════════════════════════════════════════════════════════════
// Practice Data Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Future provider for the count of due practice cards for the active user.
final dueCardsCountProvider = FutureProvider<int>((ref) async {
  final user = await ref.watch(activeUserProvider.future);
  if (user == null) return 0;

  final repo = ref.watch(practiceRepositoryProvider);
  return repo.countDueCards(user.id);
});

/// Future provider for today's practice queue for the active user.
final practiceQueueProvider = FutureProvider<List<PracticeCardsTableData>>((ref) async {
  final user = await ref.watch(activeUserProvider.future);
  if (user == null) return [];

  final service = ref.watch(practiceServiceProvider);
  return service.generateQueue(user.id);
});
