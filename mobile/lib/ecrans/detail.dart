import 'package:flutter/material.dart';

import '../composants.dart';
import '../dessins.dart';
import '../donnees.dart';
import '../etat.dart';
import '../theme.dart';

/// Le détail d'un appareil, en plein écran (téléphone).
class EcranDetail extends StatelessWidget {
  const EcranDetail({super.key, required this.nom});
  final String nom;

  @override
  Widget build(BuildContext context) {
    final a = EtatReseau.of(context).appareil(nom);
    return Scaffold(
      body: FondReseau(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const BoutonRetour('Appareils'),
              const SizedBox(height: 16),
              Expanded(child: PanneauDetail(appareil: a, compact: true)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Le contenu du détail, réutilisé tel quel dans le panneau de droite
/// de l'écran déplié.
class PanneauDetail extends StatelessWidget {
  const PanneauDetail({super.key, required this.appareil, required this.compact});
  final Appareil appareil;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final a = appareil;
    final joursRestants = a.expire == null ? 0 : a.expire!.difference(DateTime.now()).inDays.clamp(0, 90);
    final web = a.ports.any((p) => p == 80 || p == 443);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ListView(padding: EdgeInsets.zero, children: [
          Row(children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: Couleurs.surfaceHaute,
                border: Border.all(color: Couleurs.cyan.withValues(alpha: a.enLigne ? 0.55 : 0.15)),
                boxShadow: a.enLigne
                    ? [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.25), blurRadius: 22)]
                    : null,
              ),
              child: Icon(iconeDe(a.type), size: 36, color: a.enLigne ? Couleurs.cyan : Couleurs.eteint),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${a.enLigne ? '●  EN LIGNE' : '○  HORS LIGNE'} · ${a.proprietaire.toUpperCase()}',
                  style: etiquette(couleur: a.enLigne ? Couleurs.cyan : Couleurs.discret),
                ),
                const SizedBox(height: 2),
                Text(a.nom, style: texte(compact ? 30 : 32, graisse: 700), overflow: TextOverflow.ellipsis),
                Text(a.adresse, style: mono(13.5)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          Carte(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('NOM', style: etiquette()),
              const SizedBox(height: 6),
              Text.rich(TextSpan(children: [
                TextSpan(text: a.nom, style: mono(16, couleur: Couleurs.cyan, graisse: 600)),
                TextSpan(text: '.sas.internal', style: mono(16, couleur: Couleurs.texte)),
              ])),
            ]),
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: Carte(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('ADRESSE', style: etiquette()),
                    const SizedBox(height: 6),
                    Text(a.adresse, style: mono(17, couleur: Couleurs.texte, graisse: 600)),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Carte(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('PORTS OUVERTS', style: etiquette()),
                    const SizedBox(height: 6),
                    a.ports.isEmpty
                        ? Text('aucun', style: mono(14))
                        : Wrap(spacing: 6, runSpacing: 6, children: [for (final p in a.ports) Pastille('$p')]),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Carte(
            lumineuse: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.verified_user_outlined, size: 22, color: Couleurs.cyan),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Certificat signé', style: texte(15.5, graisse: 600)),
                  Text('par la clé de l\'admin', style: texte(12.5, couleur: Couleurs.secondaire)),
                ]),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Text('Valable jusqu\'au', style: texte(13.5, couleur: Couleurs.secondaire)),
                const Spacer(),
                if (a.expire != null)
                  Text(
                    '${a.expire!.day.toString().padLeft(2, '0')}/${a.expire!.month.toString().padLeft(2, '0')}/${a.expire!.year}',
                    style: mono(14, couleur: Couleurs.texte),
                  ),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: joursRestants / 90,
                  minHeight: 4,
                  backgroundColor: Couleurs.bordure,
                  valueColor: const AlwaysStoppedAnimation(Couleurs.cyan),
                ),
              ),
              const SizedBox(height: 6),
              Text('$joursRestants jours restants', style: mono(11)),
              const SizedBox(height: 14),
              Text('EMPREINTE', style: etiquette()),
              const SizedBox(height: 8),
              Empreinte(a.empreinte),
            ]),
          ),
        ]),
      ),
      if (web) ...[
        const SizedBox(height: 14),
        BoutonLumineux(
          libelle: 'Ouvrir dans le navigateur',
          icone: Icons.language_rounded,
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ouverture de http://${a.nomInterne} (disponible avec le moteur VPN)')),
          ),
        ),
      ],
    ]);
  }
}
