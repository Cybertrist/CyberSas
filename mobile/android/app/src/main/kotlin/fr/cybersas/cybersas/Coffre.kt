package fr.cybersas.cybersas

import android.content.Context
import android.content.pm.PackageManager
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.util.Base64
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

// Le coffre de la clé du verrou, sur le téléphone de l'admin.
//
// La clé du verrou (Ed25519) est chiffrée en AES-GCM par une clé du
// Keystore d'Android, gardée par la puce StrongBox quand le téléphone en a
// une. Cette clé ne sert qu'à une seule opération, autorisée par une
// empreinte donnée pour elle (BiometricPrompt avec CryptoObject) : ni le
// déverrouillage du téléphone, ni une empreinte donnée pour autre chose
// ne l'ouvrent. Sans le doigt de l'admin, le fichier chiffré ne vaut rien,
// même copié, même sur un téléphone déverrouillé.
//
// La clé en clair ne passe par Flutter qu'une fois, à l'import (l'admin la
// colle dans l'appli). Ensuite, Kotlin la sort du coffre et la donne
// directement au moteur Go, qui signe puis l'oublie ; aucune copie ne
// remonte vers Flutter.
object Coffre {
    // Deux alias qui alternent : ranger une nouvelle clé se fait sous
    // l'alias libre, et l'ancien n'est effacé qu'une fois le nouveau fichier
    // en place. Un échec en cours de route (doigt retiré, appli tuée) laisse
    // l'ancienne clé intacte.
    private const val ALIAS = "cybersas-verrou"
    private const val ALIAS_BIS = "cybersas-verrou-bis"

    // Le message rendu quand une empreinte a été ajoutée au téléphone :
    // Android a détruit la clé du Keystore, le coffre ne s'ouvre plus.
    const val INVALIDE = "Une empreinte a été ajoutée au téléphone : range à nouveau la clé du verrou."

    // Le coffre ne peut plus s'ouvrir : il a été effacé, il faut ranger la
    // clé du verrou à nouveau.
    class Invalide(message: String) : Exception(message)

    private fun fichier(c: Context) = File(TunnelService.dossier(c), "verrou.chiffre")

    fun present(c: Context): Boolean = fichier(c).exists()

    private fun keystore() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    // Le contenu du fichier : « alias.iv.chiffré ». Les coffres rangés avant
    // l'alternance des alias n'ont que « iv.chiffré », sous ALIAS.
    private class Contenu(val alias: String, val iv: ByteArray, val chiffre: ByteArray)

    private fun lireFichier(c: Context): Contenu? {
        val f = fichier(c)
        if (!f.exists()) return null
        val parts = f.readText().trim().split(".")
        return when (parts.size) {
            2 -> Contenu(ALIAS, Base64.decode(parts[0], Base64.NO_WRAP), Base64.decode(parts[1], Base64.NO_WRAP))
            3 -> Contenu(parts[0], Base64.decode(parts[1], Base64.NO_WRAP), Base64.decode(parts[2], Base64.NO_WRAP))
            else -> null
        }
    }

    // Une clé neuve sous [alias], qui remplace celle qui y serait restée
    // d'un essai raté. Délai 0 : chaque usage demande sa propre empreinte,
    // donnée à travers un CryptoObject.
    private fun generer(c: Context, alias: String): SecretKey {
        keystore().deleteEntry(alias)
        fun generer(strongBox: Boolean): SecretKey {
            val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(true)
                .setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
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

    // Un chiffreur en attente d'empreinte, et l'alias de sa clé neuve.
    class Chiffreur(val cipher: Cipher, val alias: String)

    // Ranger, première moitié : un chiffreur sous une clé neuve, à faire
    // autoriser par l'empreinte (BiometricPrompt). L'ancienne clé, s'il y
    // en a une, reste en place.
    fun chiffreur(c: Context): Chiffreur {
        val actuel = runCatching { lireFichier(c)?.alias }.getOrNull()
        val alias = if (actuel == ALIAS) ALIAS_BIS else ALIAS
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, generer(c, alias)) }
        return Chiffreur(cipher, alias)
    }

    // Ranger, seconde moitié : [cipher] (celui de [chiffreur]) vient d'être
    // autorisé par l'empreinte. Le nouveau fichier remplace l'ancien d'un
    // coup (rename atomique), puis seulement l'ancienne clé du Keystore est
    // effacée.
    fun ranger(c: Context, chiffreur: Chiffreur, cipher: Cipher, graine: ByteArray) {
        val ancienAlias = if (chiffreur.alias == ALIAS) ALIAS_BIS else ALIAS
        val chiffre = cipher.doFinal(graine)
        val f = fichier(c)
        f.parentFile?.mkdirs()
        val provisoire = File(f.parentFile, f.name + ".neuf")
        provisoire.writeText(
            chiffreur.alias + "." + Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + "." +
                Base64.encodeToString(chiffre, Base64.NO_WRAP)
        )
        Files.move(provisoire.toPath(), f.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        runCatching { keystore().deleteEntry(ancienAlias) }
    }

    // L'empreinte n'a pas abouti (annulée, ratée) : la clé neuve ne sert à
    // rien, l'ancienne reste.
    fun abandonner(chiffreur: Chiffreur) {
        runCatching { keystore().deleteEntry(chiffreur.alias) }
    }

    // Lire, première moitié : le déchiffreur à faire autoriser par
    // l'empreinte, et le texte chiffré qu'il ouvrira. Une empreinte ajoutée
    // au téléphone depuis le rangement a détruit la clé : le coffre est
    // effacé et [Invalide] le dit.
    fun dechiffreur(c: Context): Pair<Cipher, ByteArray> {
        val contenu = lireFichier(c) ?: throw Invalide("La clé du verrou n'est pas sur ce téléphone.")
        val cle = keystore().getKey(contenu.alias, null) as? SecretKey
        if (cle == null) {
            effacer(c)
            throw Invalide(INVALIDE)
        }
        val d = Cipher.getInstance("AES/GCM/NoPadding")
        try {
            d.init(Cipher.DECRYPT_MODE, cle, GCMParameterSpec(128, contenu.iv))
        } catch (e: KeyPermanentlyInvalidatedException) {
            effacer(c)
            throw Invalide(INVALIDE)
        }
        return d to contenu.chiffre
    }

    // Lire, seconde moitié : [dechiffreur] vient d'être autorisé par
    // l'empreinte. Rend la graine en clair, à remettre à zéro dès qu'elle a
    // servi (Arrays.fill).
    fun lire(dechiffreur: Cipher, chiffre: ByteArray): ByteArray = dechiffreur.doFinal(chiffre)

    fun effacer(c: Context) {
        fichier(c).delete()
        File(fichier(c).parentFile, fichier(c).name + ".neuf").delete()
        runCatching {
            val ks = keystore()
            ks.deleteEntry(ALIAS)
            ks.deleteEntry(ALIAS_BIS)
        }
    }
}
