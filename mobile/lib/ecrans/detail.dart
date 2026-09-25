import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../composants.dart';
import '../donnees.dart';
import '../etat.dart';
import '../icones.dart';
import '../securite.dart';
import '../theme.dart';

/// Le détail d'un appareil, en plein écran (téléphone, écran extérieur).
class EcranDetail extends StatelessWidget {
  const EcranDetail({super.key, required this.adresse});

  /// L'adresse, pas le nom : le nom peut changer pendant qu'on regarde.
  final String adresse;

  @override
  Widget build(BuildContext context) {
    final a = EtatReseau.of(context).parAdresse(adresse);
    return Scaffold(
      body: Fond(
        centre: const Alignment(-0.5, -0.68),
        etendue: const Size(0.7, 0.24),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Align(alignment: Alignment.centerLeft, child: BoutonRetour('Appareils')),
              const SizedBox(height: 14),
              Expanded(
                child: SansDefilement(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    _Identite(a: a),
                    const SizedBox(height: 14),
                    _Grille(a: a, complete: false),
                    const SizedBox(height: 14),
                    _CarteCertificat(a: a),
                  ]),
                ),
              ),
              if (a.ports.isNotEmpty) ...[const SizedBox(height: 14), _BoutonOuvrir(a: a)],
              if (EtatReseau.of(context).peutRetirer(a)) ...[
                const SizedBox(height: 10),
                _BoutonRetirer(a: a, apres: () => Navigator.pop(context)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

enum Disposition { colonne, deuxColonnes }

/// Le détail à côté de la liste, sur le Fold déplié.
class PanneauDetail extends StatelessWidget {
  const PanneauDetail({super.key, required this.a, required this.disposition});
  final Appareil a;
  final Disposition disposition;

  @override
  Widget build(BuildContext context) {
    final fil = Row(children: [
      const Etiquette('Appareils / '),
      Flexible(child: Etiquette(a.nomAffiche, couleur: Couleurs.texte)),
    ]);
    final bouton = a.ports.isNotEmpty ? _BoutonOuvrir(a: a) : null;
    final retirer = EtatReseau.of(context).peutRetirer(a) ? _BoutonRetirer(a: a) : null;
    // Rien n'est étiré pour remplir la hauteur : le panneau défile si le
    // contenu ne tient pas, au lieu d'écraser la carte du certificat.
    final Widget corps = switch (disposition) {
      Disposition.colonne => SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            fil,
            const SizedBox(height: 14),
            _Identite(a: a, grand: true),
            const SizedBox(height: 14),
            _Grille(a: a, complete: false),
            const SizedBox(height: 12),
            _CarteCertificat(a: a),
            if (bouton != null) ...[const SizedBox(height: 12), bouton],
            if (retirer != null) ...[const SizedBox(height: 10), retirer],
          ]),
        ),
      Disposition.deuxColonnes => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              fil,
              const SizedBox(height: 14),
              _Identite(a: a, compact: true),
              const SizedBox(height: 12),
              _Grille(a: a, complete: false, avecNom: false),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _CarteCertificat(a: a, compact: true),
              if (bouton != null) ...[const SizedBox(height: 12), bouton],
              if (retirer != null) ...[const SizedBox(height: 10), retirer],
            ]),
          ),
        ]),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      layoutBuilder: (actuel, anciens) => Stack(alignment: Alignment.topCenter, children: [...anciens, ?actuel]),
      child: Container(
        key: ValueKey(a.adresse),
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: Bords.reflet,
          boxShadow: haloCarte(Couleurs.cyan, 0.35),
        ),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(23),
            gradient: const RadialGradient(
              center: Alignment(-0.6, -1),
              radius: 1.3,
              colors: [Color(0xF00A1A24), Color(0xF0070C12)],
            ),
          ),
          child: corps,
        ),
      ),
    );
  }
}

class _Identite extends StatelessWidget {
  const _Identite({required this.a, this.grand = false, this.compact = false});
  final Appareil a;
  final bool grand;

