import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../core/providers/core_providers.dart';
import '../core/util/drag_scroll_behavior.dart';
import '../models/news_model.dart';
import 'news_detail_page.dart';

class NovinkyPage extends ConsumerStatefulWidget {
  const NovinkyPage({super.key});

  @override
  ConsumerState<NovinkyPage> createState() => _NovinkyPageState();
}

class _NovinkyPageState extends ConsumerState<NovinkyPage> {
  String _formatDate(DateTime d) => '${d.day}. ${d.month}. ${d.year}';

  Future<void> _refresh() async {
    ref.invalidate(newsListProvider);
    await ref.read(newsListProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final newsAsync = ref.watch(newsListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            AppStrings.novinkyTitle,
            style: AppTextStyles.heading2Bold(),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ScrollConfiguration(
            behavior: const DragScrollBehavior(),
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: newsAsync.when(
                data: (items) {
                  if (items.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: _buildEmptyState(),
                        ),
                      ],
                    );
                  }

                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) =>
                        _buildNewsCard(items[index]),
                  );
                },
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

  Widget _buildNewsCard(NewsItem item) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NewsDetailPage(id: item.id),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDecorations.radiusXL,
          boxShadow: AppDecorations.shadowMedium,
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
                Expanded(
                  child: Text(
                    item.title,
                    style: AppTextStyles.bodyBold(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.perex,
              style: AppTextStyles.bodyLarge(color: AppColors.primaryDark48),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              _formatDate(item.publishedAt),
              style: AppTextStyles.body(color: AppColors.primaryDark48),
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
              onPressed: () => ref.invalidate(newsListProvider),
              child: Text(AppStrings.novinkyRetry),
            ),
          ],
        ),
      ),
    );
  }
}
