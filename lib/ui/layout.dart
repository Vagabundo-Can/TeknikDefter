import 'dart:io';

import 'package:flutter/widgets.dart';

enum FormFactor { phone, tablet, desktop }

/// Yerleşim kısa kenara göre (Tab S9 FE dikeyde de tablet düzeni alır); Windows her zaman masaüstü.
/// Ekran görüntüsü testleri için
FormFactor? debugFormFactorOverride;

FormFactor formFactorOf(BuildContext context) {
  if (debugFormFactorOverride != null) return debugFormFactorOverride!;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return FormFactor.desktop;
  final s = MediaQuery.sizeOf(context);
  return s.shortestSide >= 600 ? FormFactor.tablet : FormFactor.phone;
}
