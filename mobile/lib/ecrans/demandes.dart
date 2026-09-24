import 'package:flutter/material.dart';

import '../composants.dart';
import '../dessins.dart';
import '../donnees.dart';
import '../etat.dart';
import '../theme.dart';

/// Côté admin : les appareils qui attendent leur signature. La clé du
/// verrou vit dans le coffre du téléphone et chaque signature demande
/// l'empreinte digitale.
class EcranDemandes extends StatelessWidget {
  const EcranDemandes({super.key});

  @override
  Widget build(BuildContext context) {
    final r = EtatReseau.of(context);
    return Scaffold(
      body: FondReseau(
        child: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            final large = c.maxWidth >= 600;
            final cartes = [for (final d in r.demandes) _CarteDemande(d: d)];
            return ListView(
              padding: EdgeInsets.fromLTRB(large ? 28 : 20, 10, large ? 28 : 20, 24),
              children: [
                const Row(children: [
                  Expanded(child: BoutonRetour('Réglages')),
                  Pastille('ADMIN'),
                ]),
                const SizedBox(height: 16),
                Text('SIGNATURE · ${r.demandes.length} EN ATTENTE', style: etiquette(couleur: Couleurs.cyan)),
                const SizedBox(height: 4),
                Text('Demandes en attente', style: texte(29, graisse: 700)),
                const SizedBox(height: 16),
                Carte(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Couleurs.cyan.withValues(alpha: 0.08),
                        border: Border.all(color: Couleurs.cyan.withValues(alpha: 0.45)),
                      ),
                      child: const Icon(Icons.memory_rounded, size: 20, color: Couleurs.cyan),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Clé du verrou · protégée par le téléphone', style: texte(14.5, graisse: 600)),
                        Text('Keystore StrongBox · empreinte à chaque signature',
                            style: texte(12.5, couleur: Couleurs.secondaire)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                if (r.demandes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(children: [
                      const Icon(Icons.task_alt_rounded, size: 40, color: Couleurs.cyan),
                      const SizedBox(height: 10),
                      Text('Aucune demande en attente', style: texte(16, graisse: 500)),
                    ]),
                  )
                else if (large)
                  Wrap(spacing: 14, runSpacing: 14, children: [
                    for (final w in cartes) SizedBox(width: (c.maxWidth - 56 - 14) / 2, child: w),
                  ])
                else
                  for (final w in cartes) Padding(padding: const EdgeInsets.only(bottom: 12), child: w),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _CarteDemande extends StatelessWidget {
  const _CarteDemande({required this.d});
  final Demande d;

  Future<void> _signer(BuildContext context, Reseau r) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeuilleBiometrie(d: d),
    );
    if (ok == true && context.mounted) {
      r.traiter(d);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${d.nom} est signé : son certificat part vers le serveur')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = EtatReseau.of(context);
    return Carte(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconeAppareil(d.type, enLigne: false, taille: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.nom, style: texte(16, graisse: 600)),
              Text(d.compte, style: mono(12)),
            ]),
          ),
          Pastille(libelleDe(d.type)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Text('EMPREINTE DE LA CLÉ', style: etiquette()),
          const Spacer(),
          Text('à comparer sur l\'appareil', style: texte(12, couleur: Couleurs.secondaire)),
        ]),
        const SizedBox(height: 8),
        Empreinte(d.empreinte),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                r.traiter(d);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${d.nom} est refusé')));
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Couleurs.rouge,
                side: BorderSide(color: Couleurs.rouge.withValues(alpha: 0.55)),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: texte(15, graisse: 600),
              ),
              child: const Text('Refuser'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: () => _signer(context, r),
              icon: const Icon(Icons.fingerprint_rounded, size: 20),
              label: const Text('Signer'),
              style: FilledButton.styleFrom(
                backgroundColor: Couleurs.cyan,
                foregroundColor: Couleurs.fond,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: texte(15, graisse: 700),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// La confirmation par empreinte digitale. Pour l'instant simulée : un
/// appui sur le capteur dessiné vaut accord. La vraie passera par le
/// Keystore d'Android, qui refuse de signer sans l'empreinte.
class _FeuilleBiometrie extends StatelessWidget {
  const _FeuilleBiometrie({required this.d});
  final Demande d;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
        decoration: BoxDecoration(
          color: Couleurs.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Couleurs.cyan.withValues(alpha: 0.35)),
          boxShadow: [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.12), blurRadius: 30)],
        ),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Couleurs.bordure, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 18),
            Text('Confirmer avec ton empreinte', style: texte(20, graisse: 700)),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(style: texte(13.5, couleur: Couleurs.secondaire), children: [
                const TextSpan(text: 'Signer '),
                TextSpan(text: d.nom, style: texte(13.5, graisse: 700)),
                const TextSpan(text: ' avec la clé du verrou'),
              ]),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(true),
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Couleurs.cyan.withValues(alpha: 0.08),
                  border: Border.all(color: Couleurs.cyan.withValues(alpha: 0.7), width: 1.5),
                  boxShadow: [BoxShadow(color: Couleurs.cyan.withValues(alpha: 0.35), blurRadius: 28)],
                ),
                child: const Icon(Icons.fingerprint_rounded, size: 52, color: Couleurs.cyan),
              ),
            ),
            const SizedBox(height: 18),
            Text('EMPREINTE · ${d.empreinte.join('-')}', style: etiquette()),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.lock_outline_rounded, size: 14, color: Couleurs.discret),
              const SizedBox(width: 6),
              Text('La clé ne quitte jamais la puce StrongBox', style: texte(12.5, couleur: Couleurs.secondaire)),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Couleurs.texte,
                  side: const BorderSide(color: Couleurs.bordure),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Annuler'),
              ),
            ),
          ]),
        ),
      );
}
