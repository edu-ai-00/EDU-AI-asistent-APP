import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:eduai/core/util/silent_log.dart';

/// Data source for courses bundled with the app.
/// These are pre-packaged JSON files in assets/courses/ that provide
/// offline-first access to courses without needing API connectivity.
class BundledCoursesDataSource {
  /// Cache of loaded courses to avoid re-reading assets.
  final Map<String, Map<String, dynamic>> _cache = {};

  /// List of bundled course files (without .json extension).
  /// Add course IDs here when you add new JSON files to assets/courses/
  static const List<String> bundledCourseIds = [
    // Example: 'demo_zlomky_v4',
  ];

  /// Manifest file that lists all bundled courses.
  /// This is auto-generated or manually maintained.
  static const String manifestPath = 'assets/courses/manifest.json';

  /// Get list of all bundled course IDs.
  /// First tries to load from manifest, falls back to hardcoded list.
  Future<List<String>> getBundledCourseIds() async {
    try {
      final manifestJson = await rootBundle.loadString(manifestPath);
      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
      final courses = manifest['courses'] as List<dynamic>? ?? [];
      final result = courses.map((c) => c.toString()).toList();
      return result;
    } catch (e) {
      // Manifest doesn't exist, use hardcoded list
      return bundledCourseIds;
    }
  }

  /// Load a bundled course by its ID.
  /// First tries the ID as a filename, then searches all bundled courses
  /// for a matching `course_id` field inside the JSON.
  /// Returns null if course is not bundled.
  Future<Map<String, dynamic>?> loadCourse(String courseId) async {
    // Check cache first (by filename key)
    if (_cache.containsKey(courseId)) {
      return _cache[courseId];
    }

    // Check cache by course_id field
    for (final entry in _cache.entries) {
      if (entry.value['course_id'] == courseId) {
        return entry.value;
      }
    }

    // Try loading by filename directly
    try {
      final path = 'assets/courses/$courseId.json';
      final jsonString = await rootBundle.loadString(path);
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      _cache[courseId] = data;
      return data;
    } catch (e, st) { silentLog('bundled_courses_datasource', e, st); }

    // Filename didn't match — search all manifest entries by course_id field
    final manifestIds = await getBundledCourseIds();
    for (final manifestId in manifestIds) {
      final course = await _loadByFilename(manifestId);
      if (course != null && course['course_id'] == courseId) {
        return course;
      }
    }

    return null;
  }

  /// Load a bundled course by filename only (no course_id search).
  Future<Map<String, dynamic>?> _loadByFilename(String filename) async {
    if (_cache.containsKey(filename)) {
      return _cache[filename];
    }

    try {
      final path = 'assets/courses/$filename.json';
      final jsonString = await rootBundle.loadString(path);
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      _cache[filename] = data;
      return data;
    } catch (e) {
      return null;
    }
  }

  /// Load a bundled course by its numeric code/pin.
  /// Searches through all bundled courses to find one with matching code.
  /// Checks both 'code' and 'pin' fields for compatibility.
  Future<Map<String, dynamic>?> loadCourseByCode(String code) async {
    final normalized = code.toUpperCase();
    final courseIds = await getBundledCourseIds();

    for (final courseId in courseIds) {
      final course = await loadCourse(courseId);
      if (course != null) {
        // Check if this course has the matching code or pin
        final courseCode = course['code']?.toString().toUpperCase();
        final coursePin = course['pin']?.toString().toUpperCase();
        if (courseCode == normalized || coursePin == normalized) {
          return course;
        }
      }
    }

    return null;
  }

  /// Check if a course is bundled (by course_id field in JSON).
  Future<bool> isBundled(String courseId) async {
    final course = await loadCourse(courseId);
    return course != null;
  }

  /// Get all bundled courses metadata (for library display).
  Future<List<Map<String, dynamic>>> getAllBundledCourses() async {
    final courseIds = await getBundledCourseIds();
    final courses = <Map<String, dynamic>>[];

    for (final courseId in courseIds) {
      final course = await loadCourse(courseId);
      if (course != null) {
        courses.add(course);
      }
    }

    return courses;
  }

  /// Clear the cache (useful for testing or memory management).
  void clearCache() {
    _cache.clear();
  }
}
