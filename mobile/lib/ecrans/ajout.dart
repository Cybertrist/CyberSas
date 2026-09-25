import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../composants.dart';
import '../donnees.dart';
import '../etat.dart';
import '../icones.dart';
import '../theme.dart';

/// Inviter un nouvel appareil : un code à usage unique, valable 10 minutes,
/// en QR et en clair.
class EcranAjout extends StatefulWidget {
  const EcranAjout({super.key});

  @override
  State<EcranAjout> createState() => _EcranAjoutState();
}

class _EcranAjoutState extends State<EcranAjout> {
  late Invitation _invitation = Invitation(EtatReseau.of(context).serveur);
  late final Timer _horloge;

  @override
  void initState() {
    super.initState();
    _horloge = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _horloge.cancel();
    super.dispose();
  }

  Duration get _reste {
    final d = _invitation.expire.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  void _renouveler() => setState(() => _invitation = Invitation(_invitation.serveur));

  Future<void> _partager() => SharePlus.instance.share(ShareParams(
        subject: 'Invitation CyberSas',
        text: 'Rejoins mon réseau CyberSas.\n'
            'Serveur : ${_invitation.serveur}\n'
            'Code : ${_invitation.code} (usage unique, 10 minutes)\n'
            '${_invitation.charge}',
      ));

  @override
  Widget build(BuildContext context) {
    final reste = _reste;
    final expiree = reste == Duration.zero;
    final mm = reste.inMinutes.toString().padLeft(2, '0');
    final ss = (reste.inSeconds % 60).toString().padLeft(2, '0');

    return Scaffold(
      body: Fond(
        centre: const Alignment(0, -0.32),
        etendue: const Size(0.7, 0.3),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Align(alignment: Alignment.centerLeft, child: BoutonRetour('Appareils')),
                  const SizedBox(height: 14),
                  Expanded(
                    child: SansDefilement(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Ajouter un appareil', style: titre(28)),
                            const SizedBox(height: 8),
                            Text('Un code à usage unique, valable 10 minutes.', style: texte(13.5, couleur: Couleurs.secondaire)),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        Bordee(
                          bordure: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0x9931E7FD), Couleurs.bordure, Color(0x7301B9FD)],
                            stops: [0, 0.45, 1],
                          ),
                          fond: const Color(0xEB090F16),
                          rayon: 24,
                          halo: [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.6), blurRadius: 34, spreadRadius: -14)],
                          padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                          child: Column(children: [
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 300),
                              opacity: expiree ? 0.25 : 1,
                              child: _Qr(charge: _invitation.charge),
                            ),
                            const SizedBox(height: 14),
                            Text(_invitation.code,
                                style: mono(19, couleur: expiree ? Couleurs.tertiaire : Couleurs.texte, espacement: 1.5)),
                            const SizedBox(height: 5),
                            if (expiree)
                              TextButton(
                                onPressed: _renouveler,
                                style: TextButton.styleFrom(foregroundColor: Couleurs.cyan),
                                child: Text('Code expiré · en créer un autre', style: texte(13, graisse: 600, couleur: Couleurs.cyan)),
                              )
                            else
                              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                const Icone(Ico.horloge, couleur: Couleurs.secondaire, taille: 13, trait: 2),
                                const SizedBox(width: 6),
                                Text('Expire dans $mm:$ss', style: texte(12.5, couleur: Couleurs.secondaire)),
                              ]),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        const _Etapes(),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 14),
                  BoutonContour(libelle: "Partager l'invitation", ico: Ico.partage, hauteur: 52, onTap: expiree ? _renouveler : _partager),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le QR, 176 dp, avec ses coins de visée et la maison au centre.
class _Qr extends StatelessWidget {
  const _Qr({required this.charge});
  final String charge;

  @override
  Widget build(BuildContext context) => CustomPaint(
        foregroundPainter: Coins(),
        child: Container(
          width: 176,
          height: 176,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Couleurs.bloc,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Couleurs.separateur),
          ),
          child: Stack(alignment: Alignment.center, children: [
            QrImageView(
              data: charge,
              padding: EdgeInsets.zero,
              errorCorrectionLevel: QrErrorCorrectLevel.H,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFFE6FDFF)),
              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFFCFF8FF)),
            ),
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF0A1219),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Couleurs.cyan, width: 1.2),
              ),
              child: const Icone(Ico.maison, taille: 17, trait: 2),
            ),
          ]),
        ),
      );
}

class _Etapes extends StatelessWidget {
  const _Etapes();

  @override
  Widget build(BuildContext context) {
    const etapes = [
      ('Installer CyberSas', 'Sur le nouvel appareil'),
      ('Scanner ou saisir le code', 'Le nouvel appareil crée sa propre clé'),
      ("Signature sur le téléphone de l'admin", "Après vérification de l'empreinte"),
    ];
    return Carte(
      fond: const Color(0xC70C1117),
      child: Column(children: [
        for (var i = 0; i < etapes.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: i < etapes.length - 1 ? const Border(bottom: BorderSide(color: Couleurs.separateur)) : null,
            ),
            child: Row(children: [
              _Pastille(n: i + 1, etat: i == 0 ? 2 : (i == 1 ? 1 : 0)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(etapes[i].$1, style: texte(14, graisse: 500, couleur: i == 2 ? Couleurs.secondaire : Couleurs.texte)),
                  const SizedBox(height: 2),
                  Text(etapes[i].$2, style: texte(12, couleur: Couleurs.tertiaire)),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// 2 : fait ; 1 : en cours ; 0 : à venir.
class _Pastille extends StatelessWidget {
  const _Pastille({required this.n, required this.etat});
  final int n;
  final int etat;

  @override
  Widget build(BuildContext context) {
    if (etat == 2) {
      return Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Couleurs.cyan, Couleurs.bleu]),
          boxShadow: [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.7), blurRadius: 12, spreadRadius: -2)],
        ),
        child: const Icone(Ico.coche, couleur: Couleurs.fond, taille: 14, trait: 2.4),
      );
    }
    final actif = etat == 1;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: actif ? Couleurs.cyan.withValues(alpha: 0.6) : Couleurs.bordure),
        boxShadow: actif ? [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.7), blurRadius: 12, spreadRadius: -3)] : null,
      ),
      child: Text('$n', style: texte(12, graisse: 600, couleur: actif ? Couleurs.cyan : Couleurs.tertiaire)),
    );
  }
}
