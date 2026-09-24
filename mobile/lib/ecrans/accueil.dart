import 'package:flutter/material.dart';

import '../composants.dart';
import '../dessins.dart';
import '../donnees.dart';
import '../etat.dart';
import '../theme.dart';

/// L'accueil : le tunnel, l'interrupteur, et ce qui dit qu'on est protégé.
/// Sur un écran étroit tout s'empile ; déplié en paysage, le tunnel passe
/// à gauche ; déplié en portrait, les informations se rangent sur deux
/// colonnes sous le tunnel.
class EcranAccueil extends StatelessWidget {
  const EcranAccueil({super.key});

  @override
  Widget build(BuildContext context) {
    final r = EtatReseau.of(context);
    return LayoutBuilder(builder: (context, c) {
      final ecran = MediaQuery.sizeOf(context);
      // L'orientation se lit sur l'écran entier : à côté du rail, la place
      // restante est presque carrée même en paysage.
      final paysage = ecran.width >= 700 && ecran.width > ecran.height;
      final grandPortrait = c.maxWidth >= 600 && !paysage;
      final entete = _Entete(r: r, grand: c.maxWidth >= 600);

      if (paysage) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(children: [
            entete,
            const SizedBox(height: 16),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _ZoneTunnel(r: r)),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _CarteEtat(r: r, grand: true),
                    const SizedBox(height: 14),
                    _CarteInfos(r: r),
                    const SizedBox(height: 14),
                    _CarteSecurite(r: r),
                  ]),
                ),
              ]),
            ),
          ]),
        );
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, grandPortrait ? 16 : 8),
        child: Column(children: [
          entete,
          const SizedBox(height: 8),
          Expanded(child: _ZoneTunnel(r: r)),
          const SizedBox(height: 12),
          _CarteEtat(r: r, grand: grandPortrait),
          const SizedBox(height: 12),
          if (grandPortrait)
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _CarteInfos(r: r)),
                const SizedBox(width: 12),
                Expanded(child: _CarteSecurite(r: r)),
              ]),
            )
          else
            _CarteInfos(r: r, avecSecurite: true),
        ]),
      );
    });
  }
}

class _Entete extends StatelessWidget {
  const _Entete({required this.r, required this.grand});
  final Reseau r;
  final bool grand;

  @override
  Widget build(BuildContext context) => Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset('assets/icon/icon.png', width: 30, height: 30),
        ),
        const SizedBox(width: 10),
        // Rétrécit plutôt que déborder, dans la colonne étroite du paysage.
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(fit: BoxFit.scaleDown, child: Marque(taille: grand ? 30 : 26)),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Couleurs.surface,
            border: Border.all(color: Couleurs.bordure),
          ),
          child: Text(r.compte[0], style: texte(15, graisse: 600)),
        ),
      ]);
}

class _ZoneTunnel extends StatelessWidget {
  const _ZoneTunnel({required this.r});
  final Reseau r;

  @override
  Widget build(BuildContext context) => Viseur(
        couleur: r.connecte ? Couleurs.cyan.withValues(alpha: 0.5) : Couleurs.eteint,
        child: Stack(children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 28, 8, 0),
              child: Center(child: Tunnel(allume: r.connecte)),
            ),
          ),
          Positioned(left: 14, top: 12, child: Text(r.plage, style: mono(11))),
          Positioned(right: 14, top: 12, child: Text('E2E · NOISE', style: mono(11))),
        ]),
      );
}

String _depuis(DateTime debut) {
  final d = DateTime.now().difference(debut);
  if (d.inHours > 0) return 'depuis ${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')}';
  return 'depuis ${d.inMinutes} min';
}

class _CarteEtat extends StatelessWidget {
  const _CarteEtat({required this.r, required this.grand});
  final Reseau r;
  final bool grand;

  @override
  Widget build(BuildContext context) => Carte(
        lumineuse: r.connecte,
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TUNNEL SAS', style: etiquette()),
              const SizedBox(height: 4),
              Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 8, children: [
                // Jamais coupé en deux : le mot rétrécit s'il manque de place.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    r.connecte ? 'Connecté' : 'Déconnecté',
                    softWrap: false,
                    style: syne(grand ? 32 : 27, couleur: r.connecte ? Couleurs.cyan : Couleurs.secondaire)
                        .copyWith(shadows: r.connecte
                            ? [Shadow(color: Couleurs.cyan.withValues(alpha: 0.5), blurRadius: 16)]
                            : null),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(r.connecte ? _depuis(r.debutConnexion) : 'aucun trafic ne passe',
                      style: texte(13, couleur: Couleurs.secondaire)),
                ),
              ]),
            ]),
          ),
          // L'interrupteur grossi déborde de sa place : on la lui réserve.
          const SizedBox(width: 14),
          Transform.scale(
            scale: 1.15,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: r.connecte
                    ? [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.45), blurRadius: 18)]
                    : null,
              ),
              child: Switch(value: r.connecte, onChanged: r.basculer),
            ),
          ),
        ]),
      );
}

class _CarteInfos extends StatelessWidget {
  const _CarteInfos({required this.r, this.avecSecurite = false});
  final Reseau r;
  final bool avecSecurite;

  @override
  Widget build(BuildContext context) => Carte(
        padding: EdgeInsets.zero,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('ADRESSE PRIVÉE', style: etiquette()),
                  const SizedBox(height: 4),
                  Text(r.monAdresse, style: mono(22, couleur: Couleurs.texte, graisse: 600)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('APPAREIL', style: etiquette()),
                const SizedBox(height: 6),
                Text(r.monNom, style: mono(14, couleur: Couleurs.texte)),
              ]),
            ]),
          ),
          if (avecSecurite) ...[
            Divider(height: 1, color: Couleurs.bordure.withValues(alpha: 0.7)),
            _Garanties(r: r),
          ],
        ]),
      );
}

class _CarteSecurite extends StatelessWidget {
  const _CarteSecurite({required this.r});
  final Reseau r;

  @override
  Widget build(BuildContext context) => Carte(padding: EdgeInsets.zero, child: _Garanties(r: r));
}

class _Garanties extends StatelessWidget {
  const _Garanties({required this.r});
  final Reseau r;

  @override
  Widget build(BuildContext context) {
    Widget item(IconData i, String titre, String sous) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(i, size: 18, color: r.connecte ? Couleurs.cyan : Couleurs.eteint),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titre, style: texte(13.5, graisse: 600)),
                  Text(sous, style: texte(11.5, couleur: Couleurs.secondaire)),
                ]),
              ),
            ]),
          ),
        );
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        item(Icons.lock_outline_rounded, 'Chiffré de bout en bout', 'Illisible en route'),
        VerticalDivider(width: 1, color: Couleurs.bordure.withValues(alpha: 0.7)),
        item(Icons.verified_user_outlined, 'Verrou vérifié', 'Signé par l\'admin'),
      ]),
    );
  }
}
