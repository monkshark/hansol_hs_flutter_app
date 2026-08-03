import 'package:flutter/material.dart';
import 'package:hansol_high_school/styles/app_colors.dart';

class TimetableCell extends StatelessWidget {
  final String subject;
  final bool isConflict;
  final bool isDark;
  final bool isToday;
  final bool isCurrentPeriod;
  final Color? customColor;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  const TimetableCell({
    super.key,
    required this.subject,
    required this.isConflict,
    required this.isDark,
    this.isToday = false,
    this.isCurrentPeriod = false,
    this.customColor,
    this.onLongPress,
    this.onTap,
  });

  static const _lightPastels = [
    Color(0xFFDCE8F5), Color(0xFFD5ECD4), Color(0xFFF5DDD5),
    Color(0xFFE3D5F0), Color(0xFFF0E4D0), Color(0xFFD0ECE8),
    Color(0xFFF5E0E8), Color(0xFFE8E4D0), Color(0xFFD8E0F0),
    Color(0xFFE0F0D8), Color(0xFFF0D8D8), Color(0xFFD8F0F0),
  ];

  static const _darkPastels = [
    Color(0xFF2A3A4A), Color(0xFF2A3F2A), Color(0xFF4A3530),
    Color(0xFF3A2D48), Color(0xFF443D2D), Color(0xFF2A4240),
    Color(0xFF482D38), Color(0xFF3A382D), Color(0xFF303548),
    Color(0xFF354830), Color(0xFF483030), Color(0xFF304848),
  ];

  static const _textColors = [
    Color(0xFF4A6A8A), Color(0xFF4A7A4A), Color(0xFF8A5A4A),
    Color(0xFF6A4A8A), Color(0xFF7A6A4A), Color(0xFF4A7A75),
    Color(0xFF8A4A60), Color(0xFF6A654A), Color(0xFF4A508A),
    Color(0xFF5A7A4A), Color(0xFF8A4A4A), Color(0xFF4A7A8A),
  ];

  static int _colorIndex(String s) => s.hashCode.abs() % _lightPastels.length;

  static Color conflictColorFor(bool isDark) =>
      isDark ? Colors.amber.shade300 : Colors.amber.shade800;

  /// Resolves the background/text color pair a subject renders with —
  /// shared by the grid cell, the daily list rows and the weekly mini-strip
  /// so they all stay visually consistent.
  static SubjectColors colorsFor(String subject, bool isDark, [Color? customColor]) {
    if (customColor != null) {
      final bg = isDark
          ? HSLColor.fromColor(customColor).withLightness(0.15).withSaturation(0.3).toColor()
          : HSLColor.fromColor(customColor).withLightness(0.92).withSaturation(0.4).toColor();
      final text = isDark
          ? HSLColor.fromColor(customColor).withLightness(0.75).toColor()
          : HSLColor.fromColor(customColor).withLightness(0.35).toColor();
      return SubjectColors(bg, text);
    }
    final idx = _colorIndex(subject);
    return isDark
        ? SubjectColors(_darkPastels[idx], _lightPastels[idx])
        : SubjectColors(_lightPastels[idx], _textColors[idx]);
  }

  @override
  Widget build(BuildContext context) {
    final conflictColor = conflictColorFor(isDark);

    if (subject.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1C22) : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(10),
        ),
      );
    }

    final colors = colorsFor(subject, isDark, customColor);
    final bg = colors.bg;
    final textColor = colors.text;

    return GestureDetector(
      onLongPress: onLongPress,
      onTap: onTap,
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: isConflict
                  ? Border.all(color: conflictColor, width: 1.5)
                  : isCurrentPeriod
                      ? Border.all(color: AppColors.theme.primaryColor, width: 2)
                      : null,
              boxShadow: isCurrentPeriod
                  ? [
                      BoxShadow(
                        color: AppColors.theme.primaryColor.withAlpha(70),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                child: Text(
                  subject,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
          if (isConflict)
            Positioned(
              top: 1.5,
              right: 1.5,
              child: ClipPath(
                clipper: _CornerFlagClipper(),
                child: Container(
                  width: 14,
                  height: 14,
                  color: conflictColor,
                ),
              ),
            ),
          if (isConflict)
            Positioned(
              top: 1.5,
              right: 2.5,
              child: Text(
                '!',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: isDark ? const Color(0xFF221A05) : Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SubjectColors {
  final Color bg;
  final Color text;
  const SubjectColors(this.bg, this.text);
}

class _CornerFlagClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
