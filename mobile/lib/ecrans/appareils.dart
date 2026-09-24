import 'package:flutter/material.dart';

import '../composants.dart';
import '../dessins.dart';
import '../donnees.dart';
import '../etat.dart';
import '../theme.dart';
import 'ajout.dart';
import 'demandes.dart';
import 'detail.dart';

/// Les appareils du réseau, rangés par propriétaire comme sur Tailscale.
///
/// [large] : l'écran intérieur déplié. En paysage, la liste et le détail
/// se partagent l'écran ; en portrait, la carte prend toute la largeur en
/// haut, puis liste et détail côte à côte.
class EcranAppareils extends StatefulWidget {
  const EcranAppareils({super.key});

  @override
  State<EcranAppareils> createState() => _EcranAppareilsState();
}

class _EcranAppareilsState extends State<EcranAppareils> {
  String _choisi = 'maison';

  @override
  Widget build(BuildContext context) {
    final r = EtatReseau.of(context);
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 600) {
        return ListeAppareils(
          r: r,
          onChoisir: (a) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EcranDetail(nom: a.nom))),
        );
      }
      final detail = PanneauDetail(appareil: r.appareil(_choisi), compact: false);
      void choisir(Appareil a) => setState(() => _choisi = a.nom);

      final ecran = MediaQuery.sizeOf(context);
      if (ecran.width > ecran.height) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 10, child: ListeAppareils(r: r, onChoisir: choisir, choisi: _choisi, marges: false)),
            const SizedBox(width: 24),
            Expanded(
              flex: 9,
              child: Carte(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                child: detail,
              ),
            ),
          ]),
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          EnTeteAppareils(r: r),
          const SizedBox(height: 14),
          SizedBox(height: 230, child: CarteTopologie(r: r)),
          const SizedBox(height: 14),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: ListeAppareils(r: r, onChoisir: choisir, choisi: _choisi, marges: false, sansEntete: true),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Carte(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16), child: detail),
              ),
            ]),
          ),
          const SizedBox(height: 16),
        ]),
      );
    });
  }
}

class EnTeteAppareils extends StatelessWidget {
  const EnTeteAppareils({super.key, required this.r});
  final Reseau r;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('RÉSEAU SAS · ${r.plage}', style: etiquette(couleur: Couleurs.cyan)),
            const SizedBox(height: 4),
            Text('Appareils', style: texte(31, graisse: 700)),
          ]),
        ),
        _BoutonAjouter(),
      ]);
}

class _BoutonAjouter extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.25), blurRadius: 16)],
        ),
        child: Material(
          color: Couleurs.cyan.withValues(alpha: 0.08),
          shape: StadiumBorder(side: BorderSide(color: Couleurs.cyan.withValues(alpha: 0.7))),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranAjout())),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_rounded, size: 20, color: Couleurs.cyan),
                const SizedBox(width: 6),
                Text('Ajouter', style: texte(15.5, graisse: 600)),
              ]),
            ),
          ),
        ),
      );
}

class CarteTopologie extends StatelessWidget {
  const CarteTopologie({super.key, required this.r});
  final Reseau r;

  @override
  Widget build(BuildContext context) => Carte(
        padding: const EdgeInsets.all(12),
        child: Stack(children: [
          Positioned.fill(child: CarteReseau(appareils: r.acceptes)),
          Positioned(left: 2, top: 0, child: Text('TOPOLOGIE', style: etiquette(taille: 10.5))),
          Positioned(
            left: 0,
            bottom: 0,
            child: Row(children: [
              _Compteur(icone: Icons.monitor_heart_outlined, valeur: r.enLigne, allume: true),
              const SizedBox(width: 6),
              _Compteur(icone: Icons.power_settings_new_rounded, valeur: r.horsLigne, allume: false),
            ]),
          ),
        ]),
      );
}

class _Compteur extends StatelessWidget {
  const _Compteur({required this.icone, required this.valeur, required this.allume});
  final IconData icone;
  final int valeur;
  final bool allume;

  @override
  Widget build(BuildContext context) {
    final c = allume ? Couleurs.cyan : Couleurs.discret;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Couleurs.fond.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(icone, size: 14, color: c),
        const SizedBox(width: 5),
        Text('$valeur', style: mono(12.5, couleur: c)),
      ]),
    );
  }
}

