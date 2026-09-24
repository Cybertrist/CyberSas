// Les dessins de l'appli, tracés en code plutôt qu'en images : ils restent
// nets à toutes les tailles d'écran et s'animent.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'donnees.dart';
import 'theme.dart';

/// Le fond de tous les écrans : bleu nuit, une grille réseau à peine
/// visible et une lueur cyan en haut.
class FondReseau extends StatelessWidget {
  const FondReseau({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _Grille(),
        child: child,
      );
}

class _Grille extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Couleurs.fondHaut, Couleurs.fond],
        ).createShader(r),
    );
    final trait = Paint()
      ..color = Couleurs.cyan.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    const pas = 28.0;
    for (var x = 0.0; x < size.width; x += pas) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), trait);
    }
    for (var y = 0.0; y < size.height; y += pas) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), trait);
    }
    canvas.drawCircle(
      Offset(size.width * 0.5, 0),
      size.width * 0.9,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.5, 0),
          size.width * 0.9,
          [Couleurs.bleu.withValues(alpha: 0.10), Colors.transparent],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Le tunnel du logo, en grand. Connecté, il brille et des paquets le
/// remontent ; coupé, il s'éteint.
class Tunnel extends StatefulWidget {
  const Tunnel({super.key, required this.allume});
  final bool allume;

  @override
  State<Tunnel> createState() => _TunnelState();
}

class _TunnelState extends State<Tunnel> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(seconds: 3))
    ..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1,
        child: RepaintBoundary(
          child: CustomPaint(painter: _PeintreTunnel(_anim, widget.allume)),
        ),
      );
}

class _PeintreTunnel extends CustomPainter {
  _PeintreTunnel(this.t, this.allume) : super(repaint: t);
  final Animation<double> t;
  final bool allume;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 1000;
    canvas.save();
    canvas.scale(s);
    final phase = t.value;
    final souffle = allume ? 0.75 + 0.25 * math.sin(phase * 2 * math.pi) : 0.0;
    final c1 = allume ? Couleurs.cyan : const Color(0xFF3A4652);
    final c2 = allume ? Couleurs.bleu : const Color(0xFF2A333D);

    // Halo derrière le tunnel.
    if (allume) {
      canvas.drawCircle(
        const Offset(512, 470),
        430,
        Paint()
          ..shader = ui.Gradient.radial(const Offset(512, 470), 430,
              [Couleurs.bleu.withValues(alpha: 0.22 * souffle), Colors.transparent]),
      );
    }

    // Le sol, qui s'enfonce vers la porte.
    final sol = Path()
      ..moveTo(0, 1000)
      ..lineTo(0, 780)
      ..lineTo(440, 575)
      ..lineTo(585, 575)
      ..lineTo(1000, 780)
      ..lineTo(1000, 1000)
      ..close();
    canvas.drawPath(
      sol,
      Paint()
        ..shader = ui.Gradient.linear(const Offset(0, 575), const Offset(0, 1000),
            [const Color(0xFF0B1C27), Couleurs.fond.withValues(alpha: 0)]),
    );

