import '../core/database/app_database.dart';
import '../core/strings/app_strings.dart';

/// Predefined AI chat personas.
enum ChatPersona {
  aiTeacher('ai_teacher'),
  mathMentor('math_mentor'),
  studyCoach('study_coach'),
  languageMentor('language_mentor');

  final String id;
  const ChatPersona(this.id);

  String get emoji {
    switch (this) {
      case ChatPersona.aiTeacher: return '🤖';
      case ChatPersona.mathMentor: return '📐';
      case ChatPersona.studyCoach: return '📚';
      case ChatPersona.languageMentor: return '🌍';
    }
  }

  String get displayName {
    switch (this) {
      case ChatPersona.aiTeacher: return AppStrings.personaAiTeacherName;
      case ChatPersona.mathMentor: return AppStrings.personaMathMentorName;
      case ChatPersona.studyCoach: return AppStrings.personaStudyCoachName;
      case ChatPersona.languageMentor: return AppStrings.personaLanguageMentorName;
    }
  }

  String get subtitle {
    switch (this) {
      case ChatPersona.aiTeacher: return AppStrings.personaAiTeacherSubtitle;
      case ChatPersona.mathMentor: return AppStrings.personaMathMentorSubtitle;
      case ChatPersona.studyCoach: return AppStrings.personaStudyCoachSubtitle;
      case ChatPersona.languageMentor: return AppStrings.personaLanguageMentorSubtitle;
    }
  }

  String get description {
    switch (this) {
      case ChatPersona.aiTeacher: return AppStrings.personaAiTeacherDesc;
      case ChatPersona.mathMentor: return AppStrings.personaMathMentorDesc;
      case ChatPersona.studyCoach: return AppStrings.personaStudyCoachDesc;
      case ChatPersona.languageMentor: return AppStrings.personaLanguageMentorDesc;
    }
  }

  static ChatPersona fromId(String id) {
    return ChatPersona.values.firstWhere(
      (p) => p.id == id,
      orElse: () => ChatPersona.aiTeacher,
    );
  }
}

/// Message role constants matching server API values.
class MessageRole {
  MessageRole._();
  static const String user = 'user';
  static const String assistant = 'assistant';
  static const String system = 'system';
}

/// Extension on Drift-generated ChatMessagesTableData for convenience.
extension ChatMessageHelpers on ChatMessagesTableData {
  bool get isFromUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
  bool get isLiked => feedbackType == 'like';
  bool get isDisliked => feedbackType == 'dislike';
}

/// Extension on ChatSessionsTableData for persona access.
extension ChatSessionHelpers on ChatSessionsTableData {
  ChatPersona get chatPersona => ChatPersona.fromId(persona);
}

/// Events emitted during chat SSE streaming.
sealed class ChatStreamEvent {}

class ChatStreamToken extends ChatStreamEvent {
  final String token;
  ChatStreamToken(this.token);
}

class ChatStreamDone extends ChatStreamEvent {
  final String fullContent;
  final int assistantMessageServerId;
  ChatStreamDone(this.fullContent, this.assistantMessageServerId);
}

class ChatStreamError extends ChatStreamEvent {
  final String error;
  ChatStreamError(this.error);
}
