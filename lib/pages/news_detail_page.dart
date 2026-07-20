import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../core/providers/core_providers.dart';
import '../core/util/silent_log.dart';
import '../models/news_model.dart';
import '../widgets/markdown_latex_widget.dart';

class NewsDetailPage extends ConsumerStatefulWidget {
  final int id;

  const NewsDetailPage({super.key, required this.id});

  @override
  ConsumerState<NewsDetailPage> createState() => _NewsDetailPageState();
}

class _NewsDetailPageState extends ConsumerState<NewsDetailPage> {
  late Future<NewsItem> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = _loadDetail();
  }

  Future<NewsItem> _loadDetail() async {
    final repository = ref.read(newsRepositoryProvider);
    final item = await repository.fetchDetail(widget.id);
    // Mark as read once, update the unread badge and refresh the list so the
    // read state is reflected when the user returns.
    _markRead();
    return item;
  }

  Future<void> _markRead() async {
    try {
      final newCount = await ref.read(newsRepositoryProvider).markRead(widget.id);
      if (!mounted) return;
      ref.read(unreadNewsCountProvider.notifier).set(newCount);
      ref.invalidate(newsListProvider);
    } catch (e, st) {
      silentLog('news:mark-read', e, st);
    }
  }

  String _formatDate(DateTime d) => '${d.day}. ${d.month}. ${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.primaryDark),
        title: Text(
          AppStrings.novinkyTitle,
          style: AppTextStyles.heading3(),
        ),
      ),
      body: FutureBuilder<NewsItem>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _buildError();
          }

          final item = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              Text(
                item.title,
                style: AppTextStyles.heading2Bold(),
              ),
              const SizedBox(height: 8),
              Text(
                _formatDate(item.publishedAt),
                style: AppTextStyles.body(color: AppColors.primaryDark48),
              ),
              const SizedBox(height: 16),
              MarkdownLatexWidget(content: item.body ?? item.perex),
            ],
          );
        },
      ),
    );
  }

  Widget _buildError() {
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
              onPressed: () {
                setState(() {
                  _detailFuture = _loadDetail();
                });
              },
              child: Text(AppStrings.novinkyRetry),
            ),
          ],
        ),
      ),
    );
  }
}
