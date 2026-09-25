import 'package:flutter/material.dart';

import '../composants.dart';
import '../donnees.dart';
import '../etat.dart';
import '../icones.dart';
import '../securite.dart';
import '../theme.dart';

/// Admin : les appareils qui attendent la signature du verrou. On compare
/// l'empreinte de la clé avec celle affichée sur l'appareil, puis on signe
/// avec le doigt, par l'invite biométrique du téléphone.
class EcranDemandes extends StatelessWidget {
  const EcranDemandes({super.key});

  @override
  Widget build(BuildContext context) {
    final r = EtatReseau.of(context);
    final n = r.demandes.length;
    return Scaffold(
      body: Fond(
        centre: const Alignment(0, -0.72),
        etendue: const Size(0.8, 0.24),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                children: [
                  const Align(alignment: Alignment.centerLeft, child: BoutonRetour('Appareils')),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Demandes en attente', style: titre(26)),
                      const SizedBox(height: 8),
                      Text(
                        "Vérifie que l'empreinte affichée ici est la même que sur l'appareil, puis signe avec ton doigt.",
                        style: texte(13.5, couleur: Couleurs.secondaire, hauteur: 1.4),
                      ),
                    ]),
                  ),
                  for (final d in r.demandes) ...[
                    const SizedBox(height: 14),
                    _CarteDemande(d: d),
                  ],
                  if (n == 0) ...[
                    const SizedBox(height: 48),
                    const Center(child: Icone(Ico.coche, couleur: Couleurs.vert, taille: 34, lueur: true)),
                    const SizedBox(height: 12),
                    Text('Aucune demande en attente.', textAlign: TextAlign.center, style: texte(15, couleur: Couleurs.secondaire)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CarteDemande extends StatelessWidget {
  const _CarteDemande({required this.d});
  final Demande d;

  @override
  Widget build(BuildContext context) {
    final r = EtatReseau.of(context);
    return Carte(
      rayon: 22,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CaseIcone(d.type.ico, couleur: Couleurs.bleu, etat: EtatIcone.attente, taille: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.nom, style: texte(16, graisse: 600)),
              const SizedBox(height: 3),
              Text('${d.compte} · ${d.type.libelle}',
                  style: texte(12.5, couleur: Couleurs.secondaire), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        const Etiquette('Empreinte de sa clé'),
        const SizedBox(height: 8),
        Empreinte(d.empreinte, couleur: Couleurs.texte),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: BoutonFantome(
              libelle: 'Refuser',
              couleur: Couleurs.rougeClair,
              bord: Couleurs.rouge.withValues(alpha: 0.4),
              onTap: () async {
                final messager = ScaffoldMessenger.of(context);
                final e = await r.traiter(d);
                messager.showSnackBar(SnackBar(content: Text(e ?? '${d.nom} refusé')));
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: _BoutonSigner(d: d)),
        ]),
      ]),
    );
  }
}

/// « Signer » : l'invite d'empreinte d'Android s'ouvre tout de suite, sans
/// fenêtre intermédiaire.
class _BoutonSigner extends StatefulWidget {
  const _BoutonSigner({required this.d});
  final Demande d;

  @override
  State<_BoutonSigner> createState() => _BoutonSignerState();
}

class _BoutonSignerState extends State<_BoutonSigner> {
  bool _enCours = false;

  // La clé du verrou est dans le coffre du téléphone (Coffre.kt), sous une
  // clé du Keystore qui ne sert que dans les secondes qui suivent cette
  // empreinte : sans le doigt, pas de signature.
  Future<void> _signer() async {
    if (_enCours) return;
    final r = EtatReseau.of(context);
    final messager = ScaffoldMessenger.of(context);
    setState(() => _enCours = true);
    final d = widget.d;
    if (r.reel && !r.cleVerrouPresente) {
      setState(() => _enCours = false);
      messager.showSnackBar(const SnackBar(
        content: Text("La clé du verrou n'est pas sur ce téléphone : Réglages, Clé du verrou."),
      ));
      return;
    }
    final identite = await confirmerIdentite('Signer ${d.nom} (${d.empreinte.join('-')})');
    switch (identite) {
      case Identite.confirmee:
        final e = await r.signer(d);
        messager.showSnackBar(SnackBar(content: Text(e ?? '${d.nom} signé : il rejoint le réseau')));
      case Identite.impossible:
        messager.showSnackBar(const SnackBar(
          content: Text("Aucune empreinte enregistrée sur ce téléphone : ajoute-en une dans les réglages d'Android."),
        ));
      case Identite.annulee:
        break;
    }
    if (mounted) setState(() => _enCours = false);
  }

  @override
  Widget build(BuildContext context) => Carte(
        rayon: 14,
        fond: Couleurs.vert.withValues(alpha: 0.12),
        bord: Couleurs.vert.withValues(alpha: 0.5),
        onTap: _signer,
        child: SizedBox(
          height: 42,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icone(Ico.empreinte, couleur: Couleurs.vert, taille: 18),
            const SizedBox(width: 9),
            Text('Signer', style: texte(15, graisse: 600, couleur: Couleurs.vert)),
          ]),
        ),
      );
}
