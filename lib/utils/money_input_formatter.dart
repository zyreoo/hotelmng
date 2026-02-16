import 'package:flutter/services.dart';

/// Allows digits and one decimal separator (comma or period); at most 2 decimal places.
/// User can type: 20, 20., 20.5, 20,50, 2.80, etc. Keeps their separator as typed.
class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;
    if (text.isEmpty) return newValue;

    final buffer = StringBuffer();
    bool hasSeparator = false;
    int decimalDigits = 0;

    for (int i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == ',' || c == '.') {
        if (!hasSeparator) {
          hasSeparator = true;
          buffer.write(c);
        }
      } else if ('0123456789'.contains(c)) {
        if (hasSeparator) {
          if (decimalDigits < 2) {
            buffer.write(c);
            decimalDigits++;
          }
        } else {
          buffer.write(c);
        }
      }
    }

    final result = buffer.toString();
    if (result == newValue.text) return newValue;

    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}
