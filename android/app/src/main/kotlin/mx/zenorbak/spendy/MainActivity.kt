package mx.zenorbak.spendy

import android.os.SystemClock
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

// local_auth (incremento 7) necesita FlutterFragmentActivity.
class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // AUD-04: reloj monótono para el bloqueo del PIN.
        MethodChannel(messenger, "mx.zenorbak.spendy/clock").setMethodCallHandler { call, result ->
            if (call.method == "elapsedRealtime") {
                result.success(SystemClock.elapsedRealtime())
            } else {
                result.notImplemented()
            }
        }
        // AUD-14: llave del Keystore que Android invalida si se agrega o
        // quita una huella o un rostro.
        MethodChannel(messenger, "mx.zenorbak.spendy/biometric_key").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "create" -> { createKey(); result.success(true) }
                    "isValid" -> result.success(isKeyValid())
                    "delete" -> { deleteKey(); result.success(true) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("biometric_key", e.javaClass.simpleName, null)
            }
        }
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun createKey() {
        deleteKey()
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
            .build()
        KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).run {
            init(spec)
            generateKey()
        }
    }

    /** `false` si la llave no existe o Android la invalidó por un cambio de biometría. */
    private fun isKeyValid(): Boolean {
        val key = keyStore().getKey(KEY_ALIAS, null) as? SecretKey ?: return false
        return try {
            Cipher.getInstance("AES/GCM/NoPadding").init(Cipher.ENCRYPT_MODE, key)
            true
        } catch (e: KeyPermanentlyInvalidatedException) {
            false
        }
    }

    private fun deleteKey() {
        val store = keyStore()
        if (store.containsAlias(KEY_ALIAS)) store.deleteEntry(KEY_ALIAS)
    }

    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "spendy_biometric"
    }
}