  /// Pour le panneau du Fold déplié en portrait : plus petit.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final r = EtatReseau.of(context);
    final admin = a.proprietaire == 'admin';
    final t = compact ? 46.0 : (grand ? 56.0 : 60.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        // L'icône de son type : un téléphone, un poste, une maison…
        CaseIcone(a.type.ico, couleur: a.couleur, etat: a.enLigne ? EtatIcone.enLigne : EtatIcone.horsLigne, taille: t),
        SizedBox(width: compact ? 13 : (grand ? 16 : 18)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: a.enLigne ? Couleurs.vert : Couleurs.tertiaire,
                  boxShadow: a.enLigne ? const [BoxShadow(color: Couleurs.vert, blurRadius: 8)] : null,
                ),
              ),
              const SizedBox(width: 7),
              Text(a.enLigne ? 'EN LIGNE · ' : 'HORS LIGNE · ',
                  style: etiquette(couleur: a.enLigne ? Couleurs.vert : Couleurs.etiquette, espacement: 0.12)),
              Text((admin ? 'admin' : a.proprietaire).toUpperCase(), style: etiquette(couleur: Couleurs.texte, espacement: 0.12)),
            ]),
            const SizedBox(height: 7),
            Row(children: [
              // Un nom long rapetisse au lieu d'être coupé.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(a.nomAffiche, style: titre(compact ? 22 : (grand ? 28 : 30)), maxLines: 1),
                ),
              ),
              if (r.peutRenommer(a)) ...[
                const SizedBox(width: 6),
                Semantics(
                  button: true,
                  label: 'Renommer',
                  child: InkResponse(
                    onTap: () => renommerAppareil(context, a),
                    radius: 22,
                    child: const Padding(padding: EdgeInsets.all(6), child: Icone(Ico.crayon, couleur: Couleurs.secondaire, taille: 18)),
                  ),
                ),
              ],
            ]),
            SizedBox(height: compact ? 4 : (grand ? 9 : 7)),
            Text(a.adresse, style: mono(compact ? 12.5 : 14, graisse: 400, couleur: Couleurs.secondaire)),
          ]),
        ),
      ]),
    );
  }
}

class _Case extends StatelessWidget {
  const _Case(this.titre, this.contenu);
  final String titre;
  final Widget contenu;

  @override
  Widget build(BuildContext context) => Carte(
        rayon: 16,
        padding: const EdgeInsets.fromLTRB(15, 12, 15, 13),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Etiquette(titre),
          const SizedBox(height: 8),
          contenu,
        ]),
      );
}

class _Grille extends StatelessWidget {
  const _Grille({required this.a, required this.complete, this.avecNom = true});
  final Appareil a;
  final bool complete;
  final bool avecNom;

  @override
  Widget build(BuildContext context) {
    final admin = a.proprietaire == 'admin';
    Widget paire(Widget g, Widget d) => IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: g),
            const SizedBox(width: 10),
            Expanded(child: d),
          ]),
        );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (avecNom) ...[
        _Case(
          'Nom',
          Text.rich(
            TextSpan(children: [
              TextSpan(text: a.nomAffiche, style: mono(14.5, graisse: 400)),
              // Accolé au nom court, le nom DNS serait faux : seulement quand
              // le nom est complet (machines, démo).
              if (a.nomAffiche == a.nom) TextSpan(text: '.sas.internal', style: mono(14.5, graisse: 400, couleur: Couleurs.cyan)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 10),
      ],
      paire(
        _Case('Adresse', Text(a.adresse, style: mono(14.5, graisse: 400))),
        _Case(
          'Ports ouverts',
          a.ports.isEmpty
              ? Text('aucun', style: texte(14, couleur: Couleurs.tertiaire))
              : Wrap(spacing: 4, runSpacing: 4, children: [for (final p in a.ports) PucePort(p)]),
        ),
      ),
      if (complete) ...[
        const SizedBox(height: 10),
        paire(
          _Case('Propriétaire',
              Text(admin ? 'Admin' : a.proprietaire[0].toUpperCase() + a.proprietaire.substring(1),
                  style: texte(14.5, graisse: 600))),
          _Case('Type', Text(a.type.libelle, style: texte(14.5))),
        ),
      ],
    ]);
  }
}

class _CarteCertificat extends StatelessWidget {
  const _CarteCertificat({required this.a, this.compact = false});
  final Appareil a;

