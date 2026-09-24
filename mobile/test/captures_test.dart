// Captures d'écran de l'appli aux formats du Galaxy Z Fold 8, pour vérifier
// la mise en page sans téléphone :
//   flutter test --update-goldens test/captures_test.dart
// Les images atterrissent dans test/captures/.
import 'dart:io';

import 'package:cybersas/donnees.dart';
import 'package:cybersas/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _polices() async {
  for (final (famille, fichier) in [
    ('Syne', 'Syne'),
    ('SpaceGrotesk', 'SpaceGrotesk'),
    ('JetBrainsMono', 'JetBrainsMono'),
  ]) {
    final l = FontLoader(famille)
      ..addFont(Future.value(ByteData.sublistView(File('assets/polices/$fichier.ttf').readAsBytesSync())));
    await l.load();
  }
  // Les icônes Material.
  final chemin = '${Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter'}'
      '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  if (File(chemin).existsSync()) {
    final l = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(File(chemin).readAsBytesSync())));
    await l.load();
  }
}

const _formats = {
  'telephone': Size(390, 844),
  'fold-passeport': Size(412, 915),
  'fold-deplie-paysage': Size(832, 750),
  'fold-deplie-portrait': Size(750, 832),
};

void main() {
  setUpAll(_polices);

  for (final f in _formats.entries) {
    for (final (onglet, nom) in [(0, 'accueil'), (1, 'appareils'), (2, 'reglages')]) {
      testWidgets('${f.key} $nom', (t) async {
        t.view.physicalSize = f.value * 3;
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        await t.pumpWidget(CyberSas(reseau: Reseau()));
        await t.pump(const Duration(milliseconds: 400));
        if (onglet > 0) {
          await t.tap(find.text(['Accueil', 'Appareils', 'Réglages'][onglet]).last);
          await t.pump(const Duration(milliseconds: 400));
          await t.pump(const Duration(milliseconds: 400));
        }
        await expectLater(find.byType(CyberSas), matchesGoldenFile('captures/${f.key}-$nom.png'));
      });
    }
  }
}
