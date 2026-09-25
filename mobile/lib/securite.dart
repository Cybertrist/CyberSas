// L'empreinte digitale et le masquage de l'écran, par les outils du
// système : l'invite biométrique d'Android et FLAG_SECURE.
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

enum Identite {
  /// Le doigt est reconnu.
  confirmee,

  /// L'utilisateur a fermé l'invite.
  annulee,

  /// Pas de capteur, ou aucune empreinte enregistrée dans le téléphone.
  impossible,
}

final _auth = LocalAuthentication();

/// Ouvre l'invite biométrique d'Android. [biometrieSeule] : refuse le code
/// du téléphone, il faut le doigt (c'est le cas pour signer).
Future<Identite> confirmerIdentite(String raison, {bool biometrieSeule = true}) async {
  try {
    final ok = await _auth.authenticate(
      localizedReason: raison,
      biometricOnly: biometrieSeule,
      authMessages: const [AndroidAuthMessages(signInTitle: 'CyberSas', cancelButton: 'Annuler')],
    );
    return ok ? Identite.confirmee : Identite.annulee;
  } on LocalAuthException catch (e) {
    return switch (e.code) {
      LocalAuthExceptionCode.userCanceled ||
      LocalAuthExceptionCode.systemCanceled ||
      LocalAuthExceptionCode.timeout ||
      LocalAuthExceptionCode.authInProgress =>
        Identite.annulee,
      _ => Identite.impossible,
    };
  } on MissingPluginException {
    return Identite.impossible;
  } on PlatformException {
    return Identite.impossible;
  }
}

const _ecran = MethodChannel('fr.cybersas/ecran');

/// Bloque les captures et vide l'aperçu dans les applis récentes.
Future<void> masquerEcran(bool oui) async {
  try {
    await _ecran.invokeMethod<void>('masquer', oui);
  } on MissingPluginException {
    // Tests, ou plateforme sans ce canal : rien à masquer.
  }
}
