// Le moteur du tunnel, écrit en Go (pont/ à la racine du dépôt) et tenu
// par TunnelService côté Android. Ici, seulement les appels et la lecture
// des liens d'invitation.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

const _canal = MethodChannel('fr.cybersas/moteur');

/// Une erreur du moteur, prête à afficher.
class ErreurMoteur implements Exception {
  ErreurMoteur(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract final class Moteur {
  /// L'inscription de cet appareil, ou null s'il n'a rejoint aucun réseau.
  static Future<Map<String, dynamic>?> inscription() async {
    final s = await _canal.invokeMethod<String>('inscription') ?? '';
    return s.isEmpty ? null : jsonDecode(s) as Map<String, dynamic>;
  }

  /// Rejoint le réseau de l'[invitation]. Rend l'inscription.
  static Future<Map<String, dynamic>> rejoindre(Invitation i, {String nom = ''}) async {
    try {
      final s = await _canal.invokeMethod<String>('rejoindre', {
        'serveur': i.serveur,
        'verrou': i.verrou,
        'cle': i.cle,
        'jeton': '',
        'nom': nom,
        'autorite': i.autorite,
      });
      return jsonDecode(s!) as Map<String, dynamic>;
    } on PlatformException catch (e) {
      throw ErreurMoteur(e.message ?? e.code);
    }
  }

  /// Ouvre le tunnel. La première fois, Android demande l'autorisation :
  /// false si elle est refusée.
  static Future<bool> demarrer() async => await _canal.invokeMethod<bool>('demarrer') ?? false;

  static Future<void> arreter() => _canal.invokeMethod<void>('arreter');

  /// L'état du tunnel et du réseau (voir pont.Vue).
  static Future<Map<String, dynamic>> etat() async {
    final s = await _canal.invokeMethod<String>('etat') ?? '{}';
    return jsonDecode(s) as Map<String, dynamic>;
  }

  static Future<void> quitter() async {
    try {
      await _canal.invokeMethod<void>('quitter');
    } on PlatformException catch (e) {
      throw ErreurMoteur(e.message ?? e.code);
    }
  }

  static Future<T?> _appel<T>(String methode, [Map<String, dynamic>? args]) async {
    try {
      return await _canal.invokeMethod<T>(methode, args);
    } on PlatformException catch (e) {
      throw ErreurMoteur(e.message ?? e.code);
    }
  }

  /// Le nom affiché d'un appareil : le sien si [cle] est vide.
  static Future<void> libeller(String cle, String libelle) => _appel<void>('libeller', {'cle': cle, 'libelle': libelle});

  /// L'état du réseau lu sur l'API, sans tunnel (même forme que [etat]).
  static Future<Map<String, dynamic>> reseau() async =>
      jsonDecode(await _appel<String>('reseau') ?? '{}') as Map<String, dynamic>;

  /// Admin : tous les appareils du serveur, signés ou non (pont.Fiche).
  static Future<List<Map<String, dynamic>>> appareils() async =>
      (jsonDecode(await _appel<String>('appareils') ?? '[]') as List).cast<Map<String, dynamic>>();

  /// La clé du verrou est dans le coffre de ce téléphone.
  static Future<bool> verrouPresent() async {
    try {
      return await _canal.invokeMethod<bool>('coffrePresent') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Range la clé du verrou dans le coffre. Juste après l'empreinte.
  static Future<String> rangerVerrou(String graine) async => await _appel<String>('coffreRanger', {'graine': graine}) ?? '';

  static Future<void> effacerVerrou() => _appel<void>('coffreEffacer');

  /// Signe ces appareils avec la clé du coffre. Juste après l'empreinte.
  static Future<int> signer(String cles) async => await _appel<int>('signer', {'cles': cles}) ?? 0;

  /// Admin : révoque ces appareils avec la clé du verrou (sortie du coffre
  /// après l'empreinte). Rend la version de la nouvelle liste.
  static Future<int> revoquer(String cles) async => await _appel<int>('revoquer', {'cles': cles}) ?? 0;

  /// Admin : un lien d'invitation pour un membre de l'équipe.
  static Future<String> inviter(String utilisateur, int minutes) async =>
      await _appel<String>('inviter', {'utilisateur': utilisateur, 'minutes': minutes}) ?? '';

  /// Admin : retire un appareil du serveur.
  static Future<void> retirer(String cle) => _appel<void>('retirer', {'cle': cle});

  /// Le nom du téléphone dans ses réglages (« Galaxy Z Fold8 »), sinon
  /// son modèle.
  static Future<String> nomAppareil() async {
    try {
      return await _canal.invokeMethod<String>('nomAppareil') ?? '';
    } on MissingPluginException {
      return '';
    }
  }

  /// Le lien d'invitation qui a ouvert l'appli, s'il y en a un.
  static Future<Invitation?> lienInitial() async {
    try {
      final s = await _canal.invokeMethod<String>('lien');
      return s == null ? null : Invitation.lire(s);
    } on MissingPluginException {
      return null;
    }
  }

  /// Les liens d'invitation ouverts pendant que l'appli tourne.
  static final liens = StreamController<Invitation>.broadcast();

  static void ecouter() {
    _canal.setMethodCallHandler((appel) async {
      if (appel.method == 'lien' && appel.arguments is String) {
        final i = Invitation.lire(appel.arguments as String);
        if (i != null) liens.add(i);
      }
    });
  }
}

/// Une invitation : ce que « sas.sh invitation » donne, sous forme de lien
///   cybersas://rejoindre?serveur=…&cle=…&verrou=…[&autorite=…]
class Invitation {
  const Invitation({required this.serveur, required this.cle, this.verrou = '', this.autorite = ''});

  /// L'adresse de l'API, https://vpn.exemple.fr.
  final String serveur;

  /// La clé d'inscription, à usage unique.
  final String cle;

  /// La clé publique du verrou : l'appareil la retient dès le départ.
  final String verrou;

  /// L'autorité du labo, en PEM ; vide avec un vrai certificat.
  final String autorite;

  static Invitation? lire(String texte) {
    final u = Uri.tryParse(texte.trim());
    if (u == null || u.scheme != 'cybersas' || u.host != 'rejoindre') return null;
    final p = u.queryParameters;
    final serveur = p['serveur'] ?? '';
    final cle = p['cle'] ?? '';
    if (!serveur.startsWith('https://') || cle.isEmpty) return null;
    var autorite = '';
    if ((p['autorite'] ?? '').isNotEmpty) {
      try {
        autorite = utf8.decode(base64.decode(p['autorite']!));
      } on FormatException {
        return null;
      }
    }
    return Invitation(serveur: serveur, cle: cle, verrou: p['verrou'] ?? '', autorite: autorite);
  }

  /// « vpn.exemple.fr ».
  String get hote => Uri.parse(serveur).host;
}
