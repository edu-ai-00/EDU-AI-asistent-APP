import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import 'block_model.dart';
export 'block_model.dart';

/// Status of a lesson
enum LessonStatus {
  completed,
  inProgress,
  locked,
}

/// Type of exercise question
enum ExerciseQuestionType {
  singleSelect,      // Simple radio button selection
  singleSelectImage, // Radio selection with image+description
  multiSelect,       // Multiple selection chips
  freeText,          // Open text input
}

/// Answer result state
enum AnswerResult {
  unanswered,
  correct,
  incorrect,
}

/// Model for single select option
class ExerciseOption {
  final String id;
  final String text;
  final String? description;
  final String? imageUrl;
  final bool isCorrect;

  const ExerciseOption({
    required this.id,
    required this.text,
    this.description,
    this.imageUrl,
    this.isCorrect = false,
  });
}

/// Model for an exercise question
class ExerciseQuestion {
  final String id;
  final String question;
  final ExerciseQuestionType type;
  final List<ExerciseOption> options;
  final String? correctAnswer; // For free text questions
  final String explanation;
  final int xpReward;

  const ExerciseQuestion({
    required this.id,
    required this.question,
    required this.type,
    this.options = const [],
    this.correctAnswer,
    required this.explanation,
    this.xpReward = 12,
  });

  /// Check if the given answer is correct
  bool checkAnswer(dynamic answer) {
    switch (type) {
      case ExerciseQuestionType.singleSelect:
      case ExerciseQuestionType.singleSelectImage:
        return options.any((o) => o.id == answer && o.isCorrect);
      case ExerciseQuestionType.multiSelect:
        if (answer is! Set<String>) return false;
        final correctIds = options.where((o) => o.isCorrect).map((o) => o.id).toSet();
        return answer.length == correctIds.length && answer.containsAll(correctIds);
      case ExerciseQuestionType.freeText:
        if (correctAnswer == null) return true;
        final userAnswer = (answer as String).toLowerCase().trim();
        return userAnswer.contains(correctAnswer!.toLowerCase());
    }
  }

  /// Get correct answer text for display
  String getCorrectAnswerText() {
    switch (type) {
      case ExerciseQuestionType.singleSelect:
      case ExerciseQuestionType.singleSelectImage:
        return options.firstWhere((o) => o.isCorrect).text;
      case ExerciseQuestionType.multiSelect:
        return options.where((o) => o.isCorrect).map((o) => o.text).join(', ');
      case ExerciseQuestionType.freeText:
        return correctAnswer ?? '';
    }
  }
}

/// Model for an exercise session
class ExerciseSession {
  final String id;
  final String title;
  final String subtitle;
  final List<ExerciseQuestion> questions;
  final int totalXp;

  const ExerciseSession({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.questions,
    this.totalXp = 12,
  });
}

