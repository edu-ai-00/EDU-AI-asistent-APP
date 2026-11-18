// BR-PW3N33 — the course page claimed lesson blocks the student never did.
//
// The student only ran the course's Kvíz: ten questions, drawn from both
// lessons, answered in under a minute. Not one lesson block. The course page
// still read "10/31": with no completed_blocks it fell back to counting quiz
// answers — a fallback meant for quiz-only courses, which have no lesson
// progress of their own. Opening lesson 1 then showed "0/19", and the first
// block the student finished dropped the course page to "1/31".
//
// BR-PTH76K — the course card read "140/129". Every lesson record in
// progress_data was summed, and those outlive the course's edits: a deleted
// or renamed lesson keeps its record, a moved block stays done in its old
// lesson. Only blocks the course holds now, in the lesson that holds them,
// may count.
//
// Pure functions — no database, no widgets:
//   flutter test test/course_completed_block_count_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/models/course_model.dart';

Map<String, dynamic> _lesson(String id, List<String> blockIds) => {
      'lesson_id': id,
      'blocks': [
        for (var i = 0; i < blockIds.length; i++)
          {'block_id': blockIds[i], 'order': i + 1},
      ],
    };

Map<String, dynamic> _done(List<String> blockIds) =>
    {'completed_blocks': blockIds};

/// Two lessons, ten questions in all — the reporter's Funkce course in small.
final _course = <String, dynamic>{
  'lessons': [
    _lesson('L1', [for (var i = 1; i <= 5; i++) 'A34-Funkce_$i']),
    _lesson('L2', [for (var i = 6; i <= 10; i++) 'A34-Funkce_$i']),
  ],
};

final _quizOnlyCourse = <String, dynamic>{..._course, 'only_quiz': true};

/// The reporter's student on 30.9.: the Kvíz, nothing in the lessons.
final _quizOnlyRun = <String, dynamic>{
  'quiz_completed': true,
  'quiz_answers': {
    for (var i = 1; i <= 10; i++)
      'A34-Funkce_$i': {'is_correct': i.isEven, 'is_answered': true},
  },
};

void main() {
  group('a regular course', () {
    test('Kvíz answers are not lesson blocks', () {
      expect(Course.completedBlockCount(_course, _quizOnlyRun), 0);
    });

    test('counts the lesson blocks the student finished', () {
      final progress = {
        ..._quizOnlyRun,
        'lessons': {
          'L1': _done(['A34-Funkce_1', 'A34-Funkce_2']),
          'L2': _done(['A34-Funkce_6']),
        },
      };
      expect(Course.completedBlockCount(_course, progress), 3);
    });

    test('nothing done reads zero', () {
      expect(Course.completedBlockCount(_course, const {}), 0);
    });

    test('a lesson without lesson_id is keyed by its index', () {
      final course = {
        'lessons': [
          {
            'blocks': [
              {'block_id': 'b1'},
              {'block_id': 'b2'},
            ],
          },
        ],
      };
      final progress = {
        'lessons': {'lesson_0': _done(['b1'])},
      };
      expect(Course.completedBlockCount(course, progress), 1);
    });
  });

  group('after the author edited the course (BR-PTH76K)', () {
    test('a deleted lesson no longer counts', () {
      final progress = {
        'lessons': {
          'L1': _done([for (var i = 1; i <= 5; i++) 'A34-Funkce_$i']),
          'L-deleted': _done(['old_1', 'old_2', 'old_3']),
        },
      };
      expect(Course.completedBlockCount(_course, progress), 5);
    });

    test('a renamed lesson counts only under its new id', () {
      final progress = {
        'lessons': {
          'L2-old': _done([for (var i = 6; i <= 10; i++) 'A34-Funkce_$i']),
          'L2': _done(['A34-Funkce_6']),
        },
      };
      expect(Course.completedBlockCount(_course, progress), 1);
    });

    test('a removed block no longer counts', () {
      final progress = {
        'lessons': {
          'L1': _done(['A34-Funkce_1', 'A34-Funkce_removed']),
        },
      };
      expect(Course.completedBlockCount(_course, progress), 1);
    });

    test('a block moved to another lesson is not counted twice', () {
      // Funkce_5 moved from L1 to L2 after the student finished it in L1,
      // then finished it again in L2.
      final course = {
        'lessons': [
          _lesson('L1', [for (var i = 1; i <= 4; i++) 'A34-Funkce_$i']),
          _lesson('L2', [for (var i = 5; i <= 10; i++) 'A34-Funkce_$i']),
        ],
      };
      final progress = {
        'lessons': {
          'L1': _done([for (var i = 1; i <= 5; i++) 'A34-Funkce_$i']),
          'L2': _done(['A34-Funkce_5']),
        },
      };
      expect(Course.completedBlockCount(course, progress), 5);
    });

    test('never exceeds the blocks the course holds', () {
      // Every record ever written, old ids and new: still 10 of 10 at most.
      final progress = {
        'lessons': {
          'L1': _done([for (var i = 1; i <= 10; i++) 'A34-Funkce_$i']),
          'L2': _done([for (var i = 1; i <= 10; i++) 'A34-Funkce_$i']),
          'L3-deleted': _done([for (var i = 1; i <= 10; i++) 'A34-Funkce_$i']),
        },
      };
      expect(Course.completedBlockCount(_course, progress), 10);
    });
  });

  group('a quiz-only course', () {
    test('answered questions are its progress', () {
      expect(Course.completedBlockCount(_quizOnlyCourse, _quizOnlyRun), 10);
    });

    test('unanswered questions do not count', () {
      final progress = {
        'quiz_answers': {
          'A34-Funkce_1': {'is_answered': true},
          'A34-Funkce_2': {'is_answered': false},
        },
      };
      expect(Course.completedBlockCount(_quizOnlyCourse, progress), 1);
    });

    test('answers to questions the course dropped do not count', () {
      final progress = {
        'quiz_answers': {
          ..._quizOnlyRun['quiz_answers'] as Map<String, dynamic>,
          'A34-Funkce_removed': {'is_answered': true},
        },
      };
      expect(Course.completedBlockCount(_quizOnlyCourse, progress), 10);
    });
  });

  // BR-W6V77D — the dashboard's "Pokračuj v lekci" card needs the same count
  // per lesson, to find the first lesson with blocks left.
  group('lessonBlockProgress', () {
    test('counts each lesson off the course JSON, untouched ones included',
        () {
      expect(Course.lessonBlockProgress(_course, const {}), [
        (done: 0, total: 5),
        (done: 0, total: 5),
      ]);
    });

    test('a block counts only in the lesson that holds it now', () {
      final progress = {
        'lessons': {
          // Lesson 2's blocks recorded under lesson 1, plus one of its own.
          'L1': _done(['A34-Funkce_1', 'A34-Funkce_6', 'A34-Funkce_7']),
          'L3-deleted': _done(['A34-Funkce_2']),
        },
      };
      expect(Course.lessonBlockProgress(_course, progress), [
        (done: 1, total: 5),
        (done: 0, total: 5),
      ]);
    });

    test('adds up to completedBlockCount', () {
      final progress = {
        'lessons': {
          'L1': _done([for (var i = 1; i <= 5; i++) 'A34-Funkce_$i']),
          'L2': _done(['A34-Funkce_6', 'A34-Funkce_9']),
        },
      };
      final perLesson = Course.lessonBlockProgress(_course, progress);
      expect(perLesson.fold<int>(0, (sum, l) => sum + l.done),
          Course.completedBlockCount(_course, progress));
    });
  });
}
