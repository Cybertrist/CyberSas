package fr.cybersas.cybersas

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity : l'invite biométrique d'Android (local_auth) en
// a besoin pour s'afficher.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // « Masquer l'écran » : pas de capture, et un aperçu vide dans les
        // applis récentes.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fr.cybersas/ecran")
            .setMethodCallHandler { appel, reponse ->
                when (appel.method) {
                    "masquer" -> {
                        if (appel.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        reponse.success(null)
                    }
                    else -> reponse.notImplemented()
                }
            }
    }
}