/// Mock exercise data
class MockExerciseData {
  static const ExerciseSession biologyExercise = ExerciseSession(
    id: '1',
    title: 'Procvičování',
    subtitle: 'Biologie — Buňky',
    totalXp: 12,
    questions: [
      // Single select (simple)
      ExerciseQuestion(
        id: '1',
        question: 'Která organela je odpovědná za výrobu energie v buňce?',
        type: ExerciseQuestionType.singleSelect,
        options: [
          ExerciseOption(id: 'a', text: 'Jádro', isCorrect: false),
          ExerciseOption(id: 'b', text: 'Mitochondrie', isCorrect: true),
          ExerciseOption(id: 'c', text: 'Ribozony', isCorrect: false),
          ExerciseOption(id: 'd', text: 'Golgiho aparát', isCorrect: false),
        ],
        explanation: 'Mitochondrie jsou často nazývány "elektrárnou buňky", protože přeměňují živiny na energii ve formě ATP, kterou buňka využívá pro své životní procesy.',
      ),
      // Single select with images
      ExerciseQuestion(
        id: '2',
        question: 'Který z těchto organismů patří mezi savce?',
        type: ExerciseQuestionType.singleSelectImage,
        options: [
          ExerciseOption(
            id: 'a',
            text: 'Netopýr',
            description: 'Malý létající živočich, který se orientuje pomocí echolokace.',
            imageUrl: 'bat',
            isCorrect: true,
          ),
          ExerciseOption(
            id: 'b',
            text: 'Orel skalní',
            description: 'Dravec s vynikajícím zrakem, patří mezi ptáky.',
            imageUrl: 'eagle',
            isCorrect: false,
          ),
          ExerciseOption(
            id: 'c',
            text: 'Rosnička zelená',
            description: 'Drobné obojživelník žijící převážně v korunách stromů.',
            imageUrl: 'frog',
            isCorrect: false,
          ),
          ExerciseOption(
            id: 'd',
            text: 'Tučňák',
            description: 'Nelétavý pták žijící v chladných oblastech, výborný plavec.',
            imageUrl: 'penguin',
            isCorrect: false,
          ),
        ],
        explanation: 'Netopýr je jediný savec schopný aktivního letu. Přestože létá, je to savec – rodí živá mláďata a kojí je mlékem.',
      ),
      // Multi-select
      ExerciseQuestion(
        id: '3',
        question: 'Které z následujících buněčných organel jsou přímo zodpovědné za produkci energie v buňce?',
        type: ExerciseQuestionType.multiSelect,
        options: [
          ExerciseOption(id: 'a', text: 'Mitochondrie', isCorrect: true),
          ExerciseOption(id: 'b', text: 'Ribozomy', isCorrect: false),
          ExerciseOption(id: 'c', text: 'Golgiho aparát', isCorrect: false),
          ExerciseOption(id: 'd', text: 'Chloroplasty', isCorrect: true),
          ExerciseOption(id: 'e', text: 'Cytoplazma', isCorrect: false),
          ExerciseOption(id: 'f', text: 'Buněčné jádro', isCorrect: false),
        ],
        explanation: 'Mitochondrie produkují ATP oxidací živin. Chloroplasty (v rostlinných buňkách) produkují energii fotosyntézou.',
      ),
      // Free text
      ExerciseQuestion(
        id: '4',
        question: 'Jaká organela v buňce produkuje energii?',
        type: ExerciseQuestionType.freeText,
        correctAnswer: 'mitochondrie',
        explanation: 'Mitochondrie jsou organely zodpovědné za buněčné dýchání a produkci ATP – hlavního zdroje energie pro buňku.',
      ),
      // Another single select
      ExerciseQuestion(
        id: '5',
        question: 'Co je základní jednotkou všech živých organismů?',
        type: ExerciseQuestionType.singleSelect,
        options: [
          ExerciseOption(id: 'a', text: 'Atom', isCorrect: false),
          ExerciseOption(id: 'b', text: 'Molekula', isCorrect: false),
          ExerciseOption(id: 'c', text: 'Buňka', isCorrect: true),
          ExerciseOption(id: 'd', text: 'Tkáň', isCorrect: false),
        ],
        explanation: 'Buňka je základní stavební a funkční jednotkou všech živých organismů. Všechny organismy jsou tvořeny jednou nebo více buňkami.',
      ),
      // Multi-select
      ExerciseQuestion(
        id: '6',
        question: 'Které z následujících procesů probíhají v mitochondriích?',
        type: ExerciseQuestionType.multiSelect,
        options: [
          ExerciseOption(id: 'a', text: 'Buněčné dýchání', isCorrect: true),
          ExerciseOption(id: 'b', text: 'Fotosyntéza', isCorrect: false),
          ExerciseOption(id: 'c', text: 'Produkce ATP', isCorrect: true),
          ExerciseOption(id: 'd', text: 'Syntéza proteinů', isCorrect: false),
        ],
        explanation: 'V mitochondriích probíhá buněčné dýchání, při kterém se z glukózy vytváří ATP – hlavní energetická měna buňky.',
      ),
      // Single select
      ExerciseQuestion(
        id: '7',
        question: 'Která struktura chrání rostlinnou buňku?',
        type: ExerciseQuestionType.singleSelect,
        options: [
          ExerciseOption(id: 'a', text: 'Buněčná membrána', isCorrect: false),
          ExerciseOption(id: 'b', text: 'Buněčná stěna', isCorrect: true),
          ExerciseOption(id: 'c', text: 'Cytoplazma', isCorrect: false),
          ExerciseOption(id: 'd', text: 'Vakuola', isCorrect: false),
        ],
        explanation: 'Buněčná stěna je pevná vnější vrstva rostlinných buněk, která jim poskytuje strukturální podporu a ochranu.',
      ),
      // Free text
      ExerciseQuestion(
        id: '8',
        question: 'Jak se nazývá proces, při kterém buňka pohlcuje velké částice?',
        type: ExerciseQuestionType.freeText,
        correctAnswer: 'fagocytóza',
        explanation: 'Fagocytóza je proces, při kterém buňka pohlcuje velké částice nebo jiné buňky tím, že je obalí svou membránou.',
      ),
      // Single select with images
      ExerciseQuestion(
        id: '9',
        question: 'Který z těchto organismů je jednobuněčný?',
        type: ExerciseQuestionType.singleSelectImage,
        options: [
          ExerciseOption(
            id: 'a',
            text: 'Améba',
            description: 'Jednobuněčný organismus měnící tvar pomocí panožek.',
            imageUrl: 'amoeba',
            isCorrect: true,
          ),
          ExerciseOption(
            id: 'b',
            text: 'Medúza',
            description: 'Mořský živočich s průsvitným tělem ve tvaru zvonu.',
            imageUrl: 'jellyfish',
            isCorrect: false,
          ),
          ExerciseOption(
            id: 'c',
            text: 'Housenka',
            description: 'Larva motýla živící se listy rostlin.',
            imageUrl: 'caterpillar',
            isCorrect: false,
          ),
          ExerciseOption(
            id: 'd',
            text: 'Korál',
            description: 'Mořský organismus tvořící útesy.',
            imageUrl: 'coral',
            isCorrect: false,
          ),
        ],
        explanation: 'Améba je jednobuněčný organismus ze skupiny prvoků. Pohybuje se pomocí panožek a živí se fagocytózou.',
      ),
      // Final single select
      ExerciseQuestion(
        id: '10',
        question: 'Co je hlavní funkcí ribozomů?',
        type: ExerciseQuestionType.singleSelect,
        options: [
          ExerciseOption(id: 'a', text: 'Produkce energie', isCorrect: false),
          ExerciseOption(id: 'b', text: 'Syntéza proteinů', isCorrect: true),
          ExerciseOption(id: 'c', text: 'Skladování vody', isCorrect: false),
          ExerciseOption(id: 'd', text: 'Trávení buněčného odpadu', isCorrect: false),
        ],
        explanation: 'Ribozomy jsou buněčné struktury zodpovědné za syntézu proteinů podle instrukcí z mRNA.',
      ),
    ],
  );
}

/// Type of content block in a lesson
enum LessonBlockType {
  text,        // Simple text content
  image,       // Image with description
  video,       // Video content
  keyConcepts, // Bullet points with key concepts
  quiz,        // Multiple choice question
}

/// Model for a key concept item
class KeyConcept {
  final String term;
  final String definition;

  const KeyConcept({
    required this.term,
    required this.definition,
  });
}

/// Model for a quiz option
class QuizOption {
  final String id;
  final String text;
  final bool isCorrect;

