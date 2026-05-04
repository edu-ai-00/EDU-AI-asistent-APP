/// API endpoint constants for the Laravel backend.
class ApiEndpoints {
  ApiEndpoints._();

  /// Base URL for the API.
  /// Override at build time: flutter build web --dart-define=API_URL=https://app-api-stage.edu-ai.eu
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://app-api.edu-ai.eu',
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // Guest Authentication
  // ═══════════════════════════════════════════════════════════════════════════

  /// POST - Register a guest user. Returns Sanctum token.
  /// Body: { device_id, name }
  static const String guestRegister = '/api/guest/register';

  /// POST - Claim/upgrade guest to full user with email.
  /// Body: { email } (requires auth token from guest register)
  static const String guestClaim = '/api/guest/claim';

  // ═══════════════════════════════════════════════════════════════════════════
  // Authentication
  // ═══════════════════════════════════════════════════════════════════════════

  /// POST - Create account, returns token.
  static const String register = '/api/register';

  /// POST - Register/sync after email verification (no password required).
  static const String registerVerified = '/api/register-verified';

  /// POST - Login, returns token.
  static const String login = '/api/login';

  /// POST - Resolve a code (course PIN or student login code).
  /// Body: { code }
  /// Returns: { type: "course"|"user", course?: {...}, token?: "...", user?: {...} }
  static const String resolveCode = '/api/resolve-code';

  /// POST - Invalidate token (requires auth).
  static const String logout = '/api/logout';

  /// POST - Rotate access token. Preserves shared_device flag and
  /// session_started_at; returns 401 when shared session exceeds 8h cap.
  static const String authRefresh = '/api/auth/refresh';

  /// GET - Get authenticated user (requires auth).
  static const String user = '/api/user';

  /// PUT - Update user profile (name, avatar, etc.).
  static const String updateProfile = '/api/user/profile';

  // ═══════════════════════════════════════════════════════════════════════════
  // Courses
  // ═══════════════════════════════════════════════════════════════════════════

  /// GET - List courses (published only for guests).
  /// POST - Create course (requires auth).
  static const String courses = '/api/courses';

  /// GET - Get single course.
  /// PUT - Update course (requires auth).
  /// DELETE - Soft delete course (requires auth).
  static String course(int id) => '/api/courses/$id';

  /// GET - Lookup course by PIN (e.g., "987654").
  static String courseByCode(String code) => '/api/courses/pin/$code';

  /// GET - Check for updates since timestamp.
  static const String coursesCheckUpdates = '/api/courses/check-updates';

  /// GET - Get signed download URL for full course JSON from R2.
  static String courseDownload(int id) => '/api/courses/$id/download';

  // ═══════════════════════════════════════════════════════════════════════════
  // Email Validation
  // ═══════════════════════════════════════════════════════════════════════════

  /// POST - Check if email already exists.
  static const String emailCheck = '/api/email/check';

  /// POST - Send verification code to email.
  static const String emailSendCode = '/api/email/send-code';

  /// POST - Verify the code sent to email.
  static const String emailVerify = '/api/email/verify';

  // ═══════════════════════════════════════════════════════════════════════════
  // User Courses
  // ═══════════════════════════════════════════════════════════════════════════

  /// GET - List user's courses.
  /// POST - Add a course to user's library.
  static const String userCourses = '/api/user/courses';

  /// PUT - Update progress for a user course.
  /// DELETE - Remove a course from user's library.
  /// Accepts course_id string (e.g. "ZS_MAT_ZLOMKY_5") or numeric courses.id.
  static String userCourse(String courseId) => '/api/user/courses/$courseId';

  // ═══════════════════════════════════════════════════════════════════════════
  // User Progress (per-lesson answers, block states)
  // ═══════════════════════════════════════════════════════════════════════════

  /// POST - Bulk upsert lesson progress + answers.
  /// GET  - Pull all progress (supports ?since= for incremental sync).
  static const String userProgress = '/api/user/progress';

  /// POST - Submit quiz attempt results.
  /// GET  - Get quiz attempts (supports ?course_id= filter).
  static const String quizAttempts = '/api/user/quiz-attempts';

  // ═══════════════════════════════════════════════════════════════════════════
  // User Stats
  // ═══════════════════════════════════════════════════════════════════════════

  /// GET - Get user's stats (level, XP, streak, etc.).
  /// PUT - Update user's stats (streak only).
  static const String userStats = '/api/user/stats';

