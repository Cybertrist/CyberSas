import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../composants.dart';
import '../etat.dart';
import '../icones.dart';
import '../theme.dart';

/// Rejoindre un réseau : l'adresse du serveur, la clé publique du verrou
/// donnée par l'admin (elle épingle le verrou dès le départ), puis le
/// compte Google.
class EcranConnexion extends StatefulWidget {
  const EcranConnexion({super.key});

  @override
  State<EcranConnexion> createState() => _EcranConnexionState();
}

/// La clé du verrou s'écrit comme côté Go (internal/b64) : base64 standard,
/// canonique, 32 octets (Ed25519). Une clé mal recopiée est refusée ici,
/// avant même de contacter le serveur.
bool cleVerrouValide(String s) {
  try {
    final b = base64.decode(s);
    return b.length == 32 && base64.encode(b) == s;
  } on FormatException {
    return false;
  }
}

class _EcranConnexionState extends State<EcranConnexion> {
  late final _serveur = TextEditingController(text: EtatReseau.of(context).serveur);
  final _verrou = TextEditingController();
  final _focusServeur = FocusNode();
  final _focusVerrou = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusServeur.addListener(() => setState(() {}));
    _focusVerrou.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _serveur.dispose();
    _verrou.dispose();
    _focusServeur.dispose();
    _focusVerrou.dispose();
    super.dispose();
  }

  Future<void> _coller() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim() ?? '';
    if (t.isNotEmpty) setState(() => _verrou.text = t);
  }

  void _continuer() {
    final serveur = _serveur.text.trim();
    final cle = _verrou.text.trim();
    String? erreur;
    if (serveur.isEmpty || serveur.contains(' ')) {
      erreur = "Indiquez l'adresse du serveur.";
    } else if (!cleVerrouValide(cle)) {
      erreur = cle.isEmpty ? "Collez la clé du verrou donnée par l'admin." : "Cette clé du verrou n'est pas valide : recopiez-la en entier.";
    }
    if (erreur != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erreur)));
      return;
    }
    // La connexion Google et l'inscription passeront par le moteur Go ;
    // en attendant, on rejoint le réseau d'exemple.
    EtatReseau.of(context).rejoindre(serveur: serveur, cle: cle);
  }

  Widget _champ({
    required Ico ico,
    required String libelle,
    required TextEditingController ctrl,
    required FocusNode focus,
    String? indice,
    Widget? fin,
    TextInputType? clavier,
  }) {
    final actif = focus.hasFocus;
    return Bordee(
      bordure: actif ? Bords.cyan : Bords.plat,
      fond: actif ? const Color(0xEB090F16) : const Color(0xCC0C1117),
      rayon: 18,
      halo: actif ? [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.45), blurRadius: 24, spreadRadius: -8)] : null,
      onTap: focus.requestFocus,
      padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
      child: Row(children: [
        Icone(ico, couleur: actif ? Couleurs.cyan : Couleurs.secondaire, taille: 20, lueur: actif),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(libelle, style: texte(12.5, couleur: Couleurs.secondaire)),
            const SizedBox(height: 3),
            TextField(
              controller: ctrl,
              focusNode: focus,
              keyboardType: clavier,
              autocorrect: false,
              enableSuggestions: false,
              style: texte(16, graisse: 500),
              cursorColor: Couleurs.cyan,
              cursorWidth: 1.5,
              decoration: InputDecoration.collapsed(hintText: indice, hintStyle: texte(16, graisse: 500, couleur: Couleurs.tertiaire)),
            ),
          ]),
        ),
        ?fin,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        resizeToAvoidBottomInset: true,
        body: Fond(
          centre: const Alignment(0, -0.56),
          etendue: const Size(0.7, 0.34),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(
                      child: SansDefilement(
                        alignement: Alignment.topCenter,
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const _Logo(),
                          const SizedBox(height: 20),
                          const Center(child: Marque(taille: 38)),
                          const SizedBox(height: 10),
                          Text('Réseau privé, chiffré de bout en bout.',
                              textAlign: TextAlign.center, style: texte(13.5, couleur: Couleurs.secondaire)),
                          const SizedBox(height: 32),
                          _champ(
                            ico: Ico.serveurLigne,
                            libelle: 'Adresse du serveur',
                            ctrl: _serveur,
                            focus: _focusServeur,
                            indice: 'vpn.exemple.fr',
                            clavier: TextInputType.url,
                          ),
                          const SizedBox(height: 12),
                          _champ(
                            ico: Ico.cle,
                            libelle: 'Clé du verrou',
                            ctrl: _verrou,
                            focus: _focusVerrou,
                            indice: "Collez la clé de l'admin",
                            fin: TextButton(
                              onPressed: _coller,
                              style: TextButton.styleFrom(foregroundColor: Couleurs.cyan, minimumSize: const Size(48, 40)),
                              child: Text('Coller', style: texte(13, graisse: 600, couleur: Couleurs.cyan)),
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _BoutonGoogle(onTap: _continuer),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text("L'admin doit signer cet appareil avant l'accès au réseau.",
                          textAlign: TextAlign.center, style: texte(12, couleur: Couleurs.tertiaire, hauteur: 1.4)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox(
          width: 132,
          height: 132,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: -44,
              top: -44,
              right: -44,
              bottom: -44,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Couleurs.bleu.withValues(alpha: 0.3), Couleurs.bleu.withValues(alpha: 0)], stops: const [0, 0.65]),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  const BoxShadow(color: Couleurs.bordure, spreadRadius: 1),
                  BoxShadow(color: Couleurs.bleu.withValues(alpha: 0.6), blurRadius: 50, spreadRadius: -12, offset: const Offset(0, 16)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/icon/icon.png', width: 132, height: 132, fit: BoxFit.cover),
            ),
          ]),
        ),
      );
}

class _BoutonGoogle extends StatelessWidget {
  const _BoutonGoogle({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.45), blurRadius: 30, spreadRadius: -12, offset: const Offset(0, 10))],
        ),
        child: Material(
          color: Couleurs.texte,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 54,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SvgPicture.string(logoGoogle, width: 20, height: 20),
                const SizedBox(width: 12),
                Text('Continuer avec Google', style: texte(16, graisse: 600, couleur: Couleurs.fond)),
              ]),
            ),
          ),
        ),
      );
}
