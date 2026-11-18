import 'lesson_image_backend.dart';

/// A platform with neither a file system nor a browser: nowhere to keep
/// pictures, so lesson images load straight from the network.
LessonImageBackend? createLessonImageBackend() => null;
