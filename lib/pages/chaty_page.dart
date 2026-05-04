import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/connectivity/connectivity_service.dart';
import '../core/database/app_database.dart';
import '../core/providers/core_providers.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../models/chat_models.dart';
import '../widgets/filter_chip_row.dart';
import 'chat_detail_page.dart';

/// Chaty (Chats) page displaying list of conversations backed by Drift DB.
class ChatyPage extends ConsumerStatefulWidget {
  const ChatyPage({super.key});

  @override
  ConsumerState<ChatyPage> createState() => _ChatyPageState();
}

class _ChatyPageState extends ConsumerState<ChatyPage> {
  int _selectedFilterIndex = 0;
  final List<String> _filters = [AppStrings.filterAll, AppStrings.filterInProgress, 'Ukončené'];

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(chatSessionsStreamProvider);
    final connectivityAsync = ref.watch(connectivityStateProvider);
    final isOffline = connectivityAsync.whenOrNull(
      data: (state) => !state.isOnline,
    ) ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isOffline)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppColors.orange,
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off, size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Nejsi online',
                      style: AppTextStyles.caption(color: Colors.white),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            _buildHeader(context),
            const SizedBox(height: 16),
            // Filter chips
            FilterChipRow(
              labels: _filters,
              selectedIndex: _selectedFilterIndex,
              onSelected: (index) {
                setState(() {
                  _selectedFilterIndex = index;
                });
              },
            ),
            const SizedBox(height: 16),
            // Divider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 1,
                color: AppColors.primaryDark08,
              ),
            ),
            const SizedBox(height: 8),
            // Sessions list / empty / loading
            Expanded(
              child: sessionsAsync.when(
                data: (sessions) => sessions.isEmpty
                    ? _buildEmptyState()
                    : _buildSessionList(sessions, context),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
            _buildInfoBanner(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Title
          Text(
            AppStrings.chatyTitle,
            style: AppTextStyles.heading1(),
          ),
          const Spacer(),
          // New chat button
          GestureDetector(
            onTap: () => _showPersonaPicker(context),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(21),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SvgPicture.asset(
                    'assets/icons/plus.svg',
                    width: 18,
                    height: 18,
                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Nový chat',
                    style: AppTextStyles.actionSmall(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Session list
  // ---------------------------------------------------------------------------

  Widget _buildSessionList(
    List<ChatSessionsTableData> sessions,
    BuildContext context,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: index < sessions.length - 1 ? 12 : 0,
          ),
          child: _buildSessionCard(sessions[index], context),
        );
      },
    );
  }

  Widget _buildSessionCard(
    ChatSessionsTableData session,
    BuildContext context,
  ) {
    final persona = session.chatPersona;
    final title = (session.title.isNotEmpty) ? session.title : persona.displayName;
    final timeStr = _formatRelativeTime(session.lastMessageAt);

    final bgColor = _avatarColorForPersona(persona);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailPage(
              sessionId: session.id,
              sessionTitle: title,
              persona: persona,
            ),
          ),
        );
      },
      onLongPress: () => _showDeleteDialog(context, session),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDecorations.radiusXL,
          boxShadow: AppDecorations.shadowLight,
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  persona.emoji,
                  style: const TextStyle(fontSize: 28),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name and persona
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.statValue(),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    persona.displayName,
                    style: AppTextStyles.bodySmall(
                      color: AppColors.primaryDark64,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Timestamp aligned right
            Text(
              timeStr,
              style: AppTextStyles.caption(
                color: AppColors.primaryDark48,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty state
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('💬', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              AppStrings.chatEmptyState,
              style: AppTextStyles.bodySmall(color: AppColors.primaryDark48),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Info banner
  // ---------------------------------------------------------------------------

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 20,
            color: AppColors.primaryDark48,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.chatyInfoBanner,
              style: AppTextStyles.caption(color: AppColors.primaryDark48),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Persona picker bottom sheet
  // ---------------------------------------------------------------------------

  void _showPersonaPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppStrings.chatSelectPersona,
                style: AppTextStyles.cardTitle(),
              ),
              const SizedBox(height: 24),
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.2,
                physics: const NeverScrollableScrollPhysics(),
                children: ChatPersona.values
                    .map((p) => _buildPersonaTile(p, context))
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPersonaTile(
    ChatPersona persona,
    BuildContext context,
  ) {
    return GestureDetector(
      onTap: () async {
        Navigator.pop(context); // close sheet
        await _createSessionAndNavigate(persona, context);
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: AppDecorations.radiusS,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(persona.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                persona.displayName,
                style: AppTextStyles.labelMedium(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createSessionAndNavigate(
    ChatPersona persona,
    BuildContext context,
  ) async {
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final user = await ref.read(activeUserProvider.future);
      if (user == null) return;

      final session = await chatRepo.createSession(user.id, persona);

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailPage(
              sessionId: session.id,
              sessionTitle: session.title.isNotEmpty
                  ? session.title
                  : persona.displayName,
              persona: persona,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.chatRequiresInternet),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Delete confirmation
  // ---------------------------------------------------------------------------

  void _showDeleteDialog(
    BuildContext context,
    ChatSessionsTableData session,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.chatDelete),
        content: Text(AppStrings.chatDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Zrušit'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final chatRepo = ref.read(chatRepositoryProvider);
              await chatRepo.deleteSession(session.id);
            },
            child: Text(
              AppStrings.chatDelete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Color _avatarColorForPersona(ChatPersona persona) {
    switch (persona) {
      case ChatPersona.aiTeacher:
        return AppColors.background;
      case ChatPersona.mathMentor:
        return AppColors.successBg;
      case ChatPersona.studyCoach:
        return AppColors.cardBlue;
      case ChatPersona.languageMentor:
        return AppColors.cardBlue;
    }
  }

  String _formatRelativeTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'teď';
    if (diff.inMinutes < 60) return 'před ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'před ${diff.inHours} hod';
    if (diff.inDays < 7) return 'před ${diff.inDays} d';
    return '${dateTime.day}.${dateTime.month}.';
  }
}
