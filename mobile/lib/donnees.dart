// Les données affichées par l'appli : le vrai réseau, tenu par le moteur Go
// (Reseau.reel), ou, pour la démo et les captures, un réseau d'exemple
// qui reprend le labo (serveur, maison, téléphone, poste).
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'icones.dart';
import 'moteur.dart';
import 'theme.dart';

enum TypeAppareil {
  serveur('Serveur', Ico.serveur),
  maison('Serveur maison', Ico.maison),
  telephone('Téléphone', Ico.telephone),
  pc('Ordinateur', Ico.pc),
  portable('Portable', Ico.portable),
  tablette('Tablette', Ico.tablette);

  const TypeAppareil(this.libelle, this.ico);
  final String libelle;
  final Ico ico;
}

class Certificat {
  const Certificat({required this.debut, required this.fin, required this.empreinte});
  final DateTime debut;
  final DateTime fin;

  /// Les 12 premiers caractères du hash de la clé publique, en base64url,
  /// affichés en 3 blocs de 4.
  final List<String> empreinte;

  int joursRestants(DateTime maintenant) => fin.difference(maintenant).inDays.clamp(0, 99999);

  double progression(DateTime maintenant) {
    final total = fin.difference(debut).inSeconds;
    if (total <= 0) return 0;
    return (fin.difference(maintenant).inSeconds / total).clamp(0.0, 1.0);
  }
}

class Appareil {
  const Appareil({
    required this.nom,
    required this.adresse,
    required this.type,
    required this.proprietaire,
    required this.certificat,
    this.enLigne = false,
    this.moi = false,
    this.ports = const [],
    this.signe = true,
    this.raison = '',
  });

  /// Son certificat est valide pour ce téléphone. Sinon, [raison] dit
  /// pourquoi il est écarté (pas encore signé, expiré, révoqué).
  final bool signe;
  final String raison;

  final String nom;
  final String adresse;
  final TypeAppareil type;

  /// « admin » ou le prénom du propriétaire.
  final String proprietaire;
  final Certificat certificat;
  final bool enLigne;
  final bool moi;
  final List<int> ports;

  String get nomInterne => '$nom.sas.internal';

  /// Un appareil personnel porte toujours le nom de son propriétaire en
  /// suffixe (« fold8-tristan ») : il ne peut pas se faire passer pour
  /// « serveur ». Les machines de l'admin n'en ont pas. Même règle que
  /// NomPersonnel côté serveur.
  String get suffixe => proprietaire == 'admin' ? '' : '-$proprietaire';

  /// La partie du nom qu'on peut changer.
  String get prefixe => suffixe.isNotEmpty && nom.endsWith(suffixe) ? nom.substring(0, nom.length - suffixe.length) : nom;

  Appareil renomme(String nouveau) => Appareil(
        nom: nouveau,
        adresse: adresse,
        type: type,
        proprietaire: proprietaire,
        certificat: certificat,
        enLigne: enLigne,
        moi: moi,
        ports: ports,
        signe: signe,
        raison: raison,
      );

  /// Un appareil tel que le moteur le décrit (pont.Pair).
  factory Appareil.duMoteur(Map<String, dynamic> j) {
    final etiquette = j['etiquette'] as String? ?? '';
    final systeme = j['systeme'] as String? ?? '';
    final serveur = j['serveur'] == true;
    final type = switch ((serveur, etiquette, systeme)) {
      (true, _, _) => TypeAppareil.serveur,
      (_, final e, _) when e.isNotEmpty => TypeAppareil.maison,
      (_, _, 'android' || 'ios') => TypeAppareil.telephone,
      _ => TypeAppareil.pc,
    };
    final email = j['proprietaire'] as String? ?? '';
    final expire = DateTime.tryParse(j['expire'] as String? ?? '');
    return Appareil(
      nom: j['nom'] as String? ?? '?',
      adresse: j['adresse'] as String? ?? '',
      type: type,
      // Les machines (serveur, maison) sont celles de l'admin.
      proprietaire: serveur || etiquette.isNotEmpty ? 'admin' : prenom(email).toLowerCase(),
      enLigne: j['en_ligne'] == true,
      moi: j['moi'] == true,
      signe: j['signe'] != false,
      raison: j['raison'] as String? ?? '',
      certificat: Certificat(
        // Le verrou signe pour 90 jours par défaut.
        debut: (expire ?? DateTime.now()).subtract(const Duration(days: 90)),
        fin: expire ?? DateTime.now(),
        empreinte: (j['empreinte'] as String? ?? '').split('-'),
      ),
    );
  }
  String get fin => '.${adresse.split('.').last}';

  /// La couleur de l'appareil : cyan en ligne, gris hors ligne. Une seule
  /// couleur pour tous, c'est le type qui les distingue.
  Color get couleur => enLigne ? Couleurs.cyan : Couleurs.tertiaire;
}