  const QuizOption({
    required this.id,
    required this.text,
    this.isCorrect = false,
  });
}

/// Model for a content block within a lesson
class LessonBlock {
  final String id;
  final String title;
  final String content;
  final LessonBlockType type;
  final bool isCompleted;
  final bool isBookmarked;
  final bool isLiked;
  final bool isDisliked;
  // Image block
  final String? imageUrl;
  final String? imageEmoji;
  // Video block
  final String? videoUrl;
  final String? videoThumbnail;
  final String? videoDuration;
  // Key concepts block
  final List<KeyConcept>? keyConcepts;
  // Quiz block
  final String? quizQuestion;
  final List<QuizOption>? quizOptions;
  final String? selectedOptionId;

  const LessonBlock({
    required this.id,
    required this.title,
    required this.content,
    this.type = LessonBlockType.text,
    this.isCompleted = false,
    this.isBookmarked = false,
    this.isLiked = false,
    this.isDisliked = false,
    this.imageUrl,
    this.imageEmoji,
    this.videoUrl,
    this.videoThumbnail,
    this.videoDuration,
    this.keyConcepts,
    this.quizQuestion,
    this.quizOptions,
    this.selectedOptionId,
  });

  LessonBlock copyWith({
    String? id,
    String? title,
    String? content,
    LessonBlockType? type,
    bool? isCompleted,
    bool? isBookmarked,
    bool? isLiked,
    bool? isDisliked,
    String? imageUrl,
    String? imageEmoji,
    String? videoUrl,
    String? videoThumbnail,
    String? videoDuration,
    List<KeyConcept>? keyConcepts,
    String? quizQuestion,
    List<QuizOption>? quizOptions,
    String? selectedOptionId,
  }) {
    return LessonBlock(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      type: type ?? this.type,
      isCompleted: isCompleted ?? this.isCompleted,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      isLiked: isLiked ?? this.isLiked,
      isDisliked: isDisliked ?? this.isDisliked,
      imageUrl: imageUrl ?? this.imageUrl,
      imageEmoji: imageEmoji ?? this.imageEmoji,
      videoUrl: videoUrl ?? this.videoUrl,
      videoThumbnail: videoThumbnail ?? this.videoThumbnail,
      videoDuration: videoDuration ?? this.videoDuration,
      keyConcepts: keyConcepts ?? this.keyConcepts,
      quizQuestion: quizQuestion ?? this.quizQuestion,
      quizOptions: quizOptions ?? this.quizOptions,
      selectedOptionId: selectedOptionId ?? this.selectedOptionId,
    );
  }
}

/// Model for a lesson within a course
class Lesson {
  final String id;
  final String title;
  final String subtitle;
  final String iconEmoji;
  final LessonStatus status;
  final int questionCount;
  final int durationMinutes;
  final int xpReward;
  final List<LessonBlock> blocks;

  const Lesson({
    required this.id,
    required this.title,
    this.subtitle = '',
    required this.iconEmoji,
    required this.status,
    required this.questionCount,
    required this.durationMinutes,
    this.xpReward = 15,
    this.blocks = const [],
  });

  int get totalBlocks => blocks.length;
  int get completedBlocks => blocks.where((b) => b.isCompleted).length;
}

/// Model for a quiz within a course
class Quiz {
  final String id;
  final String title;
  final int questionCount;

  const Quiz({
    required this.id,
    required this.title,
    required this.questionCount,
  });
}

/// Header image for a course
class CourseHeaderImage {
  final String url;
  final String? alt;

  const CourseHeaderImage({
    required this.url,
    this.alt,
  });

  factory CourseHeaderImage.fromJson(Map<String, dynamic> json) {
    return CourseHeaderImage(
      url: json['url'] as String? ?? '',
      alt: json['alt'] as String?,
    );
  }
}

/// Model for a course
class Course {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final String? coverImageUrl;
  final String iconEmoji;
  final Color iconBackgroundColor;
  final String badge;
  final String difficulty;
  final int lessonCount;
  final int durationHours;
  final int durationMinutes; // Total duration in minutes (sum of all lessons)
  final int completedLessons;
  final bool isCompleted;
  final bool isBookmarked;
  final bool startsWithQuiz;
  final String? exportType;  // "course_v2", "exercise_v2", "quiz_v2"
  final bool onlyOnce;       // When true, blocks re-entry after completion
  final bool isPrivate;      // When true, course is hidden from listings and accessible only via PIN
  final bool quizEvaluate;   // When true, quiz shows correct/incorrect feedback and score
  final bool onlyQuiz;       // When true, course runs only as a quiz — no lessons
  final int? maxXp;          // Maximum XP earnable from this course (hard cap)
  final List<Lesson> lessons;
  final List<Quiz> quizzes;
  final CourseHeaderImage? headerImage;

  /// Raw course data for loading blocks on demand
  final Map<String, dynamic>? _rawData;

  const Course({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    this.coverImageUrl,
    required this.iconEmoji,
    required this.iconBackgroundColor,
    required this.badge,
    required this.difficulty,
    required this.lessonCount,
    required this.durationHours,
    this.durationMinutes = 0,
    required this.completedLessons,
    this.isCompleted = false,
    this.isBookmarked = false,
    this.startsWithQuiz = false,
    this.exportType,
    this.onlyOnce = false,
    this.isPrivate = false,
    this.quizEvaluate = false,
    this.onlyQuiz = false,
    this.maxXp,
    required this.lessons,
    required this.quizzes,
    this.headerImage,
    Map<String, dynamic>? rawData,
  }) : _rawData = rawData;

  double get progress => lessonCount > 0 ? completedLessons / lessonCount : 0.0;

