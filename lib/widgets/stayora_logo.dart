import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// STAYORA branding: "STAYORA" in Manrope with theme-adaptive color,
/// and a blue dot (.) in #007AFF. Works in both light and dark mode.
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

  static const Color _blueDot = Color(0xFF007AFF);

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;

    return Text.rich(
      textAlign: textAlign ?? TextAlign.left,
      TextSpan(
        children: [
          TextSpan(
            text: 'STAYORA',
            style: GoogleFonts.manrope(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: textColor,
              letterSpacing: -0.5,
            ),
          ),
          TextSpan(
            text: '.',
            style: GoogleFonts.manrope(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: _blueDot,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}
