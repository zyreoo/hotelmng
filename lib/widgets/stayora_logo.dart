import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// STAYORA branding: "STAYORA" in Inter bold with theme-adaptive color,
/// and a blue dot (.) in the app brand blue (#007AFF). Works in both light and dark mode.
class StayoraLogo extends StatelessWidget {
  final double fontSize;
  final FontWeight fontWeight;
  final TextAlign? textAlign;

  const StayoraLogo({
    super.key,
    this.fontSize = 24,
    this.fontWeight = FontWeight.bold,
    this.textAlign,
  });

  /// App brand blue used for logo dot and primary actions (matches theme seed).
  static const Color stayoraBlue = Color(0xFF007AFF);

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final style = GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      letterSpacing: -0.5,
    );

    return Text.rich(
      textAlign: textAlign ?? TextAlign.left,
      TextSpan(
        children: [
          TextSpan(text: 'S', style: style.copyWith(color: textColor)),
          TextSpan(text: 'tayora', style: style.copyWith(color: textColor)),
          TextSpan(text: '.', style: style.copyWith(color: stayoraBlue)),
        ],
      ),
    );
  }
}