  /// Check if this course has block_v2 format data
  bool get hasBlockV2Data =>
      _rawData != null && BlockLoader.isBlockV2Format(_rawData);

  /// Load blocks for a specific lesson (by lesson ID)
  List<ContentBlock> getBlocksForLesson(String lessonId) {
    if (_rawData == null) return [];
    return BlockLoader.loadBlocksForLesson(
      courseData: _rawData,
      lessonId: lessonId,
    );
  }

  /// Load blocks for a lesson by index
  List<ContentBlock> getBlocksForLessonIndex(int index) {
    if (index < 0 || index >= lessons.length) return [];
    return getBlocksForLesson(lessons[index].id);
  }

  /// Find which lesson contains a given block ID.
  /// Returns (lessonId, lessonIndex) or null if not found.
  ({String lessonId, int lessonIndex})? findLessonForBlock(String blockId) {
    if (_rawData == null) return null;
    final lessons = _rawData['lessons'] as List<dynamic>? ?? [];
    for (int i = 0; i < lessons.length; i++) {
      final lesson = lessons[i] as Map<String, dynamic>;
      final lessonBlocks = lesson['blocks'] as List<dynamic>?;
      final blockIds = lesson['block_ids'] as List<dynamic>?;
      if (lessonBlocks != null) {
        for (final b in lessonBlocks) {
          if ((b as Map<String, dynamic>)['block_id'] == blockId) {
            return (lessonId: lesson['lesson_id'] as String, lessonIndex: i);
          }
        }
      } else if (blockIds != null) {
        if (blockIds.contains(blockId)) {
          return (lessonId: lesson['lesson_id'] as String, lessonIndex: i);
        }
      }
    }
    return null;
  }

  /// Get block bindings for a lesson (metadata like bg_color, default_practice)
  List<LessonBlockBinding> getBlockBindingsForLesson(String lessonId) {
    if (_rawData == null) return [];
    return BlockLoader.getBlockBindingsForLesson(
      courseData: _rawData,
      lessonId: lessonId,
    );
  }

  /// Load blocks with their bindings for a lesson
  List<({ContentBlock block, LessonBlockBinding binding})> getBlocksWithBindings(String lessonId) {
    if (_rawData == null) return [];
    return BlockLoader.loadBlocksWithBindings(
      courseData: _rawData,
      lessonId: lessonId,
    );
  }

  /// Extract block IDs that the user has completed across all lessons + quiz.
  static Set<String> extractCompletedBlockIds(Map<String, dynamic>? progressData) {
    final completed = <String>{};
    if (progressData == null) return completed;
    // From lessons
    final lessons = progressData['lessons'] as Map<String, dynamic>? ?? {};
    for (final lessonData in lessons.values) {
      final map = lessonData as Map<String, dynamic>?;
      final blocks = map?['completed_blocks'] as List<dynamic>? ?? [];
      for (final b in blocks) {
        if (b is String) completed.add(b);
      }
    }
    // From quiz (user can do quiz before lessons)
    final quizAnswers = progressData['quiz_answers'] as Map<String, dynamic>?;
    if (quizAnswers != null) completed.addAll(quizAnswers.keys);
    return completed;
  }

  /// Compute total course duration in minutes from raw course JSON,
  /// matching the per-lesson logic in [Course.fromJsonData] so that the
  /// library card and the course-detail header agree.
  static int totalCourseMinutes(Map<String, dynamic> data) {
    final blocks = (data['blocks'] as List<dynamic>?) ?? const [];
    final blockDataMap = <String, Map<String, dynamic>>{};
    for (final b in blocks) {
      if (b is Map<String, dynamic>) {
        final id = b['block_id'] as String?;
        if (id != null) blockDataMap[id] = b;
      }
    }

    int total = 0;
    final lessons = (data['lessons'] as List<dynamic>?) ?? const [];
    for (final l in lessons) {
      if (l is! Map<String, dynamic>) continue;
      final lessonBlocks = (l['blocks'] as List<dynamic>?) ?? const [];
      int lessonMin = 0;
      bool hasAnyDuration = false;
      for (final binding in lessonBlocks) {
        if (binding is! Map<String, dynamic>) continue;
        final bid = binding['block_id'] as String?;
        final bd = bid != null ? blockDataMap[bid] : null;
        if (bd == null) continue;
        final dur = bd['duration'];
        if (dur is int && dur > 0) {
          lessonMin += dur;
          hasAnyDuration = true;
        } else if (dur is String) {
          final m = RegExp(r'(\d+)').firstMatch(dur);
          if (m != null) {
            lessonMin += int.tryParse(m.group(1)!) ?? 0;
            hasAnyDuration = true;
          }
        } else if (bd['duration_minutes'] is int &&
            (bd['duration_minutes'] as int) > 0) {
          lessonMin += bd['duration_minutes'] as int;
          hasAnyDuration = true;
        }
      }
      final clamped = hasAnyDuration
          ? lessonMin.clamp(1, 120)
          : (lessonBlocks.length * 4).clamp(5, 60);
      total += clamped;
    }
    return total;
  }

  /// Returns true if any step inside the given block JSON has
  /// `default_practice: true`. Steps may be either an array (V2) or a map
  /// keyed by step id (legacy).
  static bool _hasStepDefaultPractice(Map<String, dynamic> blockJson) {
    final steps = blockJson['steps'];
    if (steps is List) {
      for (final s in steps) {
        if (s is Map && s['default_practice'] == true) return true;
      }
    } else if (steps is Map) {
      for (final s in steps.values) {
        if (s is Map && s['default_practice'] == true) return true;
      }
    }
    return false;
  }

