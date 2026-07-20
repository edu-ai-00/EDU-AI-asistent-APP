import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/connectivity/connectivity_service.dart';
import '../core/database/app_database.dart';
import '../core/providers/core_providers.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../data/repositories/chat_repository.dart';
import '../models/chat_models.dart';
import '../widgets/markdown_latex_widget.dart';
import 'package:eduai/core/util/silent_log.dart';

/// Chat Detail Page for individual conversation
class ChatDetailPage extends ConsumerStatefulWidget {
  final String sessionId;
  final String sessionTitle;
  final ChatPersona persona;

  /// Optional context message to auto-send when opening chat from a block.
  /// When set with an empty sessionId, creates a new session and sends this as first message.
  final String? initialContext;

  const ChatDetailPage({
    super.key,
    required this.sessionId,
    required this.sessionTitle,
    required this.persona,
    this.initialContext,
  });

  @override
  ConsumerState<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends ConsumerState<ChatDetailPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isStreaming = false;
  bool _hasText = false;
  bool _isOffline = false;
  String? _effectiveSessionId;
  StreamSubscription<ChatStreamEvent>? _streamSub;

  @override
  void initState() {
    super.initState();
    _effectiveSessionId = widget.sessionId.isNotEmpty ? widget.sessionId : null;
    _messageController.addListener(() {
      final hasText = _messageController.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });

    // If opened with context (from block), create session and auto-send
    if (widget.initialContext != null && _effectiveSessionId == null) {
      _createSessionAndSendContext();
    }
  }

