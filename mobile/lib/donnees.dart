// Les données affichées par l'appli. Pour l'instant, un réseau d'exemple
// qui reprend le labo (maison, serveur, poste) : le moteur Go et l'API du
// serveur viendront les remplacer, sans toucher aux écrans.
import 'package:flutter/foundation.dart';

enum TypeAppareil { serveur, maison, telephone, ordinateur, tablette, inconnu }

class Appareil {
  const Appareil({
    required this.nom,
    required this.adresse,
    required this.type,
    required this.proprietaire,
    this.enLigne = false,
    this.moi = false,
    this.refuse = false,
    this.ports = const [],
    this.empreinte = const ['zNYM', 'GYdG', 'paJ5'],
    this.expire,
  });

  final String nom;
  final String adresse;
  final TypeAppareil type;
  final String proprietaire;
  final bool enLigne;
  final bool moi;
  final bool refuse;
  final List<int> ports;
  final List<String> empreinte;
  final DateTime? expire;

  String get nomInterne => '$nom.sas.internal';
}

class Demande {
  const Demande({
    required this.nom,
    required this.compte,
    required this.type,
    required this.empreinte,
  });

  final String nom;
  final String compte;
  final TypeAppareil type;
  final List<String> empreinte;
}

/// L'état de l'appli, partagé par tous les écrans.
class Reseau extends ChangeNotifier {
  bool connecte = true;
  final debutConnexion = DateTime.now().subtract(const Duration(hours: 2, minutes: 14));
  final serveur = 'vpn.exemple.fr';
  final plage = '10.77.0.0/24';
  final monAdresse = '10.77.0.18';
  final monNom = 'fold8-tristan';
  final compte = 'Tristan';
  final admin = true;

  bool toujoursActif = true;
  bool auDemarrage = true;
  bool dnsPrive = true;

  final appareils = <Appareil>[
    Appareil(
      nom: 'serveur',
      adresse: '10.77.0.1',
      type: TypeAppareil.serveur,
      proprietaire: 'admin',
      enLigne: true,
      ports: const [53],
      expire: DateTime(2026, 12, 23),
    ),
    Appareil(
      nom: 'maison',
      adresse: '10.77.0.2',
      type: TypeAppareil.maison,
      proprietaire: 'admin',
      enLigne: true,
      ports: const [80, 443],
      expire: DateTime(2026, 12, 23),
    ),
    Appareil(
      nom: 'fold8-tristan',
      adresse: '10.77.0.18',
      type: TypeAppareil.telephone,
      proprietaire: 'tristan',
      enLigne: true,
      moi: true,
      empreinte: const ['uO8I', 'L02v', '/TRr'],
      expire: DateTime(2026, 12, 23),
    ),
    Appareil(
      nom: 'pc-tristan',
      adresse: '10.77.0.19',
      type: TypeAppareil.ordinateur,
      proprietaire: 'tristan',
      empreinte: const ['k3Pw', 'Q9sA', 'x1Mf'],
      expire: DateTime(2026, 12, 23),
    ),
    const Appareil(
      nom: 'appareil inconnu',
      adresse: '',
      type: TypeAppareil.inconnu,
      proprietaire: '',
      refuse: true,
    ),
  ];

  final demandes = <Demande>[
    const Demande(
      nom: 'laptop-lea',
      compte: 'lea@exemple.fr',
      type: TypeAppareil.ordinateur,
      empreinte: ['Qx7K', 't8Zm', 'VvLp'],
    ),
    const Demande(
      nom: 'tab-tristan',
      compte: 'tristan@exemple.fr',
      type: TypeAppareil.tablette,
      empreinte: ['Rc4N', 'p2Bo', 'Ke3s'],
    ),
  ];

  List<Appareil> get acceptes => appareils.where((a) => !a.refuse).toList();
  List<Appareil> get refuses => appareils.where((a) => a.refuse).toList();
  int get enLigne => acceptes.where((a) => a.enLigne).length;
  int get horsLigne => acceptes.where((a) => !a.enLigne).length;

  Appareil appareil(String nom) => appareils.firstWhere((a) => a.nom == nom);

  void basculer(bool v) {
    connecte = v;
    notifyListeners();
  }

  void reglage(void Function() changement) {
    changement();
    notifyListeners();
  }

  void traiter(Demande d) {
    demandes.remove(d);
    notifyListeners();
  }
}