    void trait(Path p, double largeur, Color debut, Color fin, {double lueur = 1}) {
      final bornes = p.getBounds();
      final shader = ui.Gradient.linear(bornes.topCenter, bornes.bottomCenter, [debut, fin]);
      if (allume) {
        canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = largeur * 1.8
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..shader = shader
            ..color = Colors.white.withValues(alpha: 0.5 * lueur * souffle)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
        );
      }
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = largeur
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = shader,
      );
    }

    // La maison extérieure.
    final maison = Path()
      ..moveTo(215, 690)
      ..lineTo(215, 330)
      ..quadraticBezierTo(215, 300, 245, 285)
      ..lineTo(490, 160)
      ..quadraticBezierTo(512, 150, 534, 160)
      ..lineTo(779, 285)
      ..quadraticBezierTo(809, 300, 809, 330)
      ..lineTo(809, 690);
    trait(maison, 62, c1, c2);

    // Les deux arches intérieures.
    final arche1 = Path()
      ..moveTo(335, 640)
      ..lineTo(335, 460)
      ..arcToPoint(const Offset(689, 460), radius: const Radius.circular(177))
      ..lineTo(689, 640);
    trait(arche1, 38, c1.withValues(alpha: 0.75), c2.withValues(alpha: 0.55), lueur: 0.6);
    final arche2 = Path()
      ..moveTo(438, 600)
      ..lineTo(438, 505)
      ..arcToPoint(const Offset(586, 505), radius: const Radius.circular(74))
      ..lineTo(586, 600);
    trait(arche2, 30, c1.withValues(alpha: 0.6), c2.withValues(alpha: 0.45), lueur: 0.5);

    // La porte, qui éclaire tout.
    final porte = RRect.fromRectAndCorners(
      const Rect.fromLTRB(462, 440, 562, 575),
      topLeft: const Radius.circular(50),
      topRight: const Radius.circular(50),
    );
    if (allume) {
      canvas.drawRRect(
        porte.inflate(18),
        Paint()
          ..color = Couleurs.cyan.withValues(alpha: 0.55 * souffle)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
      );
    }
    canvas.drawRRect(
      porte,
      Paint()..color = allume ? const Color(0xFFB7F7FF) : const Color(0xFF26313B),
    );

    // Les trois chemins qui entrent dans le sas, avec leurs nœuds.
    final chemins = [
      Path()
        ..moveTo(485, 575)
        ..lineTo(335, 745)
        ..quadraticBezierTo(250, 830, 70, 910),
      Path()
        ..moveTo(512, 575)
        ..lineTo(512, 1000),
      Path()
        ..moveTo(539, 575)
        ..lineTo(689, 745)
        ..quadraticBezierTo(774, 830, 954, 910),
    ];
    for (final p in chemins) {
      trait(p, 11, c1, c2.withValues(alpha: 0.2), lueur: 0.8);
    }
    for (final n in const [Offset(335, 745), Offset(512, 845), Offset(689, 745)]) {
      if (allume) {
        canvas.drawCircle(
            n,
            50,
            Paint()
              ..color = Couleurs.cyan.withValues(alpha: 0.5 * souffle)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22));
      }
      canvas.drawOval(Rect.fromCenter(center: n, width: 72, height: 60),
          Paint()..color = allume ? const Color(0xFF7DF3FF) : const Color(0xFF3A4652));
    }

    // Les paquets qui remontent vers la porte.
    if (allume) {
      for (var i = 0; i < chemins.length; i++) {
        final m = chemins[i].computeMetrics().first;
        for (var k = 0; k < 2; k++) {
          final f = 1 - ((phase + i * 0.21 + k * 0.5) % 1);
          final pos = m.getTangentForOffset(m.length * f)?.position;
          if (pos == null) continue;
          canvas.drawCircle(
              pos,
              14,
              Paint()
                ..color = Colors.white.withValues(alpha: 0.9 * (1 - f * 0.4))
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PeintreTunnel old) => old.allume != allume;
}

/// La petite carte du réseau : le serveur au centre, les appareils autour.
class CarteReseau extends StatefulWidget {
  const CarteReseau({super.key, required this.appareils});
  final List<Appareil> appareils;

  @override
  State<CarteReseau> createState() => _CarteReseauState();
}

class _CarteReseauState extends State<CarteReseau> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(seconds: 2))
    ..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(painter: _PeintreCarte(_anim, widget.appareils), size: Size.infinite),
      );
}

class _PeintreCarte extends CustomPainter {
  _PeintreCarte(this.t, this.appareils) : super(repaint: t);
  final Animation<double> t;
  final List<Appareil> appareils;