class Demande {
  const Demande({required this.nom, required this.compte, required this.type, required this.empreinte});

  final String nom;
  final String compte;
  final TypeAppareil type;
  final List<String> empreinte;

  /// « lea.martin@gmail.com » → « lea » : le prénom sert de suffixe au nom.
  String get proprietaire => nomPropre(compte.split('@').first.split('.').first);
}

class CodeInvitation {
  CodeInvitation(this.serveur) : code = _code(), expire = DateTime.now().add(const Duration(minutes: 10));

  final String serveur;
  final String code;
  final DateTime expire;

  String get charge => 'cybersas://invitation?serveur=$serveur&code=$code';

  // Sans 0/O ni 1/I : le code se recopie à la main sans hésiter.
  static String _code() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    String bloc() => List.generate(4, (_) => alphabet[r.nextInt(alphabet.length)]).join();
    return 'SAS-${bloc()}-${bloc()}';
  }
}

/// L'état de l'appli, partagé par tous les écrans.
class Reseau extends ChangeNotifier {
  /// Le réseau d'exemple (démo, captures d'écran).
  Reseau({this.inscrit = false}) : reel = false;

  /// Le vrai réseau, tenu par le moteur. Vide jusqu'à [charger].
  Reseau.reel()
      : reel = true,
        inscrit = false,
        connecte = false {
    appareils.clear();
    demandes.clear();
  }

  /// Vrai : les données viennent du moteur (pont/ en Go), pas de l'exemple.
  final bool reel;

  /// Faux tant que l'appareil n'a pas rejoint de réseau : l'appli s'ouvre
  /// alors sur l'écran de connexion.
  bool inscrit;

  /// Le tunnel est ouvert (l'interrupteur).
  bool connecte = true;

  /// Une session est établie avec le serveur. Le tunnel peut être ouvert
  /// sans elle, le temps de la poignée de main ou si le serveur est
  /// injoignable.
  bool serveurJoint = true;

  /// La dernière erreur du moteur, à afficher.
  String erreur = '';

  DateTime debutConnexion = DateTime.now().subtract(const Duration(hours: 2, minutes: 14));
  String serveur = 'vpn.exemple.fr';
  String cleVerrou = '';
  String plage = '10.77.0.0/24';
  final protocole = 'Noise IK';
  String compte = 'Tristan';
  bool admin = true;

  /// Cet appareil, d'après son inscription, avant que le moteur ait décrit
  /// le réseau.
  Appareil? _moiInscrit;

  /// L'appareil choisi dans la liste, quand la liste et le détail sont
  /// côte à côte (Fold déplié).
  String selection = 'maison';

  static final _certificat = Certificat(
    debut: DateTime(2026, 8, 25),
    fin: DateTime(2026, 12, 23),
    empreinte: const ['zNYM', 'GYdG', 'paJ5'],
  );

  final appareils = <Appareil>[
    Appareil(
      nom: 'serveur',
      adresse: '10.77.0.1',
      type: TypeAppareil.serveur,
      proprietaire: 'admin',
      enLigne: true,
      certificat: Certificat(debut: DateTime(2026, 8, 25), fin: DateTime(2026, 12, 23), empreinte: const ['v8Qe', 'Lm2T', 'x0Rw']),
    ),
    Appareil(
      nom: 'maison',
      adresse: '10.77.0.2',
      type: TypeAppareil.maison,
      proprietaire: 'admin',
      enLigne: true,
      ports: const [80, 443],
      certificat: _certificat,
    ),
    Appareil(
      nom: 'fold8-tristan',
      adresse: '10.77.0.18',
      type: TypeAppareil.telephone,
      proprietaire: 'tristan',
      enLigne: true,
      moi: true,
      certificat: Certificat(debut: DateTime(2026, 8, 25), fin: DateTime(2026, 12, 23), empreinte: const ['uO8I', 'L02v', '_TRr']),
    ),
    Appareil(
      nom: 'pc-tristan',
      adresse: '10.77.0.19',
      type: TypeAppareil.pc,
      proprietaire: 'tristan',
      certificat: Certificat(debut: DateTime(2026, 8, 25), fin: DateTime(2026, 12, 23), empreinte: const ['k3Pw', 'Q9sA', 'x1Mf']),
    ),
  ];

  final demandes = <Demande>[
    const Demande(nom: 'laptop-lea', compte: 'lea.martin@gmail.com', type: TypeAppareil.portable, empreinte: ['Qm7X', 'tR2k', '9vLp']),
    const Demande(nom: 'tab-tristan', compte: 'tristan@gmail.com', type: TypeAppareil.tablette, empreinte: ['Hc4W', 'pZ8n', 'Ke3s']),
  ];

