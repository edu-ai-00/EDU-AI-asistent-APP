import 'package:flutter_test/flutter_test.dart';
import 'package:eduai/core/utils/content_embeds.dart';

void main() {
  group('parseContentEmbeds', () {
    test('text only -> single TextPart', () {
      final parts = parseContentEmbeds('hello **world**');
      expect(parts.length, 1);
      expect(parts.first, isA<TextPart>());
      expect((parts.first as TextPart).text, 'hello **world**');
    });

    test('markdown image + nested <source> video (real onboarding case)', () {
      const content =
          'Intro text\n\n![Yes!](https://cdn/ico.webp)\n'
          '<video controls width="640" autoplay muted loop playsinline>\n'
          '  <source src="https://cdn/e-intro.mp4" type="video/mp4">\n'
          '  Your browser does not support the video tag.\n'
          '</video>';
      final parts = parseContentEmbeds(content);
      expect(parts.whereType<VideoPart>().length, 1);
      expect((parts.whereType<VideoPart>().first).url, 'https://cdn/e-intro.mp4');
      // Text before the video (with markdown image) is preserved.
      expect(parts.first, isA<TextPart>());
      expect((parts.first as TextPart).text, contains('![Yes!]'));
    });

    test('src directly on <video> element', () {
      final parts = parseContentEmbeds('<video src="https://cdn/a.mp4"></video>');
      expect(parts.whereType<VideoPart>().single.url, 'https://cdn/a.mp4');
    });

    test('multiple videos with interleaved text, order preserved', () {
      const content =
          'A<video><source src="https://cdn/1.mp4"></video>'
          'B<video><source src="https://cdn/2.mp4"></video>C';
      final parts = parseContentEmbeds(content);
      expect(parts.length, 5);
      expect((parts[0] as TextPart).text, 'A');
      expect((parts[1] as VideoPart).url, 'https://cdn/1.mp4');
      expect((parts[2] as TextPart).text, 'B');
      expect((parts[3] as VideoPart).url, 'https://cdn/2.mp4');
      expect((parts[4] as TextPart).text, 'C');
    });

    test('video tag without a src is dropped, surrounding text kept', () {
      final parts = parseContentEmbeds('before<video></video>after');
      expect(parts.whereType<VideoPart>(), isEmpty);
      expect(parts.whereType<TextPart>().map((t) => t.text), ['before', 'after']);
    });

    test('hasVideoEmbed detects presence', () {
      expect(hasVideoEmbed('x <video></video>'), isTrue);
      expect(hasVideoEmbed('no media here'), isFalse);
    });
  });
}
