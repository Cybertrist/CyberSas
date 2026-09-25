import 'package:flutter/material.dart';

import '../composants.dart';
import '../donnees.dart';
import '../etat.dart';
import '../icones.dart';
import '../securite.dart';
import '../theme.dart';
import 'detail.dart';

/// Le compte, cet appareil, la sécurité de l'appli, le réseau. Pas de
/// « VPN toujours actif » ni de démarrage automatique : le tunnel s'allume
/// et se coupe à la main, depuis l'accueil. Les demandes en attente sont
/// sur la page Appareils, pas ici.
class EcranReglages extends StatelessWidget {
  const EcranReglages({super.key});

  @override
  Widget build(BuildContext context) {
    final r = EtatReseau.of(context);
    final format = formatDe(context);
    final titre0 = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text('Réglages', style: titre(format == Format.compact ? 28 : 32)),
    );
    final compte = _Compte(r: r);
    final appareil = _CetAppareil(r: r);
    final securite = _Securite(r: r);
    final reseau = _Reseau(r: r);
    final quitter = _Quitter(r: r);
    const espace = SizedBox(height: 18);

    return switch (format) {
      Format.compact => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          children: [titre0, espace, compte, espace, appareil, espace, securite, espace, reseau, espace, quitter],
        ),
      Format.portrait => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 12),
              children: [titre0, espace, compte, espace, appareil, espace, securite, espace, reseau, espace, quitter],
            ),
          ),
        ),
      Format.paysage => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            titre0,
            espace,
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(children: [compte, espace, appareil, espace, quitter])),
              const SizedBox(width: 24),
              Expanded(child: Column(children: [securite, espace, reseau])),
            ]),
          ]),
        ),
    };
  }
}

class _Compte extends StatelessWidget {
  const _Compte({required this.r});
  final Reseau r;

  @override
  Widget build(BuildContext context) => Bordee(
        bordure: Bords.reflet,
        fond: const Color(0xED090F16),
        halo: haloCarte(),
        padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
        child: Row(children: [
          Avatar(lettre: r.compte[0], taille: 42, plein: true),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.compte, style: texte(16, graisse: 600)),
              const SizedBox(height: 2),
              Text('Connecté avec Google', style: texte(12.5, couleur: Couleurs.secondaire)),
            ]),
          ),
          if (r.admin) const Puce('ADMIN', couleur: Couleurs.texte, fond: false),
        ]),
      );
}

/// Ce qui identifie ce téléphone sur le réseau : son nom (qu'on peut
/// changer), son adresse, son certificat et l'empreinte de sa clé, celle
/// que l'admin compare avant de signer.
class _CetAppareil extends StatelessWidget {
  const _CetAppareil({required this.r});
  final Reseau r;

  @override
  Widget build(BuildContext context) {
    final moi = r.moi;
    final jours = moi.certificat.joursRestants(DateTime.now());
    return Groupe(titre: 'Cet appareil', enfants: [
      LigneReglage(
        ico: Ico.etiquette,
        libelle: 'Nom',
        valeur: moi.nom,
        fin: const Chevron(),
        onTap: () => renommerAppareil(context, moi),
        dense: true,
      ),
      LigneReglage(ico: Ico.repere, libelle: 'Adresse privée', valeur: moi.adresse, valeurMono: true, dense: true),
      LigneReglage(
        ico: Ico.bouclier,
        couleurIco: jours > 14 ? Couleurs.vert : Couleurs.rouge,
        libelle: 'Certificat',
        valeur: 'encore $jours j',
        dense: true,
      ),
      LigneReglage(
        ico: Ico.cle,
        libelle: 'Ma clé',
        valeur: moi.certificat.empreinte.join('-'),
        valeurMono: true,
        separateur: false,
        dense: true,
      ),
    ]);
  }
}

class _Securite extends StatelessWidget {
  const _Securite({required this.r});
  final Reseau r;