  // ═══════════════════════════════════════════════════════════════════════════
  // User Bookmarks
  // ═══════════════════════════════════════════════════════════════════════════

  /// GET - List all bookmarks for the authenticated user.
  /// POST - Create a new bookmark.
  static const String userBookmarks = '/api/user/bookmarks';

  /// POST - Bulk sync bookmarks (send all local bookmarks).
  static const String userBookmarksSync = '/api/user/bookmarks/sync';

  /// POST - Remove a bookmark by composite key (course_id + block_id).
  /// Used when app doesn't have the server ID (offline-created bookmarks).
  static const String userBookmarksDelete = '/api/user/bookmarks/delete';

  // ═══════════════════════════════════════════════════════════════════════════
  // Content Feedback
  // ═══════════════════════════════════════════════════════════════════════════

  /// POST - Submit content feedback (question, like, dislike).
  /// Body: { course_id, block_id, lesson_id?, type, message? }
  static const String contentFeedback = '/api/content-feedback';

  // ═══════════════════════════════════════════════════════════════════════════
  // Image Proxy
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════════════════════
  // ELO / Adaptive Learning
  // ═══════════════════════════════════════════════════════════════════════════

  /// GET - Get user's ELO profile (profil_elo, profil_pocet).
  /// PUT - Update user's ELO profile.
  static const String userEloProfile = '/api/user/elo-profile';

  /// POST - Log a single ELO interaction.
  static const String eloInteractions = '/api/elo/interactions';

  /// POST - Batch log ELO interactions (offline sync).
  static const String eloInteractionsBatch = '/api/elo/interactions/batch';

  /// GET - Get block stats (item_pocet). Supports ?block_ids=id1,id2 filter.
  static const String blockStats = '/api/blocks/stats';

  // ═══════════════════════════════════════════════════════════════════════════
  // Image Proxy
  // ═══════════════════════════════════════════════════════════════════════════

  /// GET - Proxy an external image to avoid CORS on Flutter web.
  /// Query: ?url=<url-encoded-image-url>
  static const String proxyImage = '/api/proxy/image';

  // ═══════════════════════════════════════════════════════════════════════════
  // Gamification Config & Achievements
  // ═══════════════════════════════════════════════════════════════════════════

  /// GET - Public, returns versioned gamification config JSON
  /// (trophies, goals, challenges, levels).
  static const String gamificationConfig = '/api/gamification/config';

  /// GET - List user's earned achievements.
  /// POST - Push earned achievements (idempotent).
  static const String userAchievements = '/api/user/achievements';

  // ═══════════════════════════════════════════════════════════════════════════
  // User Themes
  // ═══════════════════════════════════════════════════════════════════════════

  /// GET  - List user's custom themes.
  /// POST - Create/upsert a custom theme.
  static const String userThemes = '/api/user/themes';

  /// POST - Bulk sync all custom themes.
  static const String userThemesSync = '/api/user/themes/sync';

  /// PUT    - Update a theme by server ID.
  /// DELETE - Delete a theme by server ID.
  static String userTheme(int id) => '/api/user/themes/$id';

  /// POST - Activate a theme (deactivates others server-side).
  static String userThemeActivate(int id) => '/api/user/themes/$id/activate';

  // ═══════════════════════════════════════════════════════════════════════════
  // Debug Reports
  // ═══════════════════════════════════════════════════════════════════════════

  /// POST - Send a diagnostic debug report (direct API call).
  static const String debugReports = '/api/debug-reports';

  // ═══════════════════════════════════════════════════════════════════════════
  // Chat
  // ═══════════════════════════════════════════════════════════════════════════

  /// GET - List user's chat sessions (supports ?since= for incremental pull).
  /// POST - Create a new chat session.
  static const String chatSessions = '/api/chat/sessions';

  /// DELETE - Delete a chat session.
  static String chatSession(int id) => '/api/chat/sessions/$id';

  /// GET - Get messages for a session (supports ?since=).
  /// POST - Send a user message (returns user + assistant message IDs).
  static String chatMessages(int sessionId) => '/api/chat/sessions/$sessionId/messages';

  /// GET - SSE stream for AI response. Query: ?message_id=<assistantMsgId>
  static String chatStream(int sessionId) => '/api/chat/sessions/$sessionId/stream';

  /// GET - Pull all new messages across all sessions (supports ?since=).
  static const String chatMessagesAll = '/api/chat/messages';

  /// PUT - Update feedback on a message.
  static String chatMessageFeedback(int messageId) => '/api/chat/messages/$messageId/feedback';
}
