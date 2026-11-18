import 'package:flutter/material.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../models/feed_item.dart';
import '../widgets/markdown_media_widget.dart';
import '../core/layout/breakpoints.dart';

/// A notification read in Novinky rather than followed elsewhere (BR-MCEHBH).
///
/// The school's messages, maintenance and update notices link to Novinky
/// itself, so their text is the whole point — and the feed card only shows
/// three lines of it. This is that text in full, the notification's
/// counterpart of [NewsDetailPage]: same heading, same date line, same
/// markdown body, so a pasted address in it is a link the app can follow.
///
/// Nothing to load: the feed row already carries the full text, and opening
/// it from the feed has already recorded `clicked` and marked it read.
class NotificationDetailPage extends StatelessWidget {
  final FeedItem item;

  /// Rendered as the right-hand pane of the two-pane Novinky layout rather
  /// than as a route of its own — see [NewsDetailPage.embedded].
  final bool embedded;

  const NotificationDetailPage({
    super.key,
    required this.item,
    this.embedded = false,
  });

  String _formatDateTime(DateTime d) {
    final local = d.toLocal();
    final minutes = local.minute.toString().padLeft(2, '0');
    return '${local.day}. ${local.month}. ${local.year} ${local.hour}:$minutes';
  }

  @override
  Widget build(BuildContext context) {
    if (embedded) return _buildBody(context);

    // Phone and tablet: pushed over the feed, like an article.
    return ContentWidth(
      maxWidth: ContentWidth.reading,
      child: Scaffold(
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
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    // The 120px tail clears the floating bottom bar, which only exists on the
    // phone layout.
    final bottomPadding =
        context.widthClass == WidthClass.compact ? 120.0 : 32.0;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
      children: [
        Text(
          item.title,
          style: AppTextStyles.heading2Bold(),
        ),
        const SizedBox(height: 8),
        Text(
          _formatDateTime(item.createdAt),
          style: AppTextStyles.body(color: AppColors.primaryDark48),
        ),
        if (item.body.isNotEmpty) ...[
          const SizedBox(height: 16),
          MarkdownMediaWidget(content: item.body),
        ],
      ],
    );
  }
}