  Appareil get moi => appareils.firstWhere((a) => a.moi, orElse: () => _moiInscrit ?? appareils.first);
  int get enLigne => appareils.where((a) => a.enLigne).length;
  int get horsLigne => appareils.length - enLigne;

  /// Les appareils rangés par propriétaire, l'admin d'abord.
  Map<String, List<Appareil>> get parProprietaire {
    final m = <String, List<Appareil>>{};
    for (final a in appareils) {
      (m[a.proprietaire] ??= []).add(a);
    }
    final cles = m.keys.toList()..sort((a, b) => a == 'admin' ? -1 : (b == 'admin' ? 1 : a.compareTo(b)));
    return {for (final k in cles) k: m[k]!};
  }

  Appareil appareil(String nom) => appareils.firstWhere((a) => a.nom == nom, orElse: () => appareils.isEmpty ? moi : appareils.first);
  Appareil parAdresse(String adresse) => appareils.firstWhere((a) => a.adresse == adresse, orElse: () => appareils.isEmpty ? moi : appareils.first);

  /// Vrai pendant qu'on allume ou coupe le tunnel : l'interrupteur ne
  /// répond plus tant que l'animation (et demain le moteur) n'a pas fini.
  bool enTransition = false;
  Timer? _transition;

  /// Le temps que met le tunnel de l'accueil à s'allumer ou s'éteindre.
  static const dureeTransition = Duration(milliseconds: 3200);

  void basculer(bool v) {
    if (v == connecte || enTransition) return;
    if (reel) {
      _basculerReel(v);
      return;
    }
    connecte = v;
    if (v) debutConnexion = DateTime.now();
    _attendreAnimation();
    notifyListeners();
  }

  void _attendreAnimation() {
    enTransition = true;
    _transition?.cancel();
    _transition = Timer(dureeTransition, () {
      enTransition = false;
      notifyListeners();
    });
  }

  Future<void> _basculerReel(bool v) async {
    erreur = '';
    if (v) {
      // La première fois, Android demande d'autoriser le VPN.
      if (!await Moteur.demarrer()) {
        erreur = 'Autorisation VPN refusée';
        notifyListeners();
        return;
      }
      debutConnexion = DateTime.now();
      serveurJoint = false;
    } else {
      await Moteur.arreter();
    }
    connecte = v;
    _attendreAnimation();
    notifyListeners();
  }

  // ─── Le vrai réseau ───

  Timer? _suivi;

  /// Lit l'inscription : sans elle, l'appli s'ouvre sur la connexion.
  /// Puis suit l'état du moteur toutes les deux secondes.
  Future<void> charger() async {
    final i = await Moteur.inscription();
    if (i == null) {
      inscrit = false;
      notifyListeners();
      return;
    }
    _adopterInscription(i);
    await _lireEtat();
    _suivi?.cancel();
    _suivi = Timer.periodic(const Duration(seconds: 2), (_) => _lireEtat());
    notifyListeners();
  }

  void _adopterInscription(Map<String, dynamic> i) {
    inscrit = true;
    serveur = Uri.tryParse(i['serveur'] as String? ?? '')?.host ?? '';
    plage = i['reseau'] as String? ?? plage;
    compte = prenom(i['proprietaire'] as String? ?? '');
    admin = i['groupe'] == 'admins';
    cleVerrou = i['verrou'] as String? ?? '';
    _moiInscrit = Appareil(
      nom: i['nom'] as String? ?? '',
      adresse: i['adresse'] as String? ?? '',
      type: TypeAppareil.telephone,
      proprietaire: compte.toLowerCase(),
      moi: true,
      enLigne: true,
      signe: false,
      certificat: Certificat(debut: DateTime.now(), fin: DateTime.now(), empreinte: (i['empreinte'] as String? ?? '').split('-')),
    );
  }