  Future<void> _createSessionAndSendContext() async {
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final user = await ref.read(activeUserProvider.future);
      if (user == null) return;

      final session = await chatRepo.createSession(user.id, widget.persona);
      _effectiveSessionId = session.id;
      if (mounted) setState(() {});

      // Auto-send the context as first message
      if (widget.initialContext != null && _effectiveSessionId != null) {
        _messageController.text = widget.initialContext!;
        _sendMessage();
      }
    } catch (e, st) { silentLog('chat_detail_page', e, st); }
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty || _isStreaming) return;
    final sessionId = _effectiveSessionId;
    if (sessionId == null) return;
    final content = _messageController.text.trim();
    _messageController.clear();

    setState(() => _isStreaming = true);

    final chatRepo = ref.read(chatRepositoryProvider);
    _streamSub = chatRepo.sendMessage(sessionId, content).listen(
      (event) {
        switch (event) {
          case ChatStreamToken():
            // Content is already updated in local DB by the repository
            // The watchMessages stream will trigger UI rebuild automatically
            _scrollToBottom();
            break;
          case ChatStreamDone():
            setState(() => _isStreaming = false);
            _scrollToBottom();
            // Sync to pick up server-generated title after first message
            ref.read(syncServiceProvider).sync();
            break;
          case ChatStreamError():
            setState(() => _isStreaming = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(AppStrings.chatStreamError)),
              );
            }
            break;
        }
      },
      onError: (e) {
        setState(() => _isStreaming = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppStrings.chatStreamError)),
          );
        }
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = _effectiveSessionId ?? widget.sessionId;
    final messagesAsync =
        ref.watch(chatMessagesStreamProvider(sessionId));
    final connectivityAsync = ref.watch(connectivityStateProvider);
    _isOffline = connectivityAsync.whenOrNull(
      data: (state) => !state.isOnline,
    ) ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Header (extends to top)
          _buildHeader(),
          // Offline banner
          if (_isOffline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.orange,
              child: Row(
                children: [
                  const Icon(Icons.wifi_off, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    AppStrings.chatDetailOfflineBanner,
                    style: AppTextStyles.caption(color: Colors.white),
                  ),
                ],
              ),
            ),
          // Messages
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                // Auto-scroll when new messages arrive
                _scrollToBottom();
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  itemCount: messages.length +
                      1 +
                      (_isStreaming ? 1 : 0), // +1 for date separator
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _buildDateSeparator(AppStrings.chatDetailToday);
                    }
                    if (index > messages.length) {
                      return _buildTypingIndicator();
                    }
                    final message = messages[index - 1];
                    return _buildMessageBubble(message);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(AppStrings.genericError(e.toString()))),
            ),
          ),
          // Input bar
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: topPadding + 12,
        bottom: 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppDecorations.shadowLight,
      ),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.background,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_back,
                color: AppColors.primaryDark,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                widget.persona.emoji,
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name and status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.sessionTitle.isNotEmpty
                      ? widget.sessionTitle
                      : widget.persona.displayName,
                  style: AppTextStyles.cardTitleSmall(),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      AppStrings.chatDetailOnline,
                      style:
                          AppTextStyles.meta(color: AppColors.primaryDark64),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSeparator(String date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: AppColors.primaryDark08,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              date,
              style: AppTextStyles.caption(color: AppColors.primaryDark48),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: AppColors.primaryDark08,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessagesTableData message) {
    final isUser = message.isFromUser;
    final timeString =
        '${message.createdAt.hour}:${message.createdAt.minute.toString().padLeft(2, '0')}';

    // If assistant message with empty content, it's still streaming — skip rendering
    if (!isUser && message.content.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            // AI Avatar
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.background,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  widget.persona.emoji,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Message content
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isUser ? AppColors.background : AppColors.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isUser ? 20 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 20),
                    ),
                    border: isUser
                        ? Border.all(
                            color: AppColors.primaryDark08,
                          )
                        : null,
                    boxShadow: isUser ? null : AppDecorations.shadowLight,
                  ),
                  child: MarkdownLatexWidget(
                    content: message.content,
                    textStyle: AppTextStyles.bodySmall().copyWith(height: 1.5),
                  ),
                ),
                const SizedBox(height: 6),
                // Timestamp and actions
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeString,
                      style: AppTextStyles.chipLabel(
                          color: AppColors.primaryDark48),
                    ),
                    if (!isUser) ...[
                      const SizedBox(width: 12),
                      // Thumbs up
                      GestureDetector(
                        onTap: () {
                          final chatRepo = ref.read(chatRepositoryProvider);
                          chatRepo.submitFeedback(
                            message.id,
                            message.isLiked ? null : 'like',
                            null,
                          );
                        },
                        child: Icon(
                          message.isLiked
                              ? Icons.thumb_up
                              : Icons.thumb_up_outlined,
                          size: 16,
                          color: message.isLiked
                              ? AppColors.primaryDark
                              : AppColors.primaryDark48,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Thumbs down
                      GestureDetector(
                        onTap: () => _showFeedbackBottomSheet(
                          context,
                          message.id,
                        ),
                        child: Icon(
                          message.isDisliked
                              ? Icons.thumb_down
                              : Icons.thumb_down_outlined,
                          size: 16,
                          color: message.isDisliked
                              ? AppColors.primaryDark
                              : AppColors.primaryDark48,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            // User Avatar
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.cardLavender,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.person,
                  size: 18,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI Avatar
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                widget.persona.emoji,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Typing dots
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: AppDecorations.shadowLight,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTypingDot(0),
                const SizedBox(width: 4),
                _buildTypingDot(1),
                const SizedBox(width: 4),
                _buildTypingDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 600 + (index * 200)),
      builder: (context, value, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.primaryDark48,
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  void _showFeedbackBottomSheet(BuildContext context, String messageId) {
    final chatRepo = ref.read(chatRepositoryProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FeedbackBottomSheet(
        messageId: messageId,
        chatRepo: chatRepo,
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark08,
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Text input
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: AppDecorations.radiusS,
                  ),
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter &&
                          !HardwareKeyboard.instance.isShiftPressed) {
                        if (!_isStreaming && _hasText && !_isOffline) {
                          _sendMessage();
                        }
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: AppStrings.chatDetailInputHint,
                        hintStyle: AppTextStyles.bodySmall(
                            color: AppColors.primaryDark48),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      style: AppTextStyles.bodySmall(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Send button
              GestureDetector(
                onTap: (_isStreaming || !_hasText || _isOffline) ? null : _sendMessage,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (_isStreaming || !_hasText || _isOffline)
                        ? AppColors.primaryDark32
                        : AppColors.primaryDark,
                    borderRadius: AppDecorations.radiusS,
                  ),
                  child: const Icon(
                    Icons.send,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Helper text
          Text(
            AppStrings.chatDetailHelperText,
            style: AppTextStyles.chipLabel(color: AppColors.primaryDark48),
          ),
        ],
      ),
    );
  }
}

/// Feedback reason options
enum FeedbackReason {
  incorrectInfo,
  incompleteAnswer,
  unclearExplanation,
  inappropriateAnswer,
  otherReason,
}

/// Feedback Bottom Sheet Widget
class FeedbackBottomSheet extends StatefulWidget {
  final String messageId;
  final ChatRepository chatRepo;

  const FeedbackBottomSheet({
    super.key,
    required this.messageId,
    required this.chatRepo,
  });

  @override
  State<FeedbackBottomSheet> createState() => _FeedbackBottomSheetState();
}

class _FeedbackBottomSheetState extends State<FeedbackBottomSheet> {
  FeedbackReason? _selectedReason;
  final TextEditingController _detailsController = TextEditingController();

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  String _getReasonEmoji(FeedbackReason reason) {
    switch (reason) {
      case FeedbackReason.incorrectInfo:
        return '❌';
      case FeedbackReason.incompleteAnswer:
        return '📝';
      case FeedbackReason.unclearExplanation:
        return '❓';
      case FeedbackReason.inappropriateAnswer:
        return '⚠️';
      case FeedbackReason.otherReason:
        return '💬';
    }
  }

  String _getReasonText(FeedbackReason reason) {
    switch (reason) {
      case FeedbackReason.incorrectInfo:
        return AppStrings.chatFeedbackIncorrect;
      case FeedbackReason.incompleteAnswer:
        return AppStrings.chatFeedbackIncomplete;
      case FeedbackReason.unclearExplanation:
        return AppStrings.chatFeedbackUnclear;
      case FeedbackReason.inappropriateAnswer:
        return AppStrings.chatFeedbackInappropriate;
      case FeedbackReason.otherReason:
        return AppStrings.chatFeedbackOther;
    }
  }

  void _submitFeedback() {
    if (_selectedReason == null) return;

    widget.chatRepo.submitFeedback(
      widget.messageId,
      'dislike',
      _getReasonText(_selectedReason!),
    );
    Navigator.pop(context);

    // Show confirmation snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppStrings.chatFeedbackThanks,
          style: AppTextStyles.bodySmall(),
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppDecorations.radiusS,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thumbs down icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: AppDecorations.radiusS,
                    ),
                    child: const Center(
                      child: Text(
                        '👎',
                        style: TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Title and subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.chatFeedbackTitle,
                          style: AppTextStyles.cardTitle(),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppStrings.chatFeedbackSubtitle,
                          style: AppTextStyles.meta(
                              color: AppColors.primaryDark64),
                        ),
                      ],
                    ),
                  ),
                  // Close button
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(
                      Icons.close,
                      color: AppColors.primaryDark48,
                      size: 24,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Reason label
              Row(
                children: [
                  Text(
                    AppStrings.chatFeedbackSelectReason,
                    style: AppTextStyles.labelMedium(),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '*',
                    style: AppTextStyles.labelMedium(color: AppColors.error),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Reason options
              ...FeedbackReason.values
                  .map((reason) => _buildReasonOption(reason)),

              const SizedBox(height: 24),

              // Additional details label
              Text(
                AppStrings.chatFeedbackDetails,
                style: AppTextStyles.labelMedium(),
              ),
              const SizedBox(height: 12),

              // Text area
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppColors.primaryDark16,
                  ),
                  borderRadius: AppDecorations.radiusS,
                ),
                child: TextField(
                  controller: _detailsController,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: InputDecoration(
                    hintText: AppStrings.chatFeedbackHint,
                    hintStyle: AppTextStyles.bodySmall(
                        color: AppColors.primaryDark48),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                    counterStyle: AppTextStyles.caption(
                        color: AppColors.primaryDark48),
                  ),
                  style: AppTextStyles.bodySmall(),
                ),
              ),

              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  // Cancel button
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.primaryDark16,
                          ),
                          borderRadius: AppDecorations.radiusS,
                        ),
                        child: Center(
                          child: Text(
                            AppStrings.chatFeedbackCancel,
                            style: AppTextStyles.labelMedium(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Submit button
                  Expanded(
                    child: GestureDetector(
                      onTap:
                          _selectedReason != null ? _submitFeedback : null,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: _selectedReason != null
                              ? AppColors.primaryDark
                              : AppColors.primaryDark32,
                          borderRadius: AppDecorations.radiusS,
                        ),
                        child: Center(
                          child: Text(
                            AppStrings.chatFeedbackSubmit,
                            style:
                                AppTextStyles.labelMedium(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Bottom safe area
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReasonOption(FeedbackReason reason) {
    final isSelected = _selectedReason == reason;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedReason = reason;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryDark
                  : AppColors.primaryDark16,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: AppDecorations.radiusS,
          ),
          child: Row(
            children: [
              // Radio button
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primaryDark
                        : AppColors.primaryDark32,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppColors.primaryDark,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              // Emoji
              Text(
                _getReasonEmoji(reason),
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: 12),
              // Text
              Text(
                _getReasonText(reason),
                style: AppTextStyles.bodySmall(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