class ListeAppareils extends StatelessWidget {
  const ListeAppareils({
    super.key,
    required this.r,
    required this.onChoisir,
    this.choisi,
    this.marges = true,
    this.sansEntete = false,
  });
  final Reseau r;
  final void Function(Appareil) onChoisir;
  final String? choisi;
  final bool marges;
  final bool sansEntete;

  @override
  Widget build(BuildContext context) {
    final groupes = <String, List<Appareil>>{};
    for (final a in r.acceptes) {
      groupes.putIfAbsent(a.proprietaire, () => []).add(a);
    }
    return ListView(
      padding: marges ? const EdgeInsets.fromLTRB(20, 12, 20, 110) : const EdgeInsets.only(bottom: 16),
      children: [
        if (!sansEntete) ...[
          EnTeteAppareils(r: r),
          const SizedBox(height: 14),
          SizedBox(height: marges ? 190 : 210, child: CarteTopologie(r: r)),
        ],
        if (r.admin && r.demandes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Carte(
            lumineuse: true,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranDemandes())),
            child: Row(children: [
              const Icon(Icons.pending_actions_rounded, size: 20, color: Couleurs.cyan),
              const SizedBox(width: 10),
              Expanded(child: Text('${r.demandes.length} demandes en attente', style: texte(14.5, graisse: 500))),
              Text('Voir', style: texte(14.5, graisse: 600, couleur: Couleurs.cyan)),
              const Icon(Icons.chevron_right_rounded, size: 18, color: Couleurs.cyan),
            ]),
          ),
        ],
        for (final e in groupes.entries) ...[
          TitreSection('Propriétaire · ${e.key}'),
          Carte(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (var i = 0; i < e.value.length; i++)
                _LigneAppareil(
                  a: e.value[i],
                  choisi: e.value[i].nom == choisi,
                  dernier: i == e.value.length - 1,
                  onTap: () => onChoisir(e.value[i]),
                ),
            ]),
          ),
        ],
        if (r.refuses.isNotEmpty) ...[
          const TitreSection('Accès refusé', couleur: Couleurs.rouge),
          for (final a in r.refuses)
            Carte(
              rouge: true,
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                IconeAppareil(a.type, refuse: true, taille: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.nom, style: texte(15.5, graisse: 600)),
                    Text('Tentative d\'accès · non signé', style: texte(12.5, couleur: Couleurs.rouge)),
                  ]),
                ),
                Text('BLOQUÉ', style: etiquette(couleur: Couleurs.rouge)),
              ]),
            ),
        ],
      ],
    );
  }
}

class _LigneAppareil extends StatelessWidget {
  const _LigneAppareil({required this.a, required this.choisi, required this.dernier, required this.onTap});
  final Appareil a;
  final bool choisi;
  final bool dernier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget fin;
    if (a.moi) {
      fin = const Pastille('Vous', pleine: true);
    } else if (!a.enLigne) {
      fin = Text('HORS LIGNE', style: etiquette(taille: 10.5));
    } else if (a.ports.any((p) => p == 80 || p == 443)) {
      fin = Row(mainAxisSize: MainAxisSize.min, children: [
        for (final p in a.ports) ...[Pastille(':$p'), const SizedBox(width: 4)],
        chevron,
      ]);
    } else {
      fin = Text('EN LIGNE', style: etiquette(couleur: Couleurs.cyan, taille: 10.5));
    }
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: choisi ? Couleurs.cyan.withValues(alpha: 0.07) : null,
          border: Border(
            left: BorderSide(color: choisi ? Couleurs.cyan : Colors.transparent, width: 2),
            bottom: dernier ? BorderSide.none : BorderSide(color: Couleurs.bordure.withValues(alpha: 0.6)),
          ),
        ),
        child: Row(children: [
          IconeAppareil(a.type, enLigne: a.enLigne, taille: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.nom,
                  style: texte(15.5, graisse: 600, couleur: a.enLigne ? Couleurs.texte : Couleurs.secondaire)),
              Text(a.adresse, style: mono(12)),
            ]),
          ),
          fin,
        ]),
      ),
    );
  }
}
