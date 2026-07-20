import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;

import '../core/database/app_database.dart';
import '../core/providers/core_providers.dart';
import '../core/theme/app_theme.dart';
import '../features/email_validation/providers/email_validation_providers.dart';
import '../core/strings/app_strings.dart';

class ProfileSetupPage extends ConsumerStatefulWidget {
  /// The email address entered by the user on the auth page.
  final String email;

  /// Whether the email has been validated (false if user skipped verification when offline).
  final bool isEmailValidated;

  /// Callback when profile setup is complete.
  final VoidCallback onComplete;

  const ProfileSetupPage({
    super.key,
    required this.email,
    this.isEmailValidated = true,
    required this.onComplete,
  });

  @override
  ConsumerState<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends ConsumerState<ProfileSetupPage> {
  final TextEditingController _nameController = TextEditingController();
  int _selectedAvatarIndex = 0;
  final Set<int> _selectedSubjects = {0}; // Biologie selected by default
  bool _isSaving = false;

  final List<SubjectItem> _subjects = [
    SubjectItem(name: AppStrings.subjectBiology, emoji: '🧬', color: AppColors.subjectBiology),
    SubjectItem(name: AppStrings.subjectGrammar, emoji: '✏️', color: AppColors.subjectGrammar),
    SubjectItem(name: AppStrings.subjectLiterature, emoji: '📚', color: AppColors.subjectLiterature),
    SubjectItem(name: AppStrings.subjectMath, emoji: '🔢', color: AppColors.subjectMath),
    SubjectItem(name: AppStrings.subjectChemistry, emoji: '🧪', color: AppColors.subjectChemistry),
    SubjectItem(name: AppStrings.subjectEnglish, emoji: '🇬🇧', color: AppColors.subjectLiterature),
  ];

  Future<void> _handleContinue() async {
    final name = _nameController.text.trim();

    // Validate name
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.profileSetupNameError),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Create user in database
      final db = ref.read(appDatabaseProvider);
      final userId = const Uuid().v4();

      // Capture the currently-active user (typically the guest) BEFORE it is
      // deactivated by createAndActivateUser, so its local data can be migrated
      // onto the new record below.
      final oldUser = await db.getActiveUser();

      // Convert selected subjects to JSON string
      final subjectsJson = jsonEncode(_selectedSubjects.toList());

      await db.createAndActivateUser(
        UsersTableCompanion(
          id: Value(userId),
          email: Value(widget.email),
          name: Value(name),
          avatarIndex: Value(_selectedAvatarIndex),
          selectedSubjects: Value(subjectsJson),
          isEmailValidated: Value(widget.isEmailValidated), // May be false if user skipped verification offline
          isActive: const Value(true),
          syncStatus: const Value(1), // pending sync
        ),
      );

      // Migrate local data (course enrollments in progress, progress, stats,
      // bookmarks, ...) from the previous guest user to the new full-profile
      // record. Without this the guest's rows stay keyed to the old guest UUID
      // and disappear from the course list after the upgrade (BR-4FTCFH).
      // Mirrors _saveExistingUserToDatabase in email_validation_providers.dart.
      if (oldUser != null && oldUser.id != userId) {
        await db.migrateUserData(oldUser.id, userId);
      }

      // Sync user with server (register/login on backend)
      final syncSuccess = await ref
          .read(emailVerificationProvider.notifier)
          .syncUserWithServer();

      if (!syncSuccess && mounted) {
        // Show warning but still proceed - user can sync later
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.profileSetupSyncWarning),
            backgroundColor: AppColors.warning,
          ),
        );
      }

      // Proceed to main app
      widget.onComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.profileSetupSaveError('$e')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Headline
              Text(
                AppStrings.profileSetupTitle,
                    style: AppTextStyles.heading1().copyWith(height: 1.2),
                  ),
                  const SizedBox(height: 24),
                  // Name section label
                  Text(
                    AppStrings.profileSetupNameLabel,
                    style: AppTextStyles.cardTitle(),
                  ),
                  const SizedBox(height: 8),
                  // Name input
                  Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(
                        color: AppColors.primaryDark16,
                        width: 1,
                      ),
                      borderRadius: AppDecorations.radiusM,
                    ),
                    child: TextField(
                      controller: _nameController,
                      style: AppTextStyles.bodyLarge(),
                      decoration: InputDecoration(
                        hintText: AppStrings.profileSetupNameHint,
                        hintStyle: AppTextStyles.bodyLarge(color: AppColors.primaryDark48),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 20,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
              const SizedBox(height: 130), // Space for bottom bar
            ],
          ),
        ),
      ),
      // Bottom bar with button
      bottomSheet: Container(
        height: 114,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDark16,
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _handleContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primaryDark48,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppDecorations.radiusM,
                  ),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            AppStrings.actionContinue,
                            style: AppTextStyles.buttonLarge(color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward, size: 20),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: 6,
      itemBuilder: (context, index) {
        final isSelected = _selectedAvatarIndex == index;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedAvatarIndex = index;
            });
          },
          child: Container(
            width: 109,
            height: 109,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppDecorations.radiusXL,
              border: Border.all(
                color: isSelected
                    ? AppColors.progressFill
                    : AppColors.primaryDark12,
                width: isSelected ? 4 : 1,
              ),
            ),
            child: Center(
              child: Image.asset(
                'assets/images/avatar_${index + 1}.png',
                width: 64,
                height: 64,
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubjectsGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.3,
      ),
      itemCount: _subjects.length,
      itemBuilder: (context, index) {
        final subject = _subjects[index];
        final isSelected = _selectedSubjects.contains(index);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedSubjects.remove(index);
              } else {
                _selectedSubjects.add(index);
              }
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppDecorations.radiusXL,
              border: Border.all(
                color: isSelected
                    ? AppColors.progressFill
                    : AppColors.primaryDark12,
                width: isSelected ? 4 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: subject.color,
                    borderRadius: AppDecorations.radiusM,
                  ),
                  child: Center(
                    child: Text(
                      subject.emoji,
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subject.name,
                  style: AppTextStyles.actionSmall(
                    color: isSelected
                        ? AppColors.progressFill
                        : AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SubjectItem {
  final String name;
  final String emoji;
  final Color color;

  SubjectItem({
    required this.name,
    required this.emoji,
    required this.color,
  });
}
