import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../composants.dart';
import '../dessins.dart';
import '../etat.dart';
import '../theme.dart';

/// Rejoindre un réseau : l'adresse du serveur, la clé du verrou donnée par
/// l'admin, puis le compte Google.
class EcranConnexion extends StatefulWidget {
  const EcranConnexion({super.key});

  @override
  State<EcranConnexion> createState() => _EcranConnexionState();
}

class _EcranConnexionState extends State<EcranConnexion> {
  late final _serveur = TextEditingController(text: EtatReseau.of(context).serveur);
  final _verrou = TextEditingController();

  @override
  void dispose() {
    _serveur.dispose();
    _verrou.dispose();
    super.dispose();
  }

  Widget _champ({
    required IconData icone,
    required String libelle,
    required TextEditingController ctrl,
    String? indice,
    Widget? fin,
  }) =>
      Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
        decoration: BoxDecoration(
          color: Couleurs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Couleurs.bordure),
        ),
        child: Row(children: [
          Icon(icone, size: 20, color: Couleurs.cyan),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: ctrl,
              style: texte(16, graisse: 500),
              cursorColor: Couleurs.cyan,
              decoration: InputDecoration(
                labelText: libelle,
                labelStyle: texte(13, couleur: Couleurs.secondaire),
                floatingLabelStyle: texte(13, couleur: Couleurs.cyan),
                hintText: indice,
                hintStyle: texte(15, couleur: Couleurs.eteint),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          ?fin,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final formulaire = Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 118,
        height: 118,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.35), blurRadius: 40)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Image.asset('assets/icon/icon.png', fit: BoxFit.cover),
        ),
      ),
      const SizedBox(height: 22),
      const Marque(taille: 42),
      const SizedBox(height: 6),
      Text('Réseau privé, chiffré de bout en bout.', style: texte(15, couleur: Couleurs.secondaire)),
      const SizedBox(height: 30),
      _champ(icone: Icons.dns_outlined, libelle: 'Adresse du serveur', ctrl: _serveur),
      const SizedBox(height: 12),
      _champ(
        icone: Icons.key_rounded,
        libelle: 'Clé du verrou',
        indice: 'Collez la clé de l\'admin',
        ctrl: _verrou,
        fin: TextButton(
          onPressed: () async {
            final d = await Clipboard.getData(Clipboard.kTextPlain);
            if (d?.text != null) _verrou.text = d!.text!.trim();
          },
          child: Text('Coller', style: texte(14, graisse: 600, couleur: Couleurs.cyan)),
        ),
      ),
    ]);

    final bouton = Column(mainAxisSize: MainAxisSize.min, children: [
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: SizedBox(
            height: 58,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('G', style: texte(22, graisse: 700, couleur: const Color(0xFF4285F4))),
              const SizedBox(width: 12),
              Text('Continuer avec Google', style: texte(17, graisse: 600, couleur: const Color(0xFF1F2328))),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'L\'admin doit signer cet appareil avant l\'accès au réseau.',
        textAlign: TextAlign.center,
        style: texte(12.5, couleur: Couleurs.secondaire),
      ),
    ]);

    return Scaffold(
      body: FondReseau(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
                child: Column(children: [
                  Expanded(child: Center(child: SingleChildScrollView(child: formulaire))),
                  const SizedBox(height: 16),
                  bouton,
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
