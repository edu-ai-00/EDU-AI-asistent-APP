// Parses inline media embeds out of step content so they can render as native
// widgets instead of being dropped by the markdown/HTML renderers.
//
// Currently handles <video> tags (with nested <source src> or a src attribute
// on the <video> element itself). The surrounding text is preserved in document
// order so a player can be interleaved between markdown/HTML segments.

/// One ordered piece of step content: either text (markdown/HTML) or a video.
sealed class ContentPart {
  const ContentPart();
}

/// A run of text (markdown or HTML) between embeds.
class TextPart extends ContentPart {
  final String text;
  const TextPart(this.text);
}

/// A video embed extracted from a <video> tag.
class VideoPart extends ContentPart {
  final String url;
  const VideoPart(this.url);
}

final RegExp _videoTagRe =
    RegExp(r'<video[^>]*>[\s\S]*?</video>', caseSensitive: false);
// Self-closing or attribute-only: <video ... src="..." />  (no closing tag)
final RegExp _videoSelfRe =
    RegExp(r'<video[^>]*/>', caseSensitive: false);
final RegExp _srcRe =
    RegExp(r'''src\s*=\s*["']([^"']+)["']''', caseSensitive: false);

/// True when [content] contains a <video> embed worth extracting.
bool hasVideoEmbed(String content) => content.contains('<video');

/// Split [content] into ordered text and video parts.
///
/// Falls back to a single [TextPart] when no video tag is present.
List<ContentPart> parseContentEmbeds(String content) {
  if (!hasVideoEmbed(content)) return [TextPart(content)];

  // Collect all <video>...</video> and self-closing <video/> matches, sorted.
  final matches = <RegExpMatch>[
    ..._videoTagRe.allMatches(content),
    ..._videoSelfRe.allMatches(content),
  ]..sort((a, b) => a.start.compareTo(b.start));

  // Drop self-closing matches that overlap a full-tag match (the full tag wins).
  final ranges = <RegExpMatch>[];
  int guard = -1;
  for (final m in matches) {
    if (m.start < guard) continue;
    ranges.add(m);
    guard = m.end;
  }

  final parts = <ContentPart>[];
  int last = 0;
  for (final m in ranges) {
    final before = content.substring(last, m.start);
    if (before.trim().isNotEmpty) parts.add(TextPart(before));

    final url = _extractVideoSrc(m.group(0)!);
    if (url != null && url.isNotEmpty) parts.add(VideoPart(url));

    last = m.end;
  }
  final rest = content.substring(last);
  if (rest.trim().isNotEmpty) parts.add(TextPart(rest));

  if (parts.isEmpty) parts.add(TextPart(content));
  return parts;
}

/// Pull the first src="..." out of a <video> tag (covers nested <source> too).
String? _extractVideoSrc(String tag) => _srcRe.firstMatch(tag)?.group(1);
