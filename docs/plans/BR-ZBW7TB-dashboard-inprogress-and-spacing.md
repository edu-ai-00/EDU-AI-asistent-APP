# BR-ZBW7TB — Android dashboard: in-progress courses missing + Procvičování spacing

Repo: `nobig-deals/eduai-app` (Flutter). App-only. File: `lib/pages/prehled_page.dart`.

## Reported symptoms
1. Dashboard "Pokračovat" (Continue) section shows no in-progress courses — the page ends at the "Knihovna" promo box.
2. Missing spacing above the "Procvičování" heading — it is glued to the preceding "Jak používat EDU AI" box.

---

## Bug 2 (spacing) — ALREADY FIXED on `origin/staging`

Commit `00da62f7` (2026-07-01, "fix(practice): unify due-card count…") added
`const SizedBox(height: 24)` above the Procvičování heading — commit message: "prehled_page:
add top padding above the Procvičování heading." Present verbatim at `prehled_page.dart:231`;
no diff vs `origin/staging`.

Report was filed 2026-07-08 on an Android build predating the fix. **No code change needed —
verify after the next staging deploy reaches the tester's build.**

---

## Bug 1 (in-progress courses missing) — ROOT CAUSE

The "Pokračovat" filter (`prehled_page.dart:374`):

```dart
final inProgressCourses = visibleCourses
    .where((uc) =>
        uc.completedLessons > 0 &&   // <-- gate
        !uc.isCompleted &&
        uc.courseData != null)
    .toList();
```

It gates on `completedLessons > 0`. But `completedLessons` is only incremented by the
**lesson-completion** path (`lesson_detail_page.dart:534-537`). Block/quiz-based courses never
touch it:

- `quiz_page.dart:710` (quiz progress save) writes only `progressData` — no `progressPercent`,
  no `status`, no `completedLessons`.
- `quiz_page.dart:1385` (quiz complete) sets `status`/`progressPercent` **only when
  `only_quiz == true`**; for a normal block course both stay untouched.
- `startCourse` seeds `completedLessons = 0`, `status = 'downloaded'`.

So a course the user is actively working through via **blocks/quiz** (common for newer courses
that have `blocks` but no `lessons` array, so `totalLessons == 0`) keeps:
`completedLessons == 0`, `status == 'downloaded'`, `progressPercent == 0`.

Then it falls through **both** dashboard sections:
- **Pokračovat** requires `completedLessons > 0` → excluded.
- **Rychlé kvízy** (`prehled_page.dart:301`) requires `only_quiz` **or** `totalLessons > 0 &&
  completedLessons >= totalLessons` → a mid-progress, non-only_quiz block course is excluded too.

⇒ the course is invisible; the dashboard ends at the Knihovna promo box. Matches the report.

### Why now
Newer EDU-AI courses are block-structured (no `lessons`), and the recent practice/FSRS work
surfaced them on the dashboard. The `completedLessons`-only gate was always too narrow; it only
became visible with block-first courses.

### Secondary hypothesis (verify, don't assume)
`courseData != null` requires the `courses` join (`_enrichWithCourseData` →
`getCourseById(uc.courseId)`) to resolve. `deduplicateCourses` (`course_repository.dart:113`)
can delete the `courses` row a `user_courses.courseId` pointed at, orphaning the join → the row
is filtered out. This ties into the "after updating a course" theme of sibling bugs
BR-MFZF5R / BR-JUQZPY. Confirm on a repro device before treating as in-scope.

---

## Proposed fix (Bug 1)

Broaden the "in progress" signal instead of relying on `completedLessons`. Add a getter on
`UserCourse` (`user_course_repository.dart`) so the rule is centralized and testable:

```dart
/// True when the user has any recorded progress but hasn't finished.
bool get hasStarted =>
    !isCompleted &&
    (completedLessons > 0 ||
     currentLessonIndex > 0 ||
     progressPercent > 0 ||
     status == UserCourseStatus.inProgress ||
     (progressData['lessons'] as Map?)?.isNotEmpty == true ||
     progressData['quiz_in_progress'] == true ||
     progressData.containsKey('quiz_current_index'));
```

Then the Pokračовání filter becomes:

```dart
final inProgressCourses = visibleCourses
    .where((uc) => uc.hasStarted && uc.courseData != null)
    .toList();
```

### Optional hardening (correct the data at the source)
Make `quiz_page.dart:710` mark the course `in_progress` on first quiz interaction
(`status: downloaded → in_progress`) so the status field is trustworthy going forward. Low risk,
but a schema-free behavioural change — keep it separate from the display fix.

### Guardrails
- Keep the `!isCompleted` and `only_once`/`only_quiz` exclusions so quizzes still route to Rychlé
  kvízy and finished courses don't reappear.
- Watch for a course showing in BOTH Pokračovat and Rychlé kvízy; if that reads badly, prefer
  Pokračovat while `!isCompleted`.

---

## Test (write first — TDD)
Unit-test `UserCourse.hasStarted` in `test/`:
- block course, `completedLessons==0`, `progressData:{quiz_current_index:2}` → `hasStarted == true`
- fresh download, `status==downloaded`, empty progressData → `false`
- completed course (`status==completed`) → `false` even with progress
- lesson course, `completedLessons==1` → `true`

Then a widget/logic test asserting such a block course lands in the Pokračovat list.

## Verify
- `flutter test`
- Run on Android: enroll a block-based course, do one block/quiz question, return to dashboard →
  course appears under Pokračovat.
- Confirm quiz-only and completed courses still route correctly.

## Scope
- `lib/data/repositories/user_course_repository.dart` (add `hasStarted`)
- `lib/pages/prehled_page.dart` (use it)
- optional: `lib/pages/quiz_page.dart` (mark in_progress)
- `test/…` new
Base off `origin/staging`.
