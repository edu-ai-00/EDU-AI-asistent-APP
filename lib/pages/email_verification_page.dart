import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/core_providers.dart';
import '../core/theme/app_theme.dart';
import '../features/email_validation/providers/email_validation_providers.dart';
import '../core/strings/app_strings.dart';

/// Full-screen page for email verification during registration/login.
class EmailVerificationPage extends ConsumerStatefulWidget {
  final String email;
  /// Called when verification succeeds or user continues without verification.
  /// Parameters: needsProfileSetup, isEmailValidated (false if user skipped offline)
  final void Function(bool needsProfileSetup, bool isEmailValidated) onVerified;
  final VoidCallback? onBack;

  const EmailVerificationPage({
    super.key,
    required this.email,
    required this.onVerified,
    this.onBack,
  });

  @override
  ConsumerState<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends ConsumerState<EmailVerificationPage> {
  final List<TextEditingController> _pinControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _codeSent = false;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    // Auto-send code when page opens (after checking connectivity)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkConnectivityAndSendCode();
    });
  }

  Future<void> _checkConnectivityAndSendCode() async {
    final connectivity = ref.read(connectivityServiceProvider);
    final isOnline = await connectivity.isOnline;

    if (!isOnline) {
      if (mounted) {
        setState(() => _isOffline = true);
        // Show offline dialog to let user continue without verification
        _showOfflineDialog();
      }
      return;
    }

    setState(() => _isOffline = false);
    _sendCode();
  }

  void _showOfflineDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: AppDecorations.radiusXL,
        ),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryDark12,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                color: AppColors.orange,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              AppStrings.emailVerificationOfflineTitle,
              style: AppTextStyles.cardTitle(),
            ),
          ],
        ),
        content: Text(
          AppStrings.emailVerificationOfflineMessage,
          style: AppTextStyles.bodySmall(color: AppColors.primaryDark64),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Try again
              _checkConnectivityAndSendCode();
            },
            child: Text(
              AppStrings.emailVerificationRetry,
              style: AppTextStyles.labelMedium(color: AppColors.primaryDark64),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Continue without verification - user needs profile setup, email NOT validated
              widget.onVerified(true, false);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: AppDecorations.radiusS,
              ),
              elevation: 0,
            ),
            child: Text(
              AppStrings.actionContinue,
              style: AppTextStyles.labelMedium(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final controller in _pinControllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  String get _pin => _pinControllers.map((c) => c.text).join();

  void _onPinChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    setState(() {});

    // Auto-submit when all 6 digits entered
    if (_pin.length == 6) {
      _verifyCode();
    }
  }

  void _handleKeyPress(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _pinControllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  void _clearPinFields() {
    for (final controller in _pinControllers) {
      controller.clear();
    }
    if (_focusNodes[0].canRequestFocus) {
      _focusNodes[0].requestFocus();
    }
  }

  Future<void> _sendCode() async {
    // Check connectivity first to avoid unnecessary API calls
    final connectivity = ref.read(connectivityServiceProvider);
    final isOnline = await connectivity.isOnline;

    if (!isOnline) {
      if (mounted) {
        setState(() => _isOffline = true);
        _showOfflineDialog();
      }
      return;
    }

    final notifier = ref.read(emailVerificationProvider.notifier);
    final success = await notifier.sendCode(widget.email);
    if (success && mounted) {
      setState(() {
        _codeSent = true;
        _isOffline = false;
      });
      _focusNodes[0].requestFocus();
    }
  }

  Future<void> _verifyCode() async {
    final notifier = ref.read(emailVerificationProvider.notifier);
    await notifier.verifyCode(_pin);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(emailVerificationProvider);
    final screenHeight = MediaQuery.of(context).size.height;

    // Listen for verification success
    ref.listen(emailVerificationProvider, (previous, current) {
      if (current is EmailVerificationSuccess) {
        // Email was verified successfully
        widget.onVerified(current.needsProfileSetup, true);
      } else if (current is EmailVerificationError) {
        if (current.type == EmailVerificationErrorType.invalidCode) {
          _clearPinFields();
        }
      }
    });

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: AppColors.authGradient,
        ),
        child: Stack(
          children: [
            // Background decorative image
            Positioned(
              bottom: screenHeight * 0.52 - 20,
              left: 0,
              right: 0,
              child: Image.asset(
                'assets/images/login_bg.png',
                fit: BoxFit.cover,
                width: double.infinity,
              ),
            ),
            // Logo
            Positioned(
              bottom: screenHeight * 0.52 + 60,
              left: 0,
              right: 0,
              child: Center(
                child: Image.asset(
                  'assets/images/login_logo.png',
                  width: 276,
                ),
              ),
            ),
            // White form container
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: screenHeight * 0.52,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Back button
                        if (widget.onBack != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: GestureDetector(
                              onTap: widget.onBack,
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryDark08,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.arrow_back,
                                  color: AppColors.primaryDark,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),

                        // Title
                        Text(
                          AppStrings.emailVerificationTitle,
                          style: AppTextStyles.heading1().copyWith(height: 1.2),
                        ),
                        const SizedBox(height: 8),

                        // Email display
                        Text(
                          widget.email,
                          style: AppTextStyles.bodyLarge(color: AppColors.primaryDark64),
                        ),
                        const SizedBox(height: 24),

                        // Content based on state
                        _buildContent(state),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(EmailVerificationState state) {
    // Show offline state first if device is offline
    if (_isOffline) {
      return _buildOfflineState();
    }

    if (state is EmailVerificationLoading) {
      return _buildLoadingState(state.message);
    }

    if (state is EmailVerificationError) {
      return _buildErrorState(state);
    }

    if (_codeSent || state is EmailVerificationCodeSent) {
      return _buildCodeEntryState();
    }

    return _buildLoadingState(AppStrings.emailVerificationSending);
  }

  Widget _buildOfflineState() {
    // Simple background state while dialog is shown
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 48,
              color: AppColors.primaryDark32,
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.emailVerificationOfflineLabel,
              style: AppTextStyles.bodySmall(color: AppColors.primaryDark48),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.primaryDark64,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppTextStyles.bodySmall(color: AppColors.primaryDark48),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeEntryState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.emailVerificationCodePrompt,
          style: AppTextStyles.bodySmall(color: AppColors.primaryDark64),
        ),
        const SizedBox(height: 16),

        // PIN input fields
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 48,
              height: 56,
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) => _handleKeyPress(index, event),
                child: TextField(
                  controller: _pinControllers[index],
                  focusNode: _focusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: AppTextStyles.heading3Alt(),
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: AppDecorations.radiusM,
                      borderSide: BorderSide(
                        color: AppColors.primaryDark16,
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppDecorations.radiusM,
                      borderSide: BorderSide(
                        color: AppColors.primaryDark16,
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: AppDecorations.radiusM,
                      borderSide: BorderSide(
                        color: AppColors.primaryDark,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (value) => _onPinChanged(index, value),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 24),

        // Verify button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _pin.length == 6 ? _verifyCode : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primaryDark48,
              disabledForegroundColor: Colors.white.withAlpha(179),
              shape: RoundedRectangleBorder(
                borderRadius: AppDecorations.radiusM,
              ),
              elevation: 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  AppStrings.emailVerificationVerify,
                  style: AppTextStyles.buttonLarge(color: Colors.white),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Resend code link
        Center(
          child: TextButton(
            onPressed: _sendCode,
            child: Text(
              AppStrings.emailVerificationResend,
              style: AppTextStyles.bodySmall(color: AppColors.primaryDark64).copyWith(
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(EmailVerificationError error) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Error message
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primaryDark08,
            borderRadius: AppDecorations.radiusS,
          ),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: AppColors.error,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  error.message,
                  style: AppTextStyles.bodySmall(color: AppColors.error),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Show code entry for retry
        _buildCodeEntryState(),
      ],
    );
  }
}
