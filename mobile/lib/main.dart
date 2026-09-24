import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dessins.dart';
import 'donnees.dart';
import 'ecrans/accueil.dart';
import 'ecrans/appareils.dart';
import 'ecrans/reglages.dart';
import 'etat.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(CyberSas(reseau: Reseau()));
}

class CyberSas extends StatelessWidget {
  const CyberSas({super.key, required this.reseau});
  final Reseau reseau;

  @override
  Widget build(BuildContext context) => EtatReseau(
        reseau: reseau,
        child: MaterialApp(
          title: 'CyberSas',
          debugShowCheckedModeBanner: false,
          theme: themeCyberSas(),
          home: const Coquille(),
        ),
      );
}

/// Les trois onglets, et la façon de naviguer selon l'écran :
/// - étroit (téléphone, écran extérieur « passeport » du Fold) : barre
///   flottante en bas ;
/// - déplié en portrait (3/4) : la même barre, centrée ;
/// - déplié en paysage (4/3) : un rail à gauche, et tout l'écran pour le
///   contenu.
class Coquille extends StatefulWidget {
  const Coquille({super.key});

  @override
  State<Coquille> createState() => _CoquilleState();
}

class _CoquilleState extends State<Coquille> {
  int _onglet = 0;

  static const _onglets = [
    (Icons.home_outlined, Icons.home_rounded, 'Accueil'),
    (Icons.hub_outlined, Icons.hub_rounded, 'Appareils'),
    (Icons.tune_rounded, Icons.tune_rounded, 'Réglages'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = const [EcranAccueil(), EcranAppareils(), EcranReglages()];
    return Scaffold(
      body: FondReseau(
        child: LayoutBuilder(builder: (context, c) {
          final paysage = c.maxWidth >= 700 && c.maxWidth > c.maxHeight;
          final contenu = IndexedStack(index: _onglet, children: pages);
          if (paysage) {
            return SafeArea(
              child: Row(children: [
                _Rail(onglet: _onglet, onglets: _onglets, choisir: (i) => setState(() => _onglet = i)),
                Expanded(child: contenu),
              ]),
            );
          }
          return SafeArea(
            bottom: false,
            child: Column(children: [
              Expanded(child: contenu),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 10 + MediaQuery.paddingOf(context).bottom),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: _BarreBas(onglet: _onglet, onglets: _onglets, choisir: (i) => setState(() => _onglet = i)),
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }
}

typedef _Onglet = (IconData, IconData, String);

class _BarreBas extends StatelessWidget {
  const _BarreBas({required this.onglet, required this.onglets, required this.choisir});
  final int onglet;
  final List<_Onglet> onglets;
  final void Function(int) choisir;

  @override
  Widget build(BuildContext context) => Container(
        height: 68,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Couleurs.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Couleurs.bordure.withValues(alpha: 0.9)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Row(children: [
          for (var i = 0; i < onglets.length; i++)
            Expanded(child: _Bouton(o: onglets[i], actif: i == onglet, onTap: () => choisir(i))),
        ]),
      );
}

class _Rail extends StatelessWidget {
  const _Rail({required this.onglet, required this.onglets, required this.choisir});
  final int onglet;
  final List<_Onglet> onglets;
  final void Function(int) choisir;

  @override
  Widget build(BuildContext context) => Container(
        width: 96,
        margin: const EdgeInsets.fromLTRB(14, 14, 0, 14),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Couleurs.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Couleurs.bordure.withValues(alpha: 0.9)),
        ),
        child: Column(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset('assets/icon/icon.png', width: 46, height: 46),
          ),
          const SizedBox(height: 28),
          for (var i = 0; i < onglets.length; i++)
            SizedBox(height: 76, child: _Bouton(o: onglets[i], actif: i == onglet, onTap: () => choisir(i))),
        ]),
      );
}

class _Bouton extends StatelessWidget {
  const _Bouton({required this.o, required this.actif, required this.onTap});
  final _Onglet o;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final couleur = actif ? Couleurs.cyan : Couleurs.discret;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(actif ? o.$2 : o.$1, size: 23, color: couleur, shadows: actif
            ? [Shadow(color: Couleurs.cyan.withValues(alpha: 0.8), blurRadius: 12)]
            : null),
        const SizedBox(height: 3),
        Text(o.$3, style: texte(12, graisse: actif ? 600 : 500, couleur: actif ? Couleurs.texte : Couleurs.discret)),
        const SizedBox(height: 3),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: actif ? 18 : 0,
          height: 2.5,
          decoration: BoxDecoration(
            color: Couleurs.cyan,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.8), blurRadius: 6)],
          ),
        ),
      ]),
    );
  }
}
