import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/image_url.dart';
import '../../models/block_model.dart';

/// Network image renderer that handles both raster and SVG sources.
class LessonNetworkImage extends StatelessWidget {
  final String rawUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? errorWidget;
  final Widget? loadingWidget;

  const LessonNetworkImage({
    super.key,
    required this.rawUrl,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.errorWidget,
    this.loadingWidget,
  });

  @override
  Widget build(BuildContext context) {
    final url = resolveImageUrl(rawUrl);
    final isSvg = url.toLowerCase().endsWith('.svg') ||
        url.toLowerCase().contains('.svg?');
    final fallback = errorWidget ??
        Icon(Icons.broken_image, size: 48, color: AppColors.progressFill);

    if (isSvg) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: height ?? 240,
          maxWidth: width ?? double.infinity,
        ),
        child: SvgPicture.network(
          url,
          fit: fit,
          placeholderBuilder:
              loadingWidget != null ? (_) => loadingWidget! : null,
        ),
      );
    }

    return Image.network(
      url,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (context, error, stack) => fallback,
      loadingBuilder: loadingWidget != null
          ? (context, child, progress) {
              if (progress == null) return child;
              return loadingWidget!;
            }
          : null,
    );
  }
}

/// Block image with rounded corners and a styled error state.
class LessonBlockImage extends StatelessWidget {
  final StepImage image;

  const LessonBlockImage({super.key, required this.image});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppDecorations.radiusM,
      child: LessonNetworkImage(
        rawUrl: image.url,
        fit: BoxFit.contain,
        width: double.infinity,
        errorWidget: Container(
          padding: const EdgeInsets.all(32),
          color: AppColors.background,
          child: const Icon(Icons.broken_image, size: 48, color: Colors.grey),
        ),
      ),
    );
  }
}
