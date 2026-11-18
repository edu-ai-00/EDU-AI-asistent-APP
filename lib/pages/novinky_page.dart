import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../core/providers/notification_providers.dart';
import '../core/ui/app_toast.dart';
import '../core/util/drag_scroll_behavior.dart';
import '../models/feed_item.dart';
import '../routing/notification_deep_link.dart';
import '../routing/tab_routes.dart';
import 'news_detail_page.dart';
import 'notification_detail_page.dart';
import '../core/layout/breakpoints.dart';

/// Novinky: news and this user's notifications in one feed (NOTIF-4,
/// BR-KN9XUT — there is no separate notification inbox).
///
/// Infinite scroll over `/api/feed`, pull-to-refresh, unread dots and
/// "Označit vše jako přečtené". An article opens [NewsDetailPage] as it always
/// did (in the right-hand pane on desktop); a notification records `clicked`
/// and opens its deep link — unless that link is Novinky itself, in which case
/// it opens [NotificationDetailPage] the way an article opens (BR-MCEHBH).
/// Offline, the pages loaded last time are shown
/// under a hint. On a phone with push available, the top of the feed is also
/// where the user is first asked about notifications — never an OS prompt at
/// launch.
class NovinkyPage extends ConsumerStatefulWidget {
  const NovinkyPage({super.key});

  static const markAllReadKey = Key('novinky-mark-all-read');
  static const primingAllowKey = Key('novinky-push-priming-allow');
  static const primingLaterKey = Key('novinky-push-priming-later');

  @override
  ConsumerState<NovinkyPage> createState() => _NovinkyPageState();
}

class _NovinkyPageState extends ConsumerState<NovinkyPage> {
  static const double _listWidth = 360;

  /// How close to the end of the list the next page starts loading.
  static const double _loadMoreThreshold = 600;

  /// Novinky's own index among the main tabs.
  static final int _novinkyTab = mainTabIndexForPath('/news')!;

  /// Wide layout only. The row open in the right-hand pane — an article, or a
  /// notification read in place — null until one is picked.
  FeedItem? _openItem;

  final ScrollController _scrollController = ScrollController();

