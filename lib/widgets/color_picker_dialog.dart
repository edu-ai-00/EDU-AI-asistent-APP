import 'package:flutter/material.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';

/// HSV-based color picker shown as a modal bottom sheet / dialog.
///
/// Features a saturation-value canvas, hue slider, and hex input.
class ColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final String label;

  const ColorPickerDialog({
    super.key,
    required this.initialColor,
    required this.label,
  });

  /// Show the picker and return the chosen color (or null if cancelled).
  static Future<Color?> show(
    BuildContext context, {
    required Color initialColor,
    required String label,
  }) {
    return showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ColorPickerDialog(
        initialColor: initialColor,
        label: label,
      ),
    );
  }

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late double _hue;
  late double _saturation;
  late double _value;
  late TextEditingController _hexController;
  late Color _currentColor;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initialColor);
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _value = hsv.value;
    _currentColor = widget.initialColor;
    _hexController = TextEditingController(text: _colorToHex(widget.initialColor));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _updateFromHSV() {
    _currentColor = HSVColor.fromAHSV(1, _hue, _saturation, _value).toColor();
    _hexController.text = _colorToHex(_currentColor);
  }

  void _updateFromHex(String hex) {
    hex = hex.replaceFirst('#', '').trim();
    if (hex.length == 6) {
      try {
        final color = Color(int.parse('FF$hex', radix: 16));
        final hsv = HSVColor.fromColor(color);
        setState(() {
          _hue = hsv.hue;
          _saturation = hsv.saturation;
          _value = hsv.value;
          _currentColor = color;
        });
      } catch (_) {}
    }
  }

  String _colorToHex(Color c) {
    final v = c.toARGB32();
    return '#${v.toRadixString(16).substring(2).toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.primaryDark16,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Label
          Text(widget.label, style: AppTextStyles.heading3()),
          const SizedBox(height: 20),
          // Preview: old → new
          _buildPreviewRow(),
          const SizedBox(height: 20),
          // SV Canvas
          _buildSVCanvas(),
          const SizedBox(height: 16),
          // Hue slider
          _buildHueSlider(),
          const SizedBox(height: 16),
          // Hex input
          _buildHexInput(),
          const SizedBox(height: 24),
          // Buttons
          _buildButtons(),
        ],
      ),
    );
  }

  Widget _buildPreviewRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildPreviewCircle(widget.initialColor),
        const SizedBox(width: 12),
        Icon(Icons.arrow_forward, size: 20, color: AppColors.primaryDark48),
        const SizedBox(width: 12),
        _buildPreviewCircle(_currentColor),
      ],
    );
  }

  Widget _buildPreviewCircle(Color color) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primaryDark16, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  Widget _buildSVCanvas() {
    return SizedBox(
      height: 200,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onPanDown: (d) => _onSVPan(d.localPosition, constraints.biggest),
            onPanUpdate: (d) => _onSVPan(d.localPosition, constraints.biggest),
            child: ClipRRect(
              borderRadius: AppDecorations.radiusM,
              child: CustomPaint(
                size: constraints.biggest,
                painter: _SVCanvasPainter(_hue),
                child: Stack(
                  children: [
                    Positioned(
                      left: (_saturation * constraints.maxWidth) - 10,
                      top: ((1 - _value) * constraints.maxHeight) - 10,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _onSVPan(Offset pos, Size size) {
    setState(() {
      _saturation = (pos.dx / size.width).clamp(0, 1);
      _value = (1 - pos.dy / size.height).clamp(0, 1);
      _updateFromHSV();
    });
  }

  Widget _buildHueSlider() {
    return SizedBox(
      height: 32,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onPanDown: (d) => _onHuePan(d.localPosition, constraints.maxWidth),
            onPanUpdate: (d) => _onHuePan(d.localPosition, constraints.maxWidth),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CustomPaint(
                size: Size(constraints.maxWidth, 32),
                painter: _HueBarPainter(),
                child: Stack(
                  children: [
                    Positioned(
                      left: (_hue / 360 * constraints.maxWidth) - 10,
                      top: 6,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: HSVColor.fromAHSV(1, _hue, 1, 1).toColor(),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _onHuePan(Offset pos, double width) {
    setState(() {
      _hue = (pos.dx / width * 360).clamp(0, 359.9);
      _updateFromHSV();
    });
  }

  Widget _buildHexInput() {
    return Row(
      children: [
        Text('Hex:', style: AppTextStyles.labelMedium()),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.inputBg,
              borderRadius: AppDecorations.radiusS,
            ),
            child: TextField(
              controller: _hexController,
              style: AppTextStyles.bodySmall(),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: _updateFromHex,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: AppDecorations.radiusM,
              ),
              child: Center(
                child: Text(
                  AppStrings.themeEditorCancel,
                  style: AppTextStyles.buttonLarge(color: AppColors.primaryDark),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.pop(context, _currentColor),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: AppDecorations.radiusM,
              ),
              child: Center(
                child: Text(
                  AppStrings.themeEditorConfirm,
                  style: AppTextStyles.buttonLarge(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Custom Painters ─────────────────────────────────────────────────

/// Draws the saturation (x) × value (y) canvas for a given hue.
class _SVCanvasPainter extends CustomPainter {
  final double hue;
  _SVCanvasPainter(this.hue);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Horizontal gradient: white → fully saturated color
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, hueColor],
        ).createShader(rect),
    );

    // Vertical overlay: transparent → black
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SVCanvasPainter old) => old.hue != hue;
}

/// Draws a horizontal rainbow bar for hue selection (0–360).
class _HueBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final colors = List.generate(
      7,
      (i) => HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
    );
    canvas.drawRect(
      rect,
      Paint()..shader = LinearGradient(colors: colors).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_HueBarPainter old) => false;
}
