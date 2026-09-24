// Les pièces réutilisées par tous les écrans.
import 'package:flutter/material.dart';

import 'donnees.dart';
import 'theme.dart';

/// « CyberSas », « Sas » en cyan, comme sur le logo.
class Marque extends StatelessWidget {
  const Marque({super.key, this.taille = 26});
  final double taille;

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(children: [
        TextSpan(text: 'Cyber', style: syne(taille)),
        TextSpan(
          text: 'Sas',
          style: syne(taille, couleur: Couleurs.cyan).copyWith(shadows: [
            Shadow(color: Couleurs.cyan.withValues(alpha: 0.55), blurRadius: taille * 0.6),
          ]),
        ),
      ]));
}

/// Une carte en verre sombre. [lumineuse] : bordure cyan et halo.
class Carte extends StatelessWidget {
  const Carte({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.lumineuse = false,
    this.rouge = false,
    this.onTap,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool lumineuse;
  final bool rouge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = rouge ? Couleurs.rouge : Couleurs.cyan;
    final bord = lumineuse || rouge ? accent.withValues(alpha: 0.45) : Couleurs.bordure.withValues(alpha: 0.8);
    final decor = BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: rouge
            ? [const Color(0xFF1C0E14), const Color(0xFF12090D)]
            : [Couleurs.surfaceHaute.withValues(alpha: 0.85), Couleurs.surface.withValues(alpha: 0.85)],
      ),
      border: Border.all(color: bord),
      boxShadow: lumineuse
          ? [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.14), blurRadius: 24, spreadRadius: -2)]
          : null,
    );
    return Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: decor,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Une pastille : « ADMIN », « :443 », « Vous »…
class Pastille extends StatelessWidget {
  const Pastille(this.texte, {super.key, this.couleur = Couleurs.cyan, this.pleine = false});
  final String texte;
  final Color couleur;
  final bool pleine;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: pleine ? 0.16 : 0.06),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: couleur.withValues(alpha: 0.45)),
        ),
        child: Text(texte, style: mono(11, couleur: couleur, espacement: 0.8)),
      );
}

/// Un petit titre de section : « PROPRIÉTAIRE · ADMIN ».
class TitreSection extends StatelessWidget {
  const TitreSection(this.texte, {super.key, this.couleur = Couleurs.discret});
  final String texte;
  final Color couleur;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(texte.toUpperCase(), style: etiquette(couleur: couleur)),
      );
}

IconData iconeDe(TypeAppareil t) => switch (t) {
      TypeAppareil.serveur => Icons.dns_outlined,
      TypeAppareil.maison => Icons.home_outlined,
      TypeAppareil.telephone => Icons.smartphone_outlined,
      TypeAppareil.ordinateur => Icons.laptop_outlined,
      TypeAppareil.tablette => Icons.tablet_android_outlined,
      TypeAppareil.inconnu => Icons.close_rounded,
    };

String libelleDe(TypeAppareil t) => switch (t) {
      TypeAppareil.serveur => 'SERVEUR',
      TypeAppareil.maison => 'MACHINE',
      TypeAppareil.telephone => 'TÉLÉPHONE',
      TypeAppareil.ordinateur => 'PORTABLE',
      TypeAppareil.tablette => 'TABLETTE',
      TypeAppareil.inconnu => 'INCONNU',
    };

/// L'icône d'un appareil, avec son point d'état en bas à droite.
class IconeAppareil extends StatelessWidget {
  const IconeAppareil(this.type, {super.key, this.enLigne = true, this.refuse = false, this.taille = 40});
  final TypeAppareil type;
  final bool enLigne;
  final bool refuse;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final couleur = refuse ? Couleurs.rouge : (enLigne ? Couleurs.cyan : Couleurs.eteint);
    return SizedBox(
      width: taille + 4,
      height: taille + 4,
      child: Stack(children: [
        Container(
          width: taille,
          height: taille,
          decoration: BoxDecoration(
            color: couleur.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(taille * 0.3),
            border: Border.all(color: couleur.withValues(alpha: 0.35)),
          ),
          child: Icon(iconeDe(type), size: taille * 0.5, color: couleur),
        ),
        if (!refuse)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enLigne ? Couleurs.cyan : Couleurs.fond,
                border: Border.all(color: enLigne ? Couleurs.fond : Couleurs.eteint, width: 2),
                boxShadow: enLigne
                    ? [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.7), blurRadius: 6)]
                    : null,
              ),
            ),
          ),
      ]),
    );
  }
}

