import 'package:flutter/material.dart';

import '../composants.dart';
import '../icones.dart';
import '../securite.dart';
import '../theme.dart';

/// L'appli verrouillée (réglage « Verrouiller l'appli ») : l'invite
/// d'empreinte s'ouvre d'elle-même, le bouton sert si on l'a fermée.
class EcranVerrou extends StatefulWidget {
  const EcranVerrou({super.key, required this.deverrouiller});
  final VoidCallback deverrouiller;

  @override
  State<EcranVerrou> createState() => _EcranVerrouState();
}

class _EcranVerrouState extends State<EcranVerrou> {
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _demander());
  }

  Future<void> _demander() async {
    if (_enCours) return;
    _enCours = true;
    // Le code du téléphone est accepté aussi : un doigt mouillé ne doit
    // pas fermer la porte.
    final ok = await confirmerIdentite('Déverrouiller CyberSas', biometrieSeule: false);
    _enCours = false;
    if (ok == Identite.confirmee) widget.deverrouiller();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Fond(
          child: SafeArea(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Marque(taille: 30),
                const SizedBox(height: 40),
                const Icone(Ico.empreinte, taille: 56, trait: 1.4, lueur: true),
                const SizedBox(height: 16),
                Text('CyberSas est verrouillée', style: texte(16, couleur: Couleurs.secondaire)),
                const SizedBox(height: 32),
                SizedBox(width: 240, child: BoutonContour(libelle: 'Déverrouiller', ico: Ico.empreinte, onTap: _demander)),
              ]),
            ),
          ),
        ),
      );
}