  /// Pour le panneau du Fold déplié en portrait : sans sous-titre, plus
  /// serré.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = a.certificat;
    final maintenant = DateTime.now();
    final date = '${c.fin.day.toString().padLeft(2, '0')}/${c.fin.month.toString().padLeft(2, '0')}/${c.fin.year}';
    final jours = c.joursRestants(maintenant);
    final enfants = <Widget>[
      Row(children: [
        const Icone(Ico.bouclier, couleur: Couleurs.vert, taille: 26, lueur: true),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Certificat signé', style: texte(15.5, graisse: 600)),
            if (!compact) ...[
              const SizedBox(height: 2),
              Text("par la clé de l'admin · verrou vérifié",
                  style: texte(12.5, couleur: Couleurs.secondaire), maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
            ],
          ]),
        ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text("Valable jusqu'au", style: texte(14, couleur: Couleurs.secondaire)),
          const Spacer(),
          Text(date, style: mono(15, graisse: 400)),
        ]),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, k) => Container(
            height: 4,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(color: Couleurs.separateur, borderRadius: BorderRadius.circular(2)),
            child: Container(
              width: k.maxWidth * c.progression(maintenant),
              decoration: BoxDecoration(
                gradient: Couleurs.degrade,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.6), blurRadius: 8)],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('$jours jour${jours > 1 ? 's' : ''} restant${jours > 1 ? 's' : ''}', style: texte(12.5, couleur: Couleurs.secondaire)),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Etiquette('Empreinte'),
        const SizedBox(height: 8),
        Empreinte(c.empreinte, hauteur: compact ? 30 : 36),
      ]),
    ];
    return Bordee(
      bordure: Bords.reflet,
      fond: const Color(0xED090F16),
      rayon: 20,
      halo: haloCarte(),
      padding: EdgeInsets.all(compact ? 13 : 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [enfants[0], SizedBox(height: compact ? 10 : 14), enfants[1], SizedBox(height: compact ? 10 : 14), enfants[2]],
      ),
    );
  }
}

class _BoutonOuvrir extends StatelessWidget {
  const _BoutonOuvrir({required this.a});
  final Appareil a;

  @override
  Widget build(BuildContext context) => BoutonContour(
        libelle: 'Ouvrir dans le navigateur',
        ico: Ico.globe,
        hauteur: 52,
        onTap: () async {
          var ok = false;
          try {
            ok = await launchUrl(Uri.parse('https://${a.nomInterne}'), mode: LaunchMode.externalApplication);
          } on Exception {
            ok = false;
          }
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impossible d\'ouvrir ${a.nomInterne}')));
          }
        },
      );
}

