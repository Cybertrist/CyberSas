import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../composants.dart';
import '../dessins.dart';
import '../etat.dart';
import '../theme.dart';

/// Ajouter un appareil : une invitation à usage unique, valable dix minutes.
/// Le nouvel appareil la scanne, crée sa propre clé, puis attend que l'admin
/// signe son empreinte.
class EcranAjout extends StatefulWidget {
  const EcranAjout({super.key});

  @override
  State<EcranAjout> createState() => _EcranAjoutState();
}

class _EcranAjoutState extends State<EcranAjout> {
  // Exemple : le vrai code viendra du serveur (clé d'inscription).
  static const _code = 'SAS-7K4Q-92XD';
  final _fin = DateTime.now().add(const Duration(minutes: 10));
  late final Timer _minuteur;

  @override
  void initState() {
    super.initState();
    _minuteur = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _minuteur.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = EtatReseau.of(context);
    final reste = _fin.difference(DateTime.now());
    final expire = reste.isNegative;
    final chrono = expire
        ? 'Expirée'
        : 'Expire dans ${reste.inMinutes.toString().padLeft(2, '0')}:${(reste.inSeconds % 60).toString().padLeft(2, '0')}';

    final qr = Carte(
      lumineuse: true,
      padding: const EdgeInsets.all(22),
      child: Column(children: [
        Viseur(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: QrImageView(
              data: 'cybersas://rejoindre?serveur=${r.serveur}&code=$_code',
              size: 170,
              padding: EdgeInsets.zero,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Couleurs.cyan),
              dataModuleStyle:
                  const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFFDDF9FF)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(_code, style: mono(21, couleur: Couleurs.texte, graisse: 600, espacement: 2)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.schedule_rounded, size: 15, color: expire ? Couleurs.rouge : Couleurs.discret),
          const SizedBox(width: 6),
          Text(chrono, style: texte(13.5, couleur: expire ? Couleurs.rouge : Couleurs.secondaire)),
        ]),
      ]),
    );

    Widget etape(int n, String titre, String sous, {bool fait = false, bool active = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: n < 3 ? Border(bottom: BorderSide(color: Couleurs.bordure.withValues(alpha: 0.6))) : null,
          ),
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fait ? Couleurs.cyan : null,
                border: Border.all(color: fait || active ? Couleurs.cyan : Couleurs.bordure),
              ),
              child: fait
                  ? const Icon(Icons.check_rounded, size: 17, color: Couleurs.fond)
                  : Text('$n', style: mono(13, couleur: active ? Couleurs.cyan : Couleurs.discret)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titre, style: texte(15, graisse: 600, couleur: fait || active ? Couleurs.texte : Couleurs.secondaire)),
                Text(sous, style: texte(12.5, couleur: Couleurs.secondaire)),
              ]),
            ),
          ]),
        );

    final etapes = Carte(
      padding: EdgeInsets.zero,
      child: Column(children: [
        etape(1, 'Installer CyberSas', 'Sur le nouvel appareil', fait: true),
        etape(2, 'Scanner ou saisir le code', 'Le nouvel appareil crée sa propre clé', active: true),
        etape(3, 'Signature sur le téléphone de l\'admin', 'Après vérification de l\'empreinte'),
      ]),
    );

    final partager = BoutonLumineux(
      libelle: 'Partager l\'invitation',
      icone: Icons.share_rounded,
      onPressed: () => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Partage disponible avec le serveur réel'))),
    );

    return Scaffold(
      body: FondReseau(
        child: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            final large = c.maxWidth >= 600;
            final titre = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const BoutonRetour('Appareils'),
              const SizedBox(height: 16),
              Text('INVITATION · USAGE UNIQUE', style: etiquette(couleur: Couleurs.cyan)),
              const SizedBox(height: 4),
              Text('Ajouter un appareil', style: texte(29, graisse: 700)),
              const SizedBox(height: 16),
            ]);
            if (large) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  titre,
                  Expanded(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: qr),
                      const SizedBox(width: 20),
                      Expanded(child: Column(children: [etapes, const SizedBox(height: 16), partager])),
                    ]),
                  ),
                ]),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              children: [titre, qr, const SizedBox(height: 14), etapes, const SizedBox(height: 16), partager],
            );
          }),
        ),
      ),
    );
  }
}