  /// Get all blocks marked as default_practice — either in the lesson binding
  /// or on the block JSON itself. Always included in Cvičení.
  ///
  /// [completedBlockIds] — if provided, only return blocks the user has completed.
  /// [removedBlockIds] — if provided, exclude blocks the user explicitly unbookmarked.
  List<ContentBlock> getDefaultPracticeBlocks({
    Set<String>? completedBlockIds,
    Set<String>? removedBlockIds,
  }) {
    if (_rawData == null) return [];

    final blocks = _rawData['blocks'] as List<dynamic>? ?? [];
    final lessonsJson = _rawData['lessons'] as List<dynamic>? ?? [];

    // Build a lookup map from block_id to block JSON
    final blockMap = <String, Map<String, dynamic>>{};
    for (final b in blocks) {
      final blockJson = b as Map<String, dynamic>;
      final blockId = blockJson['block_id'] as String?;
      if (blockId != null) {
        blockMap[blockId] = blockJson;
      }
    }

    // Iterate lessons in order, checking both binding and block-level default_practice
    final result = <ContentBlock>[];
    final seen = <String>{};
    for (final l in lessonsJson) {
      final lesson = l as Map<String, dynamic>;
      final lessonBlocks = lesson['blocks'] as List<dynamic>?;
      if (lessonBlocks == null) continue;

      final refs = lessonBlocks
          .map((b) => b as Map<String, dynamic>)
          .toList();
      refs.sort((a, b) {
        final orderA = a['order'] as int? ?? 0;
        final orderB = b['order'] as int? ?? 0;
        return orderA.compareTo(orderB);
      });

      for (final ref in refs) {
        final blockId = ref['block_id'] as String?;
        if (blockId == null) continue;
        if (!seen.add(blockId)) continue;

        // Check binding-level OR block-level OR step-level default_practice.
        // Step-level applies to display blocks: any step with default_practice=true
        // promotes the whole block into the practice queue.
        final bindingPractice = ref['default_practice'] as bool? ?? false;
        final blockJson = blockMap[blockId];
        if (blockJson == null) continue;
        final blockPractice = blockJson['default_practice'] as bool? ?? false;
        final stepPractice = _hasStepDefaultPractice(blockJson);

        if (!bindingPractice && !blockPractice && !stepPractice) continue;
        result.add(ContentBlock.fromJson(blockJson));
      }
    }

    // Also include unassigned blocks with default_practice on the block itself
    // or on any of their steps.
    for (final entry in blockMap.entries) {
      if (seen.contains(entry.key)) continue;
      final hasBlockFlag = entry.value['default_practice'] == true;
      final hasStepFlag = _hasStepDefaultPractice(entry.value);
      if (!hasBlockFlag && !hasStepFlag) continue;
      result.add(ContentBlock.fromJson(entry.value));
    }

    // Filter: only completed blocks (makes Cvičení a review pool, not a spoiler)
    if (completedBlockIds != null) {
      result.retainWhere((b) => completedBlockIds.contains(b.blockId));
    }
    // Filter: exclude blocks the user explicitly unbookmarked
    if (removedBlockIds != null) {
      result.removeWhere((b) => removedBlockIds.contains(b.blockId));
    }

    return result;
  }

  /// Get exercise blocks: default_practice blocks merged with bookmarked blocks.
  /// Default practice blocks come first, then bookmarked (deduplicated).
  List<ContentBlock> getExerciseBlocks(
    List<ContentBlock> bookmarkedBlocks, {
    Set<String>? completedBlockIds,
    Set<String>? removedBlockIds,
  }) {
    final defaultBlocks = getDefaultPracticeBlocks(
      completedBlockIds: completedBlockIds,
      removedBlockIds: removedBlockIds,
    );
    final seen = <String>{};
    final result = <ContentBlock>[];
    for (final b in defaultBlocks) {
      if (seen.add(b.blockId)) result.add(b);
    }
    for (final b in bookmarkedBlocks) {
      if (seen.add(b.blockId)) result.add(b);
    }
    return result;
  }

  /// Get all question-type blocks from all lessons in the course.
  /// Used for quiz mode after course completion.
  /// Respects lesson block ordering rather than the flat blocks array order.
  List<ContentBlock> getAllQuestionBlocks() {
    if (_rawData == null) return [];

    final blocks = _rawData['blocks'] as List<dynamic>? ?? [];
    final lessons = _rawData['lessons'] as List<dynamic>? ?? [];

    // Build a lookup map from block_id to block JSON
    final blockMap = <String, Map<String, dynamic>>{};
    for (final b in blocks) {
      final blockJson = b as Map<String, dynamic>;
      final blockId = blockJson['block_id'] as String?;
      if (blockId != null) {
        blockMap[blockId] = blockJson;
      }
    }

    // Collect block IDs in lesson order (respecting each lesson's block order)
    final orderedBlockIds = <String>[];
    for (final l in lessons) {
      final lesson = l as Map<String, dynamic>;
      final lessonBlocks = lesson['blocks'] as List<dynamic>?;
      if (lessonBlocks != null) {
        final refs = lessonBlocks
            .map((b) => b as Map<String, dynamic>)
            .toList();
        refs.sort((a, b) {
          final orderA = a['order'] as int? ?? 0;
          final orderB = b['order'] as int? ?? 0;
          return orderA.compareTo(orderB);
        });
        for (final ref in refs) {
          final id = ref['block_id'] as String?;
          if (id != null) orderedBlockIds.add(id);
        }
      }
    }

    // Parse blocks in lesson order, filtering to exercise blocks with questions
    final questionBlocks = <ContentBlock>[];
    final includedIds = <String>{};
    for (final blockId in orderedBlockIds) {
      final blockJson = blockMap[blockId];
      if (blockJson == null) continue;
      final block = ContentBlock.fromJson(blockJson);
      includedIds.add(blockId);
      if (block.type == BlockType.exercise &&
          (block.atomicQuestion != null || block.hasV2Steps)) {
        questionBlocks.add(block);
      }
    }

    // Also include unassigned exercise blocks (not in any lesson)
    for (final entry in blockMap.entries) {
      if (includedIds.contains(entry.key)) continue;
      final block = ContentBlock.fromJson(entry.value);
      if (block.type == BlockType.exercise &&
          (block.atomicQuestion != null || block.hasV2Steps)) {
        questionBlocks.add(block);
      }
    }

    return questionBlocks;
  }