/// Renommer un appareil. Le suffixe du propriétaire (« -tristan ») reste
/// fixe : on ne change que ce qui le précède.
Future<void> renommerAppareil(BuildContext context, Appareil a) async {
  final r = EtatReseau.of(context);
  // Sur le vrai réseau, on change le nom affiché, tel quel ; dans la démo,
  // le nom lui-même, suffixe du propriétaire compris.
  final libre = r.reel;
  final champ = TextEditingController(text: libre ? a.nomAffiche : a.prefixe);
  String? erreur;
  var enCours = false;
  await showDialog<void>(
    context: context,
    barrierColor: const Color(0xA8020407),
    builder: (context) => StatefulBuilder(
      builder: (context, maj) {
        Future<void> valider() async {
          if (enCours) return;
          maj(() => enCours = true);
          final e = await r.renommer(r.parAdresse(a.adresse), champ.text);
          if (!context.mounted) return;
          if (e == null) {
            Navigator.pop(context);
          } else {
            maj(() {
              erreur = e;
              enCours = false;
            });
          }
        }

        final apercu = nomPropre(champ.text) + a.suffixe;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Bordee(
              bordure: Bords.reflet,
              fond: const Color(0xFF0A1119),
              rayon: 24,
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Renommer', style: texte(20, graisse: 600, espacement: -0.4)),
                const SizedBox(height: 6),
                Text(
                  libre
                      ? 'Le nom que tu verras partout, majuscules et espaces compris.'
                      : a.suffixe.isEmpty
                      ? 'Lettres, chiffres et tirets : le nom sert aussi d\'adresse sur le réseau.'
                      : 'Le suffixe « ${a.suffixe} » reste : il dit à qui est l\'appareil.',
                  style: texte(13.5, couleur: Couleurs.secondaire, hauteur: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: champ,
                  autofocus: true,
                  maxLength: libre ? 40 : 30,
                  textCapitalization: libre ? TextCapitalization.words : TextCapitalization.none,
                  style: libre ? texte(16, graisse: 500) : mono(16, graisse: 400),
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => maj(() => erreur = null),
                  onSubmitted: (_) => valider(),
                  decoration: InputDecoration(
                    counterText: '',
                    suffixText: libre || a.suffixe.isEmpty ? null : a.suffixe,
                    suffixStyle: mono(16, graisse: 400, couleur: Couleurs.tertiaire),
                    filled: true,
                    fillColor: Couleurs.bloc,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Couleurs.bordure)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Couleurs.cyan)),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  erreur ?? (libre ? 'Ton nom sur le réseau ne change pas.' : '$apercu.sas.internal'),
                  style: erreur != null ? texte(13, couleur: Couleurs.rougeClair) : mono(12.5, graisse: 400, couleur: Couleurs.etiquette),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(child: BoutonFantome(libelle: 'Annuler', onTap: () => Navigator.pop(context))),
                  const SizedBox(width: 10),
                  Expanded(child: BoutonFantome(libelle: 'Renommer', couleur: Couleurs.cyan, bord: Couleurs.cyan.withValues(alpha: 0.5), onTap: valider)),
                ]),
              ]),
            ),
          ),
        );
      },
    ),
  );
  // La fenêtre s'efface encore un instant avec le champ : on attend.
  Future<void>.delayed(const Duration(milliseconds: 400), champ.dispose);
}

/// « Retirer du réseau », pour l'admin : une confirmation, puis l'empreinte.
/// Le serveur oublie l'appareil. Signé, et la clé du verrou sur ce
/// téléphone : « Révoquer », qui le bannit aussi pour de bon (la liste de
/// révocation est signée par le verrou, et chaque appareil la vérifie).
class _BoutonRetirer extends StatelessWidget {
  const _BoutonRetirer({required this.a, this.apres});
  final Appareil a;
  final VoidCallback? apres;

  Future<void> _retirer(BuildContext context) async {
    final r = EtatReseau.of(context);
    final messager = ScaffoldMessenger.of(context);
    final revoquer = r.peutRevoquer(a);
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
              Text('${revoquer ? 'Révoquer' : 'Retirer'} ${a.nomAffiche} ?', style: texte(20, graisse: 600, espacement: -0.4)),
              const SizedBox(height: 8),
              Text(
                revoquer
                    ? "Sa clé est bannie pour de bon, signée par le verrou : aucun appareil ne l'acceptera plus, même si le serveur était piraté. Pour revenir, il lui faudra une nouvelle invitation, avec une nouvelle clé."
                    : "Il quitte le réseau tout de suite : plus aucun appareil ne le voit. Pour revenir, il devra refaire une demande et être signé à nouveau.",
                style: texte(14, couleur: Couleurs.secondaire, hauteur: 1.4),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: BoutonFantome(libelle: 'Annuler', onTap: () => Navigator.pop(context, false))),
                const SizedBox(width: 10),
                Expanded(
                  child: BoutonFantome(
                    libelle: revoquer ? 'Révoquer' : 'Retirer',
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
    if (oui != true) return;
    if (await confirmerIdentite('${revoquer ? 'Révoquer' : 'Retirer'} ${a.nomAffiche}') != Identite.confirmee) return;
    final e = revoquer ? await r.revoquerAppareil(a) : await r.retirerAppareil(a);
    messager.showSnackBar(SnackBar(content: Text(e ?? '${a.nomAffiche} ${revoquer ? 'révoqué' : 'retiré du réseau'}')));
    if (e == null) apres?.call();
  }

  @override
  Widget build(BuildContext context) => BoutonFantome(
        libelle: EtatReseau.of(context).peutRevoquer(a) ? 'Révoquer' : 'Retirer du réseau',
        couleur: Couleurs.rougeClair,
        bord: Couleurs.rouge.withValues(alpha: 0.4),
        onTap: () => _retirer(context),
      );
}
