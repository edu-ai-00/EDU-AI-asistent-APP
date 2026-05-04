# Hidden Features TODO

Features temporarily hidden from the UI. Each item has a `TODO: re-enable when ready` comment in the code.

## Search & Config (Kurzy header)
- **File**: `lib/main.dart` (~line 1027)
- **What**: Search button (`Icons.search`) and settings/tune button (`Icons.tune`) removed from the Kurzy tab header
- **Why**: Not ready for users yet

## Bookmarks — Course Listing
- **File**: `lib/widgets/course_card.dart` (~line 170)
  - Bookmark icon in generic course card (non-badge cards)
- **File**: `lib/widgets/kurzy_course_card.dart` (~line 151)
  - Bookmark icon in Kurzy-style course card (bottom-right)

## Bookmarks — Course Detail
- **File**: `lib/pages/course_detail_page.dart` (~line 297)
  - Bookmark circle button in course detail header
- **File**: `lib/pages/course_detail_page.dart` (~line 964)
  - "Cvičení" button (in-progress state) — navigates to bookmarked blocks
- **File**: `lib/pages/course_detail_page.dart` (~line 1037)
  - "Cvičení" button (completed state) — navigates to bookmarked blocks

## Bookmarks — Lesson Detail
- **File**: `lib/pages/lesson_detail_page.dart` (~line 2421, 2522)
  - Bookmark action button on content blocks (both V2 and legacy paths)
- **File**: `lib/pages/lesson_detail_page.dart` (~line 748)
  - "Přidat k procvičování" option in feedback modal
- **File**: `lib/pages/lesson_detail_page.dart` (~line 3020)
  - "Cvičení" button in course completion view

## Bookmarks — Exercise Page
- **File**: `lib/pages/exercise_page.dart` (~line 925)
  - Bookmark action button on exercise questions

## Three Dots Menu — Course Detail
- **File**: `lib/pages/course_detail_page.dart` (~line 299)
  - Three dots (`Icons.more_horiz`) menu button in course detail header