  /// Create a Course from downloaded JSON data and user progress.
  factory Course.fromJsonData({
    required String id,
    required Map<String, dynamic> data,
    int completedLessons = 0,
    bool isCompleted = false,
    bool isBookmarked = false,
    Map<String, dynamic>? lessonsProgress,
    String? fallbackName,
  }) {
    // Parse lessons from JSON
    final lessonsJson = data['lessons'] as List<dynamic>? ?? [];
    final lessons = <Lesson>[];

    // Build block lookup map for XP calculation
    final blocksData = data['blocks'] as List<dynamic>? ?? [];
    final blockDataMap = <String, Map<String, dynamic>>{};
    for (final b in blocksData) {
      if (b is Map<String, dynamic>) {
        final bid = b['block_id'] as String?;
        if (bid != null) blockDataMap[bid] = b;
      }
    }

    // Emoji options for lessons
    const lessonEmojis = ['📚', '📖', '✏️', '🎯', '💡', '🔬', '🧮', '📝', '🎓', '⭐'];

    for (int i = 0; i < lessonsJson.length; i++) {
      final lessonJson = lessonsJson[i] as Map<String, dynamic>;
      final lessonId = lessonJson['lesson_id'] as String? ?? 'lesson_$i';

      // Determine lesson status — prefer per-lesson is_completed flags from
      // progress data when available, fall back to sequential completedLessons
      // count, and ultimately to the course-level isCompleted flag.
      LessonStatus status;
      if (isCompleted) {
        // Course-level completion: all lessons are done regardless of
        // individual flags or completedLessons count (handles corrupted data
        // where completedLessons==0 but status=="completed").
        status = LessonStatus.completed;
      } else if (lessonsProgress != null) {
        final lp = lessonsProgress[lessonId] as Map<String, dynamic>?;
        final isLessonCompleted = lp?['is_completed'] == true;
        if (isLessonCompleted) {
          status = LessonStatus.completed;
        } else if (i < completedLessons) {
          // No is_completed flag but sequential count says done — treat as completed.
          // This handles data where _saveProgress overwrote the flag before the merge fix.
          status = LessonStatus.completed;
        } else if (i == completedLessons && i < lessonsJson.length) {
          status = LessonStatus.inProgress;
        } else if (lp != null) {
          // Lesson has a progress entry — user was here (possibly via cross-lesson jump)
          status = LessonStatus.inProgress;
        } else {
          status = LessonStatus.locked;
        }
      } else if (i < completedLessons) {
        status = LessonStatus.completed;
      } else if (i == completedLessons) {
        status = LessonStatus.inProgress;
      } else {
        status = LessonStatus.locked;
      }

      // Parse blocks for this lesson - count them as questions
      final blocksJson = lessonJson['blocks'] as List<dynamic>? ?? [];
      final blockCount = blocksJson.length;

      // Calculate duration: sum block durations from JSON, fall back to estimate
      int totalBlockDuration = 0;
      bool hasAnyDuration = false;
      for (final blockBinding in blocksJson) {
        final binding = blockBinding as Map<String, dynamic>;
        final blockId = binding['block_id'] as String?;
        final blockData = blockId != null ? blockDataMap[blockId] : null;
        if (blockData != null) {
          final dur = blockData['duration'];
          if (dur is int && dur > 0) {
            totalBlockDuration += dur;
            hasAnyDuration = true;
          } else if (dur is String) {
            final match = RegExp(r'(\d+)').firstMatch(dur);
            if (match != null) {
              totalBlockDuration += int.tryParse(match.group(1)!) ?? 0;
              hasAnyDuration = true;
            }
          } else if (blockData['duration_minutes'] is int && (blockData['duration_minutes'] as int) > 0) {
            totalBlockDuration += blockData['duration_minutes'] as int;
            hasAnyDuration = true;
          }
        }
      }
      // If no block has duration data, estimate ~4 min per block
      final durationMinutes = hasAnyDuration
          ? totalBlockDuration.clamp(1, 120)
          : (blockCount * 4).clamp(5, 60);

      // XP reward: sum of per-step XP across all blocks in this lesson
      // +1 per display step, +8 per question step (max possible)
      int xpReward = 0;
      for (final blockBinding in blocksJson) {
        final binding = blockBinding as Map<String, dynamic>;
        final blockId = binding['block_id'] as String?;
        final blockData = blockId != null ? blockDataMap[blockId] : null;
        if (blockData == null) {
          xpReward += 1; // Unknown block — give minimum
          continue;
        }
        xpReward += _calculateBlockMaxXp(blockData);
      }
      if (xpReward == 0) xpReward = 1;

      // Select emoji based on lesson index
      final emoji = lessonEmojis[i % lessonEmojis.length];

      lessons.add(Lesson(
        id: lessonJson['lesson_id'] as String? ?? 'lesson_$i',
        title: lessonJson['name'] as String? ?? 'Lekce ${i + 1}',
        subtitle: lessonJson['description'] as String? ?? '',
        iconEmoji: emoji,
        status: status,
        questionCount: blockCount,
        durationMinutes: durationMinutes,
        xpReward: xpReward,
        blocks: const [], // Blocks will be loaded separately when lesson is opened
      ));
    }

    // Parse quizzes if present
    final quizzesJson = data['quizzes'] as List<dynamic>? ?? [];
    final quizzes = quizzesJson.map((quizJson) {
      final quiz = quizJson as Map<String, dynamic>;
      return Quiz(
        id: quiz['id'] as String? ?? '',
        title: quiz['title'] as String? ?? '',
        questionCount: quiz['question_count'] as int? ?? 0,
      );
    }).toList();

    // Calculate duration
    final totalMinutes = lessons.fold<int>(0, (sum, l) => sum + l.durationMinutes);
    final durationHours = (totalMinutes / 60).ceil();

    // Parse header image
    CourseHeaderImage? headerImage;
    final headerImageData = data['header_image'];
    if (headerImageData is Map<String, dynamic>) {
      headerImage = CourseHeaderImage.fromJson(headerImageData);
    }

    final dataName = (data['name'] as String?)?.trim();
    final cleanFallback = (fallbackName ?? '').trim();
    final resolvedTitle = (dataName != null && dataName.isNotEmpty)
        ? dataName
        : (cleanFallback.isNotEmpty ? cleanFallback : 'Kurz');

    return Course(
      id: data['course_id'] as String? ?? id,
      title: resolvedTitle,
      subtitle: data['subtitle'] as String? ?? '',
      description: data['description'] as String? ?? '',
      iconEmoji: data['emoji'] as String? ?? '📖',
      iconBackgroundColor: _parseColor(data['icon_background_color'] as String?),
      badge: data['badge'] as String? ?? '',
      difficulty: data['difficulty'] as String? ?? 'ROOKIE',
      lessonCount: lessons.length,
      durationHours: durationHours,
      durationMinutes: totalMinutes,
      completedLessons: completedLessons,
      isCompleted: isCompleted,
      isBookmarked: isBookmarked,
      startsWithQuiz: data['starts_with_quiz'] as bool? ?? false,
      exportType: data['export_type'] as String?,
      onlyOnce: data['only_once'] as bool? ?? false,
      isPrivate: data['private'] as bool? ?? false,
      quizEvaluate: data['quiz_evaluate'] as bool? ?? false,
      onlyQuiz: data['only_quiz'] as bool? ?? false,
      maxXp: data['max_xp'] as int?,
      lessons: lessons,
      quizzes: quizzes,
      headerImage: headerImage,
      rawData: data, // Store raw data for block loading
    );
  }