  Future<void> _lireEtat() async {
    final Map<String, dynamic> e;
    try {
      e = await Moteur.etat();
    } on Exception {
      return;
    }
    final enMarche = e['en_marche'] == true;
    // Pendant qu'on change d'état, l'interrupteur a la main.
    if (!enTransition) connecte = enMarche;
    serveurJoint = e['connecte'] == true;
    erreur = e['erreur'] as String? ?? '';
    final pairs = (e['pairs'] as List? ?? []).cast<Map<String, dynamic>>();
    if (pairs.isNotEmpty) {
      appareils
        ..clear()
        ..addAll(pairs.map(Appareil.duMoteur));
      if (!appareils.any((a) => a.nom == selection)) selection = appareils.first.nom;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _transition?.cancel();
    _suivi?.cancel();
    super.dispose();
  }

  void choisir(String nom) {
    selection = nom;
    notifyListeners();
  }

  /// Rejoint le réseau de l'invitation. Rend l'erreur à afficher, ou null.
  Future<String?> rejoindre(Invitation i, {String nom = ''}) async {
    if (!reel) {
      serveur = i.hote;
      cleVerrou = i.verrou;
      inscrit = true;
      notifyListeners();
      return null;
    }
    try {
      await Moteur.rejoindre(i, nom: nom);
    } on ErreurMoteur catch (e) {
      return e.message;
    }
    await charger();
    return null;
  }

  Future<void> quitter() async {
    if (reel) {
      _suivi?.cancel();
      await Moteur.quitter();
      appareils.clear();
      connecte = false;
    }
    inscrit = false;
    notifyListeners();
  }

  /// Refusée : la demande disparaît, rien n'entre dans le réseau.
  void traiter(Demande d) {
    demandes.remove(d);
    notifyListeners();
  }

  /// Signée : l'appareil reçoit la première adresse libre et un certificat
  /// de 120 jours, et rejoint la liste de son propriétaire. Il reste hors
  /// ligne tant qu'il ne s'est pas connecté.
  void signer(Demande d) {
    demandes.remove(d);
    final prises = appareils.map((a) => a.adresse).toSet();
    var n = 2;
    while (prises.contains('10.77.0.$n')) {
      n++;
    }
    final maintenant = DateTime.now();
    appareils.add(Appareil(
      nom: d.nom,
      adresse: '10.77.0.$n',
      type: d.type,
      proprietaire: d.proprietaire,
      certificat: Certificat(debut: maintenant, fin: maintenant.add(const Duration(days: 120)), empreinte: d.empreinte),
    ));
    notifyListeners();
  }

  /// L'admin renomme n'importe quel appareil, les autres seulement les
  /// leurs. Le nom n'est pas dans le certificat : pas besoin de resigner.
  // Le vrai serveur n'a pas encore de quoi renommer : seulement dans la démo.
  bool peutRenommer(Appareil a) => !reel && (admin || a.proprietaire == compte.toLowerCase());

  /// Renomme [a] en « [prefixe][suffixe] ». Rend l'erreur à afficher, ou
  /// null si c'est fait.
  String? renommer(Appareil a, String prefixe) {
    final nouveau = nomPropre(prefixe) + a.suffixe;
    if (nouveau == a.nom) return null;
    if (appareils.any((b) => b.nom == nouveau)) return '« $nouveau » est déjà pris';
    final i = appareils.indexOf(a);
    if (i < 0) return 'Appareil introuvable';
    appareils[i] = a.renomme(nouveau);
    if (selection == a.nom) selection = nouveau;
    notifyListeners();
    return null;
  }

  // ─── Réglages de l'appli, gardés sur le téléphone ───

  /// Demander l'empreinte à l'ouverture de l'appli.
  bool verrouAppli = false;

  /// Bloquer les captures et l'aperçu dans les applis récentes.
  bool ecranMasque = false;

  static const _cleVerrou = 'verrou_appli';
  static const _cleEcran = 'ecran_masque';

  Future<void> chargerReglages() async {
    final p = await SharedPreferences.getInstance();
    verrouAppli = p.getBool(_cleVerrou) ?? false;
    ecranMasque = p.getBool(_cleEcran) ?? false;
    notifyListeners();
  }

  Future<void> reglerVerrou(bool v) async {
    verrouAppli = v;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_cleVerrou, v);
  }

  Future<void> reglerEcran(bool v) async {
    ecranMasque = v;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_cleEcran, v);
  }
}

/// Minuscules, chiffres et tirets, 30 caractères au plus : le nom sert de
/// nom DNS. Même règle que NomPropre côté serveur.
String nomPropre(String s) {
  var n = s.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]+'), '-');
  n = n.replaceAll(RegExp(r'^-+|-+$'), '');
  if (n.length > 30) n = n.substring(0, 30).replaceAll(RegExp(r'-+$'), '');
  return n.isEmpty ? 'appareil' : n;
}

/// « 2 h 14 », « 12 min ».
String duree(Duration d) {
  if (d.inHours > 0) return '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')}';
  return '${d.inMinutes} min';
}

/// La version affichée dans « À propos » (même valeur que pubspec.yaml).
const versionAppli = '0.4.0';

/// « tristan.joncour@gmail.com » → « Tristan » : de quoi nommer quelqu'un
/// sans son nom complet.
String prenom(String email) {
  // Les chiffres de fin ne font pas partie du prénom : « tristan29 ».
  final p = email.split('@').first.split(RegExp(r'[._+-]')).first.replaceAll(RegExp(r'[0-9]+$'), '');
  if (p.isEmpty) return '';
  return p[0].toUpperCase() + p.substring(1).toLowerCase();
}
