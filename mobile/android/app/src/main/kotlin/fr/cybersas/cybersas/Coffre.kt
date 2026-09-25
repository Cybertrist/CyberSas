package fr.cybersas.cybersas

import android.content.Context
import android.content.pm.PackageManager
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

// Le coffre de la clé du verrou, sur le téléphone de l'admin.
//
// La clé du verrou (Ed25519) est chiffrée en AES-GCM par une clé du
// Keystore d'Android, gardée par la puce StrongBox quand le téléphone en a
// une. Cette clé ne sert que dans les 10 secondes qui suivent une empreinte
// reconnue (setUserAuthenticationParameters) : sans le doigt de l'admin, le
// fichier chiffré ne vaut rien, même copié, même sur un téléphone déverrouillé.
//
// La clé déchiffrée ne passe jamais par Flutter : Kotlin la lit et la donne
// directement au moteur Go, qui signe puis l'oublie.
object Coffre {
    private const val ALIAS = "cybersas-verrou"
    private const val DELAI = 10 // secondes après l'empreinte

    private fun fichier(c: Context) = File(TunnelService.dossier(c), "verrou.chiffre")

    fun present(c: Context): Boolean = fichier(c).exists()

    private fun cleKeystore(c: Context, creer: Boolean): SecretKey? {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        if (!creer) return null
        fun generer(strongBox: Boolean): SecretKey {
            val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(true)
                .setUserAuthenticationParameters(DELAI, KeyProperties.AUTH_BIOMETRIC_STRONG)
                // Une nouvelle empreinte ajoutée au téléphone invalide la clé.
                .setInvalidatedByBiometricEnrollment(true)
                .setIsStrongBoxBacked(strongBox)
                .build()
            return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
                init(spec)
                generateKey()
            }
        }
        val strongBox = c.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
        return try {
            generer(strongBox)
        } catch (e: StrongBoxUnavailableException) {
            generer(false)
        }
    }

    // À appeler juste après une empreinte reconnue.
    fun ranger(c: Context, graine: String) {
        effacer(c)
        val chiffreur = Cipher.getInstance("AES/GCM/NoPadding")
        chiffreur.init(Cipher.ENCRYPT_MODE, cleKeystore(c, creer = true))
        val chiffre = chiffreur.doFinal(graine.trim().toByteArray())
        fichier(c).parentFile?.mkdirs()
        fichier(c).writeText(
            Base64.encodeToString(chiffreur.iv, Base64.NO_WRAP) + "." + Base64.encodeToString(chiffre, Base64.NO_WRAP)
        )
    }

    // À appeler juste après une empreinte reconnue. Rend la graine en clair.
    fun lire(c: Context): String {
        val (iv, chiffre) = fichier(c).readText().split(".").map { Base64.decode(it, Base64.NO_WRAP) }
        val dechiffreur = Cipher.getInstance("AES/GCM/NoPadding")
        dechiffreur.init(
            Cipher.DECRYPT_MODE,
            cleKeystore(c, creer = false) ?: throw IllegalStateException("clé du coffre absente"),
            GCMParameterSpec(128, iv)
        )
        return String(dechiffreur.doFinal(chiffre))
    }

    fun effacer(c: Context) {
        fichier(c).delete()
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(ALIAS)
    }
}
