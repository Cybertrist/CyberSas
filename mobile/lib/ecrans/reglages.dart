import 'package:flutter/material.dart';

import '../composants.dart';
import '../etat.dart';
import '../theme.dart';
import 'connexion.dart';
import 'demandes.dart';

class EcranReglages extends StatelessWidget {
  const EcranReglages({super.key});

  @override
  Widget build(BuildContext context) {
    final r = EtatReseau.of(context);
    return LayoutBuilder(builder: (context, c) {
      final large = c.maxWidth >= 600;
      final compte = Carte(
        lumineuse: true,
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Couleurs.degrade),
            child: Text(r.compte[0], style: texte(18, graisse: 700, couleur: Couleurs.fond)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.compte, style: texte(17, graisse: 600)),
              Text('Connecté avec Google', style: texte(13, couleur: Couleurs.secondaire)),
            ]),
          ),
          Pastille(r.admin ? 'ADMIN' : 'MEMBRE'),
        ]),
      );
      final connexion = GroupeReglages(titre: 'Connexion', lignes: [
        LigneReglage(
          icone: Icons.power_settings_new_rounded,
          titre: 'VPN toujours actif',
          fin: Switch(value: r.toujoursActif, onChanged: (v) => r.reglage(() => r.toujoursActif = v)),
        ),
        LigneReglage(
          icone: Icons.smartphone_rounded,
          titre: 'Connexion au démarrage',
          separateur: false,
          fin: Switch(value: r.auDemarrage, onChanged: (v) => r.reglage(() => r.auDemarrage = v)),
        ),
      ]);
      final reseau = GroupeReglages(titre: 'Réseau', lignes: [
        LigneReglage(
          icone: Icons.language_rounded,
          titre: 'DNS privé',
          sousTitre: '*.sas.internal',
          fin: Switch(value: r.dnsPrive, onChanged: (v) => r.reglage(() => r.dnsPrive = v)),
        ),
        LigneReglage(
          icone: Icons.dns_outlined,
          titre: 'Serveur',
          separateur: false,
          fin: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(r.serveur, style: mono(12.5)),
            chevron,
          ]),
        ),
      ]);
      final securite = GroupeReglages(titre: 'Sécurité', lignes: [
        if (r.admin)
          const LigneReglage(
            icone: Icons.memory_rounded,
            titre: 'Clé du verrou',
            sousTitre: 'sur ce téléphone, protégée',
            fin: Pastille('STRONGBOX'),
          ),
        if (r.admin)
          LigneReglage(
            icone: Icons.verified_user_outlined,
            titre: 'Demandes en attente',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranDemandes())),
            fin: Row(mainAxisSize: MainAxisSize.min, children: [
              if (r.demandes.isNotEmpty)
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Couleurs.cyan,
                    boxShadow: [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.6), blurRadius: 10)],
                  ),
                  child: Text('${r.demandes.length}', style: mono(12, couleur: Couleurs.fond, graisse: 700)),
                ),
              chevron,
            ]),
          ),
        LigneReglage(
          icone: Icons.logout_rounded,
          titre: 'Quitter le réseau',
          couleur: Couleurs.rouge,
          separateur: false,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranConnexion())),
        ),
      ]);

      final titre = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('COMPTE · APPAREIL', style: etiquette(couleur: Couleurs.cyan)),
        const SizedBox(height: 4),
        Text('Réglages', style: texte(31, graisse: 700)),
        const SizedBox(height: 14),
      ]);

      if (large) {
        // Déplié : deux colonnes, rien à faire défiler.
        return ListView(padding: const EdgeInsets.fromLTRB(28, 20, 28, 24), children: [
          titre,
          compte,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(children: [connexion, reseau])),
            const SizedBox(width: 20),
            Expanded(child: securite),
          ]),
        ]);
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
        children: [titre, compte, connexion, reseau, securite],
      );
    });
  }
}
