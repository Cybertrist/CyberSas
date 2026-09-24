import 'package:flutter/widgets.dart';

import 'donnees.dart';

/// Donne l'état du réseau à tous les écrans, et les reconstruit quand il
/// change.
class EtatReseau extends InheritedNotifier<Reseau> {
  const EtatReseau({super.key, required Reseau reseau, required super.child})
      : super(notifier: reseau);

  static Reseau of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EtatReseau>()!.notifier!;
}