  /// Parse color from hex string or return default.
  static Color _parseColor(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) {
      return AppColors.surfaceLight;
    }
    try {
      final hex = hexColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.surfaceLight;
    }
  }
}

/// Calculate max possible XP for a block from its JSON data.
/// +1 per display/text/image/video step, +8 per question/evaluation step.
/// For atomic blocks (no steps): +8 if question/exercise, +1 otherwise.
int _calculateBlockMaxXp(Map<String, dynamic> blockData) {
  int xp = 0;
  final steps = blockData['steps'];

  if (steps is List && steps.isNotEmpty) {
    // V2 list format: [{id, type, ...}, ...]
    for (final step in steps) {
      if (step is Map<String, dynamic>) {
        final type = step['type'] as String? ?? '';
        xp += (type == 'question' || type == 'evaluation') ? 8 : 1;
      }
    }
  } else if (steps is Map<String, dynamic> && steps.isNotEmpty) {
    // Legacy map format: {s1: {type: ...}, s2: ...}
    for (final entry in steps.entries) {
      if (entry.value is Map<String, dynamic>) {
        final type = (entry.value as Map<String, dynamic>)['type'] as String? ?? '';
        xp += (type == 'question' || type == 'evaluation') ? 8 : 1;
      }
    }
  } else {
    // Atomic block (no steps)
    final type = blockData['type'] as String? ?? '';
    xp += (type == 'question' || type == 'exercise') ? 8 : 1;
  }

  return xp > 0 ? xp : 1;
}

/// Mock data for demo purposes
class MockCourseData {
  /// Demo blocks showing all card types
  static const List<LessonBlock> _demoBlocks = [
    // Text block
    LessonBlock(
      id: '1',
      title: 'Úvod do tématu',
      content: 'Toto je úvodní text, který vysvětluje základní koncepty této lekce. Každá lekce obsahuje různé typy obsahu, které vám pomohou lépe pochopit probíranou látku.\n\nText může obsahovat více odstavců a podrobně vysvětlovat důležité informace.',
      type: LessonBlockType.text,
      isCompleted: false,
    ),
    // Image block
    LessonBlock(
      id: '2',
      title: 'Vizuální znázornění',
      content: 'Obrázek pomáhá lépe pochopit složité koncepty a ukazuje vztahy mezi jednotlivými prvky.',
      type: LessonBlockType.image,
      imageEmoji: '🎨',
      isCompleted: false,
    ),
    // Video block
    LessonBlock(
      id: '3',
      title: 'Video vysvětlení',
      content: 'Sledujte video, které vás provede tímto tématem krok za krokem.',
      type: LessonBlockType.video,
      videoDuration: '4:32',
      isCompleted: false,
    ),
    // Key concepts block
    LessonBlock(
      id: '4',
      title: 'Klíčové pojmy',
      content: '',
      type: LessonBlockType.keyConcepts,
      keyConcepts: [
        KeyConcept(term: 'Pojem 1', definition: 'Definice prvního klíčového pojmu'),
        KeyConcept(term: 'Pojem 2', definition: 'Definice druhého klíčového pojmu'),
        KeyConcept(term: 'Pojem 3', definition: 'Definice třetího klíčového pojmu'),
      ],
      isCompleted: false,
    ),
    // Quiz block
    LessonBlock(
      id: '5',
      title: 'Rychlá kontrola',
      content: '',
      type: LessonBlockType.quiz,
      quizQuestion: 'Co jste se právě naučili v této části lekce?',
      quizOptions: [
        QuizOption(id: 'a', text: 'První možná odpověď', isCorrect: false),
        QuizOption(id: 'b', text: 'Správná odpověď', isCorrect: true),
        QuizOption(id: 'c', text: 'Třetí možná odpověď', isCorrect: false),
      ],
      isCompleted: false,
    ),
    // Another text block
    LessonBlock(
      id: '6',
      title: 'Pokračování výkladu',
      content: 'Nyní se podíváme na další důležité aspekty tohoto tématu. Je důležité pochopit souvislosti mezi jednotlivými koncepty.\n\nTento text navazuje na předchozí část a rozšiřuje vaše znalosti.',
      type: LessonBlockType.text,
      isCompleted: false,
    ),
    // Summary text block
    LessonBlock(
      id: '7',
      title: 'Shrnutí lekce',
      content: 'V této lekci jste se naučili základní koncepty a pojmy. Nezapomeňte si projít klíčové pojmy a vyzkoušet si kvíz pro ověření vašich znalostí.',
      type: LessonBlockType.text,
      isCompleted: false,
    ),
  ];

