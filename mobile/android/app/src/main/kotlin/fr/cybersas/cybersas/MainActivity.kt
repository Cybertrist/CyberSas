package fr.cybersas.cybersas

import android.content.Intent
import android.net.VpnService
import android.view.WindowManager
import fr.cybersas.pont.Pont
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

// FlutterFragmentActivity : l'invite biométrique d'Android (local_auth) en
// a besoin pour s'afficher.
class MainActivity : FlutterFragmentActivity() {
    // Les appels réseau du moteur (inscription, désinscription) ne doivent
    // jamais tourner sur le fil de l'interface.
    private val travail = Executors.newSingleThreadExecutor()
    private var enAttente: MethodChannel.Result? = null
    private var canalMoteur: MethodChannel? = null

    // Le lien d'invitation (cybersas://rejoindre?...) qui a ouvert l'appli.
    private fun lien(intent: Intent?): String? =
        intent?.data?.takeIf { it.scheme == "cybersas" }?.toString()

    companion object {
        private const val AUTORISATION_VPN = 42
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messager = flutterEngine.dartExecutor.binaryMessenger
        // « Masquer l'écran » : pas de capture, et un aperçu vide dans les
        // applis récentes.
        MethodChannel(messager, "fr.cybersas/ecran").setMethodCallHandler { appel, reponse ->
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

        // Le moteur du tunnel (pont/ en Go).
        val canal = MethodChannel(messager, "fr.cybersas/moteur")
        canalMoteur = canal
        canal.setMethodCallHandler { appel, reponse ->
            val dossier = TunnelService.dossier(this)
            when (appel.method) {
                "inscription" -> reponse.success(Pont.inscription(dossier.path))
                "lien" -> reponse.success(lien(intent))
                // Le nom donné au téléphone dans ses réglages, sinon son modèle.
                "nomAppareil" -> reponse.success(
                    android.provider.Settings.Global.getString(contentResolver, android.provider.Settings.Global.DEVICE_NAME)
                        ?.takeIf { it.isNotBlank() } ?: android.os.Build.MODEL
                )
                "etat" -> reponse.success(Pont.etat())
                "rejoindre" -> {
                    val serveur = appel.argument<String>("serveur") ?: ""
                    val verrou = appel.argument<String>("verrou") ?: ""
                    val cle = appel.argument<String>("cle") ?: ""
                    val jeton = appel.argument<String>("jeton") ?: ""
                    // Sans nom choisi, celui du modèle : « SM-F966B ».
                    val nom = (appel.argument<String>("nom") ?: "").ifEmpty { android.os.Build.MODEL }
                    val autorite = appel.argument<String>("autorite") ?: ""
                    enArriere(reponse) {
                        Pont.rejoindre(dossier.path, serveur, verrou, cle, jeton, nom, autorite)
                    }
                }
                "demarrer" -> {
                    // La première fois, Android demande à l'utilisateur
                    // d'autoriser le VPN.
                    val demande = VpnService.prepare(this)
                    if (demande == null) {
                        lancerService()
                        reponse.success(true)
                    } else {
                        enAttente = reponse
                        @Suppress("DEPRECATION")
                        startActivityForResult(demande, AUTORISATION_VPN)
                    }
                }
                "libeller" -> {
                    val cle = appel.argument<String>("cle") ?: ""
                    val libelle = appel.argument<String>("libelle") ?: ""
                    enArriere(reponse) { Pont.libeller(dossier.path, cle, libelle); null }
                }
                // Admin : les appareils, la clé du verrou, les signatures.
                "appareils" -> enArriere(reponse) { Pont.appareils(dossier.path) }
                // L'état du réseau par l'API, quand le tunnel est coupé.
                "reseau" -> enArriere(reponse) { Pont.reseau(dossier.path) }
                "coffrePresent" -> reponse.success(Coffre.present(this))
                // Juste après l'empreinte : la clé collée est vérifiée, puis rangée.
                "coffreRanger" -> {
                    val graine = appel.argument<String>("graine") ?: ""
                    enArriere(reponse) {
                        val empreinte = Pont.verifierVerrou(dossier.path, graine)
                        Coffre.ranger(this, graine)
                        empreinte
                    }
                }
                "coffreEffacer" -> { Coffre.effacer(this); reponse.success(null) }
                // Juste après l'empreinte : la clé sort du coffre et va droit au
                // moteur, sans passer par Flutter.
                "signer" -> {
                    val cles = appel.argument<String>("cles") ?: ""
                    enArriere(reponse) { Pont.signer(dossier.path, Coffre.lire(this), cles) }
                }
                "retirer" -> {
                    val cle = appel.argument<String>("cle") ?: ""
                    enArriere(reponse) { Pont.retirer(dossier.path, cle); null }
                }
                "arreter" -> {
                    startService(Intent(this, TunnelService::class.java).setAction(TunnelService.ARRET))
                    reponse.success(null)
                }
                "quitter" -> {
                    startService(Intent(this, TunnelService::class.java).setAction(TunnelService.ARRET))
                    enArriere(reponse) {
                        Pont.quitter(dossier.path)
                        Coffre.effacer(this)
                        null
                    }
                }
                else -> reponse.notImplemented()
            }
        }
    }

    // Un lien ouvert pendant que l'appli tourne déjà.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        lien(intent)?.let { canalMoteur?.invokeMethod("lien", it) }
    }

    private fun lancerService() {
        startService(Intent(this, TunnelService::class.java))
    }

    @Deprecated("startActivityForResult suffit ici : une seule demande possible à la fois")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != AUTORISATION_VPN) return
        val r = enAttente ?: return
        enAttente = null
        if (resultCode == RESULT_OK) {
            lancerService()
            r.success(true)
        } else {
            r.success(false)
        }
    }

    // Exécute [bloc] hors du fil de l'interface, et rend son résultat (ou
    // son erreur) à Flutter sur le fil de l'interface.
    private fun enArriere(reponse: MethodChannel.Result, bloc: () -> Any?) {
        travail.execute {
            try {
                val r = bloc()
                runOnUiThread { reponse.success(r) }
            } catch (e: Exception) {
                runOnUiThread { reponse.error("moteur", e.message ?: e.toString(), null) }
            }
        }
    }
}