  /// Rows already reported as viewed in this visit (the event queue dedupes
  /// across visits).
  final Set<String> _viewed = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.extentAfter > _loadMoreThreshold) return;
    final feed = ref.read(feedControllerProvider).valueOrNull;
    if (feed == null ||
        !feed.hasMore ||
        feed.loadingMore ||
        feed.loadMoreFailed) {
      return;
    }
    ref.read(feedControllerProvider.notifier).loadMore();
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    return '${local.day}. ${local.month}. ${local.year}';
  }

  String _formatDateTime(DateTime d) {
    final local = d.toLocal();
    final minutes = local.minute.toString().padLeft(2, '0');
    return '${_formatDate(local)} ${local.hour}:$minutes';
  }

  Future<void> _refresh() async {
    _viewed.clear();
    await ref.read(feedControllerProvider.notifier).refresh();
  }

  Future<void> _markAllRead() async {
    final ok = await ref.read(feedControllerProvider.notifier).markAllRead();
    if (!ok && mounted) {
      showAppToast(
        context,
        AppStrings.novinkyMarkAllReadFailed,
        variant: ToastVariant.error,
      );
    }
  }

  void _open(FeedItem item) {
    if (item.isNews) {
      _openArticle(item);
    } else if (_readsInPlace(item)) {
      _readNotification(item);
    } else {
      _openNotification(item);
    }
  }

  /// Whether [item]'s link is this feed. The school's messages, maintenance
  /// and update notices all link to `/news`: they have nowhere else to send
  /// the user, their text is the point. Following that link from here was a
  /// no-op — already on the tab — so they could not be read past the card's
  /// three-line preview (BR-MCEHBH).
  bool _readsInPlace(FeedItem item) =>
      resolveNotificationLink(item.deepLink) ==
      NotificationLinkTarget.tab(_novinkyTab);

  /// Open an article: a pane on desktop, a pushed route otherwise.
  void _openArticle(FeedItem item) {
    if (context.isExpanded) {
      setState(() => _openItem = item);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NewsDetailPage(id: item.newsId!)),
    );
  }

  /// Open a notification whose target is this feed the way an article opens.
  /// It still counts as opened: `clicked`, and read.
  void _readNotification(FeedItem item) {
    unawaited(ref.read(feedControllerProvider.notifier).openNotification(item));
    if (context.isExpanded) {
      setState(() => _openItem = item);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NotificationDetailPage(item: item)),
    );
  }

  /// Any other notification leads somewhere in the app. Desktop included: the
  /// pane is for reading, this is navigation.
  Future<void> _openNotification(FeedItem item) async {
    await ref.read(feedControllerProvider.notifier).openNotification(item);
    if (!mounted) return;
    await openNotificationLink(context, ref, item.deepLink);
  }

  Future<void> _acceptPriming() async {
    final granted = await ref.read(pushControllerProvider).acceptPriming();
    ref.invalidate(pushPrimingVisibleProvider);
    if (!granted && mounted) {
      showAppToast(context, AppStrings.pushPermissionDenied);
    }
  }

  Future<void> _declinePriming() async {
    await ref.read(pushControllerProvider).declinePriming();
    ref.invalidate(pushPrimingVisibleProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (!context.isExpanded) {
      return ContentWidth(
        maxWidth: ContentWidth.reading,
        child: _buildPage(context),
      );
    }

    // Two panes: the feed on the left, the open article on the right. The
    // phone flow pushes the detail as a route; here it is embedded, so the
    // list stays visible and switching articles does not animate the whole
    // view. Same shape as the chat tab (BR-ZT56WM).
    final open = _openItem;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: _listWidth, child: _buildPage(context)),
        Container(width: 1, color: AppColors.primaryDark08),
        Expanded(
          child: open == null
              ? _buildNoArticleSelected()
              // The pane is as wide as the monitor allows, but an article is
              // prose — left unclamped its lines ran the full width and became
              // unreadable, so the pane sets the measure the embedded page
              // deliberately does not.
              : ContentWidth(
                  maxWidth: ContentWidth.reading,
                  child: open.isNews
                      ? NewsDetailPage(
                          // Keyed by row so switching rebuilds the state (the
                          // detail future and its mark-read call) instead of
                          // reusing the previous article's.
                          key: ValueKey(open.id),
                          id: open.newsId!,
                          embedded: true,
                        )
                      : NotificationDetailPage(
                          key: ValueKey(open.id),
                          item: open,
                          embedded: true,
                        ),
                ),
        ),
      ],
    );
  }

  Widget _buildPage(BuildContext context) {
    final feedAsync = ref.watch(feedControllerProvider);
    final feed = feedAsync.valueOrNull;
    final showPriming = ref.watch(pushPrimingVisibleProvider).valueOrNull ?? false;
    // The desktop top bar already shows the page title.
    final showTitle = !context.isExpanded;
    // A server without the feed has no "read all" endpoint either.
    final showMarkAll = feed != null && !feed.legacy && feed.hasUnread;
    // The floating bottom bar the list has to clear only exists on phones —
    // the tablet rail and the desktop sidebar are beside the content.
    final isPhone = context.widthClass == WidthClass.compact;

    if (feed != null && feed.hasMore && !feed.loadingMore && !feed.loadMoreFailed) {
      // A first page shorter than the screen never scrolls, so the listener
      // alone would never ask for the next one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeLoadMore();
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        if (showTitle) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              AppStrings.novinkyTitle,
              style: AppTextStyles.heading2Bold(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        // A row of its own: beside the heading the Czech label does not fit a
        // phone, and on desktop there is no heading to sit beside.
        if (showMarkAll) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: NovinkyPage.markAllReadKey,
                onPressed: _markAllRead,
                icon: const Icon(Icons.done_all, size: 18),
                label: Text(
                  AppStrings.novinkyMarkAllRead,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        Expanded(
          child: ScrollConfiguration(
            behavior: const DragScrollBehavior(),
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: feedAsync.when(
                // A failed reload keeps the list on screen (the controller
                // only errors when there is nothing to show).
                skipError: true,
                data: (feed) => _buildList(
                  context,
                  feed,
                  showPriming: showPriming,
                  bottomPadding: isPhone ? 120 : 32,
                ),
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stack) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: _buildErrorState(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    FeedState feed, {
    required bool showPriming,
    required double bottomPadding,
  }) {
    final header = <Widget>[
      if (showPriming) _buildPrimingCard(),
      if (feed.fromCache) _buildOfflineHint(),
    ];

    if (feed.items.isEmpty) {
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final row in header) ...[row, const SizedBox(height: 12)],
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: _buildEmptyState(),
          ),
        ],
      );
    }

    final footer = _buildFooter(feed);
    final count = header.length + feed.items.length + (footer == null ? 0 : 1);

    return ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
      itemCount: count,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index < header.length) return header[index];
        final itemIndex = index - header.length;
        if (itemIndex < feed.items.length) {
          return _buildCard(feed.items[itemIndex]);
        }
        return footer!;
      },
    );
  }

  Widget? _buildFooter(FeedState feed) {
    if (feed.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (feed.loadMoreFailed) {
      return Center(
        child: Column(
          children: [
            Text(
              AppStrings.novinkyLoadMoreFailed,
              style: AppTextStyles.body(color: AppColors.primaryDark64),
              textAlign: TextAlign.center,
            ),
            TextButton(
              onPressed: () =>
                  ref.read(feedControllerProvider.notifier).loadMore(),
              child: Text(AppStrings.novinkyRetry),
            ),
          ],
        ),
      );
    }
    return null;
  }

  Widget _buildCard(FeedItem item) {
    // First time on screen: `viewed`. Notifications only; the queue ignores
    // repeats across visits.
    if (item.isNotification && _viewed.add(item.id)) {
      ref.read(feedControllerProvider.notifier).recordViewed(item);
    }

    // In the two-pane layout the card is what tells the user which article the
    // right-hand pane is showing — without it the panes read as unrelated.
    final isOpen = context.isExpanded && _openItem?.id == item.id;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(item),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDecorations.radiusXL,
          boxShadow: AppDecorations.shadowMedium,
          // Always drawn, so selecting a card does not nudge its contents by
          // the border width.
          border: Border.all(
            color: isOpen ? AppColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!item.isRead) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (item.isNotification) ...[
                  Icon(
                    _categoryIcon(item.category),
                    size: 18,
                    color: AppColors.primaryDark64,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    item.title,
                    style: AppTextStyles.bodyBold(),
                  ),
                ),
              ],
            ),
            if (item.body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                item.body,
                style: AppTextStyles.bodyLarge(color: AppColors.primaryDark48),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              item.isNotification
                  ? _formatDateTime(item.createdAt)
                  : _formatDate(item.createdAt),
              style: AppTextStyles.body(color: AppColors.primaryDark48),
            ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon(String? category) => switch (category) {
        'provoz' => Icons.campaign_outlined,
        'navyk' => Icons.alarm_outlined,
        'pokrok' => Icons.emoji_events_outlined,
        'aktivace' => Icons.bolt_outlined,
        _ => Icons.notifications_outlined,
      };

  Widget _buildPrimingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDecorations.radiusXL,
        boxShadow: AppDecorations.shadowMedium,
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_active_outlined,
                  color: AppColors.primaryDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppStrings.pushPrimingTitle,
                  style: AppTextStyles.bodyBold(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.pushPrimingBody,
            style: AppTextStyles.body(color: AppColors.primaryDark64),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: NovinkyPage.primingLaterKey,
                onPressed: _declinePriming,
                child: Text(AppStrings.pushPrimingLater),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: NovinkyPage.primingAllowKey,
                onPressed: _acceptPriming,
                child: Text(AppStrings.pushPrimingAllow),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: AppDecorations.radiusM,
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.primaryDark64),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppStrings.novinkyOfflineHint,
              style: AppTextStyles.bodySmall(color: AppColors.primaryDark64),
            ),
          ),
        ],
      ),
    );
  }

  /// Right-hand pane before the user has picked anything.
  Widget _buildNoArticleSelected() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📰', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              AppStrings.novinkyPickArticle,
              style: AppTextStyles.body(color: AppColors.primaryDark48),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('📰', style: TextStyle(fontSize: 36)),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              AppStrings.novinkyEmpty,
              style: AppTextStyles.heading4(),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              AppStrings.novinkyError,
              style: AppTextStyles.bodyLarge(color: AppColors.primaryDark64),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => ref.invalidate(feedControllerProvider),
              child: Text(AppStrings.novinkyRetry),
            ),
          ],
        ),
      ),
    );
  }
}