/// L'empreinte d'une clé en trois blocs, faite pour être comparée à l'œil.
class Empreinte extends StatelessWidget {
  const Empreinte(this.blocs, {super.key});
  final List<String> blocs;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < blocs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Couleurs.cyan.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Couleurs.cyan.withValues(alpha: 0.35)),
                ),
                child: Text(blocs[i], style: mono(15, couleur: Couleurs.cyan, graisse: 600)),
              ),
            ),
          ],
        ],
      );
}

/// Bouton principal au contour lumineux.
class BoutonLumineux extends StatelessWidget {
  const BoutonLumineux({super.key, required this.libelle, required this.icone, this.onPressed, this.plein = false});
  final String libelle;
  final IconData icone;
  final VoidCallback? onPressed;
  final bool plein;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.18), blurRadius: 22)],
        ),
        child: Material(
          color: plein ? null : Couleurs.cyan.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              gradient: plein ? Couleurs.degrade : null,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Couleurs.cyan.withValues(alpha: 0.6)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onPressed,
              child: SizedBox(
                height: 54,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icone, size: 19, color: plein ? Couleurs.fond : Couleurs.cyan),
                  const SizedBox(width: 10),
                  Text(libelle,
                      style: texte(16, graisse: 600, couleur: plein ? Couleurs.fond : Couleurs.texte)),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// « < Appareils » : le retour, en pilule.
class BoutonRetour extends StatelessWidget {
  const BoutonRetour(this.libelle, {super.key});
  final String libelle;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: Couleurs.surface,
          shape: StadiumBorder(side: BorderSide(color: Couleurs.bordure.withValues(alpha: 0.9))),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => Navigator.of(context).maybePop(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.chevron_left_rounded, size: 20, color: Couleurs.cyan),
                Text(libelle, style: texte(15, graisse: 500)),
              ]),
            ),
          ),
        ),
      );
}

/// Les coins d'un viseur, autour du QR ou du tunnel.
class Viseur extends StatelessWidget {
  const Viseur({super.key, required this.child, this.couleur = Couleurs.cyan});
  final Widget child;
  final Color couleur;

  @override
  Widget build(BuildContext context) => CustomPaint(
        foregroundPainter: _Coins(couleur),
        child: child,
      );
}

class _Coins extends CustomPainter {
  _Coins(this.c);
  final Color c;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = c.withValues(alpha: 0.8)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 18.0;
    for (final (o, dx, dy) in [
      (Offset.zero, 1.0, 1.0),
      (Offset(s.width, 0), -1.0, 1.0),
      (Offset(0, s.height), 1.0, -1.0),
      (Offset(s.width, s.height), -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(o.dx, o.dy + dy * l)
          ..lineTo(o.dx, o.dy)
          ..lineTo(o.dx + dx * l, o.dy),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Coins old) => old.c != c;
}

/// Une ligne de réglage : icône, titre, sous-titre, et à droite ce qu'on veut.
class LigneReglage extends StatelessWidget {
  const LigneReglage({
    super.key,
    required this.icone,
    required this.titre,
    this.sousTitre,
    this.fin,
    this.onTap,
    this.couleur = Couleurs.texte,
    this.separateur = true,
  });
  final IconData icone;
  final String titre;
  final String? sousTitre;
  final Widget? fin;
  final VoidCallback? onTap;
  final Color couleur;
  final bool separateur;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            border: separateur
                ? Border(bottom: BorderSide(color: Couleurs.bordure.withValues(alpha: 0.6)))
                : null,
          ),
          child: Row(children: [
            Icon(icone, size: 20, color: couleur == Couleurs.texte ? Couleurs.cyan : couleur),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titre, style: texte(15.5, graisse: 500, couleur: couleur)),
                if (sousTitre != null) Text(sousTitre!, style: mono(11.5)),
              ]),
            ),
            ?fin,
          ]),
        ),
      );
}

/// Un bloc de lignes de réglage, dans une carte.
class GroupeReglages extends StatelessWidget {
  const GroupeReglages({super.key, required this.titre, required this.lignes});
  final String titre;
  final List<Widget> lignes;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TitreSection(titre),
          Carte(padding: EdgeInsets.zero, child: Column(children: lignes)),
        ],
      );
}

/// Chevron discret en fin de ligne.
const chevron = Icon(Icons.chevron_right_rounded, size: 20, color: Couleurs.discret);