  static final Course biologyCourse = Course(
    id: '1',
    title: 'Základy biologie',
    subtitle: 'Zábavné metody fungování oboušení',
    description:
        'Objevte fascinující svět biologie od základních stavebních jednotek po složité organismy. Tento kurz vás provede základy buněčné biologie, genetiky a ekologie. Naučíte se, jak fungují živé organismy a jak jsou propojeny s prostředím kolem nás.',
    iconEmoji: '🧬',
    iconBackgroundColor: AppColors.cardLavender,
    badge: 'BIO',
    difficulty: 'ROOKIE',
    lessonCount: 16,
    durationHours: 5,
    completedLessons: 16,
    isCompleted: true,
    isBookmarked: true,
    lessons: [
      Lesson(
        id: '1',
        title: 'Úvod do biologie',
        iconEmoji: '📚',
        status: LessonStatus.completed,
        questionCount: 8,
        durationMinutes: 15,
        xpReward: 15,
        blocks: _demoBlocks,
      ),
      Lesson(
        id: '2',
        title: 'Co je živý organismus?',
        iconEmoji: '🦠',
        status: LessonStatus.completed,
        questionCount: 12,
        durationMinutes: 25,
        xpReward: 20,
        blocks: _demoBlocks,
      ),
      Lesson(
        id: '3',
        title: 'Základní stavební jednotky',
        iconEmoji: '🔬',
        status: LessonStatus.completed,
        questionCount: 11,
        durationMinutes: 15,
        xpReward: 15,
        blocks: _demoBlocks,
      ),
      Lesson(
        id: '4',
        title: 'Buněčné struktury',
        subtitle: 'Lekce 4: Buněčné struktur...',
        iconEmoji: '🧬',
        status: LessonStatus.inProgress,
        questionCount: 12,
        durationMinutes: 35,
        xpReward: 15,
        blocks: _demoBlocks,
      ),
      Lesson(
        id: '5',
        title: 'Buněčné dělení',
        iconEmoji: '🔄',
        status: LessonStatus.locked,
        questionCount: 11,
        durationMinutes: 30,
        xpReward: 20,
        blocks: _demoBlocks,
      ),
      Lesson(
        id: '6',
        title: 'Metabolismus',
        iconEmoji: '⚡',
        status: LessonStatus.locked,
        questionCount: 7,
        durationMinutes: 15,
        xpReward: 15,
        blocks: _demoBlocks,
      ),
    ],
    quizzes: const [
      Quiz(
        id: '1',
        title: 'Buněčné základy',
        questionCount: 25,
      ),
      Quiz(
        id: '2',
        title: 'Organismy',
        questionCount: 20,
      ),
      Quiz(
        id: '3',
        title: 'Genetika',
        questionCount: 30,
      ),
    ],
  );

  static final Course physicsCourse = Course(
    id: '2',
    title: 'Fyzika pro začátečníky',
    subtitle: 'Základy mechaniky a termodynamiky',
    description:
        'Prozkoumejte základní principy fyziky od Newtonových zákonů po termodynamiku.',
    iconEmoji: '⚛️',
    iconBackgroundColor: AppColors.cardPeach,
    badge: 'FYZ',
    difficulty: 'ROOKIE',
    lessonCount: 12,
    durationHours: 4,
    completedLessons: 5,
    isCompleted: false,
    isBookmarked: false,
    lessons: [
      Lesson(
        id: '1',
        title: 'Úvod do fyziky',
        iconEmoji: '📖',
        status: LessonStatus.completed,
        questionCount: 10,
        durationMinutes: 20,
        blocks: _demoBlocks,
      ),
      Lesson(
        id: '2',
        title: 'Newtonovy zákony',
        iconEmoji: '🍎',
        status: LessonStatus.completed,
        questionCount: 15,
        durationMinutes: 30,
        blocks: _demoBlocks,
      ),
      Lesson(
        id: '3',
        title: 'Síla a pohyb',
        iconEmoji: '💪',
        status: LessonStatus.inProgress,
        questionCount: 12,
        durationMinutes: 25,
        blocks: _demoBlocks,
      ),
      Lesson(
        id: '4',
        title: 'Energie',
        iconEmoji: '⚡',
        status: LessonStatus.locked,
        questionCount: 14,
        durationMinutes: 35,
        blocks: _demoBlocks,
      ),
    ],
    quizzes: const [
      Quiz(
        id: '1',
        title: 'Mechanika',
        questionCount: 15,
      ),
    ],
  );
}