  static const _places = [
    Offset(0.17, 0.30),
    Offset(0.83, 0.30),
    Offset(0.83, 0.74),
    Offset(0.17, 0.74),
    Offset(0.50, 0.14),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width * 0.5, size.height * 0.56);
    final autres = appareils.where((a) => a.type != TypeAppareil.serveur).toList();
    for (var i = 0; i < autres.length && i < _places.length; i++) {
      final a = autres[i];
      final p = Offset(_places[i].dx * size.width, _places[i].dy * size.height);
      final ligne = Paint()
        ..strokeWidth = 1.4
        ..color = a.enLigne
            ? Couleurs.cyan.withValues(alpha: 0.55)
            : Couleurs.eteint.withValues(alpha: 0.5);
      if (a.enLigne) {
        canvas.drawLine(centre, p, ligne);
        // Un paquet qui circule sur la liaison.
        final f = (t.value + i * 0.3) % 1;
        canvas.drawCircle(Offset.lerp(p, centre, f)!, 2.4, Paint()..color = Couleurs.cyan);
      } else {
        _pointilles(canvas, centre, p, ligne);
      }
      if (a.enLigne) {
        canvas.drawCircle(
            p,
            9,
            Paint()
              ..color = Couleurs.cyan.withValues(alpha: 0.35)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      }
      canvas.drawCircle(
          p,
          5,
          Paint()
            ..color = a.enLigne ? Couleurs.cyan : Couleurs.fond
            ..style = a.enLigne ? PaintingStyle.fill : PaintingStyle.stroke
            ..strokeWidth = 1.5);
      if (!a.enLigne) {
        canvas.drawCircle(p, 5, Paint()..color = Couleurs.eteint..style = PaintingStyle.stroke..strokeWidth = 1.5);
      }
      _texte(canvas, a.nom, '.${a.adresse.split('.').last}', p, p.dy < centre.dy, a.enLigne);
    }

    // Le serveur, au centre.
    final boite = RRect.fromRectAndRadius(Rect.fromCenter(center: centre, width: 34, height: 34),
        const Radius.circular(9));
    canvas.drawRRect(
        boite.inflate(4),
        Paint()
          ..color = Couleurs.cyan.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    canvas.drawRRect(boite, Paint()..color = Couleurs.surface);
    canvas.drawRRect(boite, Paint()..color = Couleurs.cyan..style = PaintingStyle.stroke..strokeWidth = 1.5);
    final toit = Path()
      ..moveTo(centre.dx - 7, centre.dy + 7)
      ..lineTo(centre.dx - 7, centre.dy - 2)
      ..lineTo(centre.dx, centre.dy - 8)
      ..lineTo(centre.dx + 7, centre.dy - 2)
      ..lineTo(centre.dx + 7, centre.dy + 7);
    canvas.drawPath(toit, Paint()..color = Couleurs.cyan..style = PaintingStyle.stroke..strokeWidth = 1.6);
    final tp = TextPainter(
      text: TextSpan(children: [
        TextSpan(text: 'serveur\n', style: mono(11, couleur: Couleurs.texte)),
        TextSpan(text: '.1', style: mono(11)),
      ]),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centre + Offset(-tp.width / 2, 22));
  }

  void _pointilles(Canvas c, Offset a, Offset b, Paint p) {
    const n = 14;
    for (var i = 0; i < n; i += 2) {
      c.drawLine(Offset.lerp(a, b, i / n)!, Offset.lerp(a, b, (i + 1) / n)!, p);
    }
  }

  /// Le nom au-dessus du nœud quand il est en haut, en dessous sinon : les
  /// liaisons partent vers le centre, jamais à travers le texte.
  void _texte(Canvas c, String nom, String fin, Offset p, bool dessus, bool allume) {
    final tp = TextPainter(
      text: TextSpan(children: [
        TextSpan(text: nom, style: mono(11, couleur: allume ? Couleurs.texte : Couleurs.discret)),
        TextSpan(text: ' $fin', style: mono(11)),
      ]),
      textDirection: TextDirection.ltr,
    )..layout();
    final y = dessus ? p.dy - tp.height - 10 : p.dy + 10;
    tp.paint(c, Offset(p.dx - tp.width / 2, y));
  }

  @override
  bool shouldRepaint(covariant _PeintreCarte old) => old.appareils != appareils;
}