  Future<void> _verrou(BuildContext context, bool v) async {
    final messager = ScaffoldMessenger.of(context);
    // On vérifie que le doigt (ou le code du téléphone) passe avant
    // d'activer : sinon on s'enfermerait dehors.
    if (v) {
      final ok = await confirmerIdentite("Verrouiller CyberSas avec l'empreinte", biometrieSeule: false);
      if (ok == Identite.impossible) {
        messager.showSnackBar(const SnackBar(content: Text('Aucune empreinte ni code sur ce téléphone.')));
      }
      if (ok != Identite.confirmee) return;
    }
    await r.reglerVerrou(v);
  }

  Future<void> _ecran(bool v) async {
    await r.reglerEcran(v);
    await masquerEcran(v);
  }

  @override
  Widget build(BuildContext context) => Groupe(titre: 'Sécurité', enfants: [
        LigneReglage(
          ico: Ico.empreinte,
          libelle: "Verrouiller l'appli",
          sousTitre: "Empreinte demandée à l'ouverture",
          fin: Interrupteur(valeur: r.verrouAppli, onChanged: (v) => _verrou(context, v), largeur: 44, hauteur: 26, libelle: "Verrouiller l'appli"),
          dense: true,
        ),
        LigneReglage(
          ico: Ico.oeil,
          libelle: "Masquer l'écran",
          sousTitre: 'Pas de capture, aperçu vide dans les applis récentes',
          fin: Interrupteur(valeur: r.ecranMasque, onChanged: _ecran, largeur: 44, hauteur: 26, libelle: "Masquer l'écran"),
          separateur: r.admin,
          dense: true,
        ),
        if (r.admin)
          const LigneReglage(
            ico: Ico.puce,
            libelle: 'Clé du verrou',
            sousTitre: "Elle signe les nouveaux appareils. Elle est gardée dans la puce du téléphone et ne sert qu'après ton empreinte.",
            separateur: false,
            dense: true,
          ),
      ]);
}

class _Reseau extends StatelessWidget {
  const _Reseau({required this.r});
  final Reseau r;

  @override
  Widget build(BuildContext context) => Groupe(titre: 'Réseau', enfants: [
        LigneReglage(ico: Ico.serveurLigne, libelle: 'Serveur', valeur: r.serveur, dense: true),
        LigneReglage(ico: Ico.globe, libelle: 'Plage', valeur: r.plage, valeurMono: true, dense: true),
        LigneReglage(ico: Ico.cadenas, libelle: 'Chiffrement', valeur: r.protocole, dense: true),
        const LigneReglage(ico: Ico.info, libelle: 'Version', valeur: versionAppli, valeurMono: true, separateur: false, dense: true),
      ]);
}

class _Quitter extends StatelessWidget {
  const _Quitter({required this.r});
  final Reseau r;

  @override
  Widget build(BuildContext context) => Carte(
        child: LigneReglage(
          ico: Ico.quitter,
          couleurIco: Couleurs.rouge,
          couleurTexte: Couleurs.rougeClair,
          libelle: 'Quitter le réseau',
          separateur: false,
          onTap: () => _quitter(context),
        ),
      );

  Future<void> _quitter(BuildContext context) async {
    final oui = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xA8020407),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Bordee(
            bordure: Bords.accent(Couleurs.rouge),
            fond: const Color(0xFF0A1119),
            rayon: 24,
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Quitter le réseau ?', style: texte(20, graisse: 600, espacement: -0.4)),
              const SizedBox(height: 8),
              Text(
                "Cet appareil oublie sa clé et son certificat. Pour revenir, l'admin devra le signer à nouveau.",
                style: texte(14, couleur: Couleurs.secondaire, hauteur: 1.4),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: BoutonFantome(libelle: 'Annuler', onTap: () => Navigator.pop(context, false))),
                const SizedBox(width: 10),
                Expanded(
                  child: BoutonFantome(
                    libelle: 'Quitter',
                    couleur: Couleurs.rougeClair,
                    bord: Couleurs.rouge.withValues(alpha: 0.45),
                    onTap: () => Navigator.pop(context, true),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (oui == true) r.quitter();
  }
}
