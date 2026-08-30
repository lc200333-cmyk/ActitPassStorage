package com.lc200333cmyk.walletaps

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val channelName = "wallet_aps/spb_wallet"
    private val openRequestCode = 7401
    private val createRequestCode = 7402
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingCreateResult: MethodChannel.Result? = null
    private var walletChannel: MethodChannel? = null
    private var launchWalletConsumed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val privateDirectories = buildList {
            add(filesDir)
            add(cacheDir)
            add(noBackupFilesDir)
            add(codeCacheDir)
            externalCacheDir?.let(::add)
            getExternalFilesDirs(null).filterNotNull().forEach(::add)
        }
        privateDirectories.forEach { directory ->
            runCatching {
                directory.mkdirs()
                File(directory, ".nomedia").apply {
                    if (!exists()) createNewFile()
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        walletChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        walletChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickSpbWallet" -> pickSpbWallet(result)
                "getLaunchWallet" -> {
                    if (launchWalletConsumed) {
                        result.success(null)
                    } else {
                        launchWalletConsumed = true
                        result.success(walletFromViewIntent(intent))
                    }
                }
                "createSpbWalletDocument" -> {
                    val displayName = call.argument<String>("displayName") ?: "wallet.swl"
                    createSpbWalletDocument(displayName, result)
                }
                "copySpbWallet" -> {
                    val uri = call.argument<String>("uri")
                    val displayName = call.argument<String>("displayName")
                    if (uri == null) {
                        result.error("bad_args", "Missing uri", null)
                    } else {
                        copySpbWallet(Uri.parse(uri), displayName, result)
                    }
                }
                "writeSpbWallet" -> {
                    val uri = call.argument<String>("uri")
                    val localPath = call.argument<String>("localPath")
                    val expectedLength = call.argument<Number>("expectedLength")?.toLong()
                    val expectedSha256 = call.argument<String>("expectedSha256")
                    val expectedExistingLength =
                        call.argument<Number>("expectedExistingLength")?.toLong()
                    val expectedExistingSha256 = call.argument<String>("expectedExistingSha256")
                    if (uri == null || localPath == null) {
                        result.error("bad_args", "Missing uri or localPath", null)
                    } else {
                        writeSpbWallet(
                            uri,
                            localPath,
                            expectedLength,
                            expectedSha256,
                            expectedExistingLength,
                            expectedExistingSha256,
                            result
                        )
                    }
                }
                "getPendingSpbWalletRecovery" -> result.success(pendingRecovery())
                "restoreSpbWalletRecovery" -> restorePendingRecovery(result)
                "discardSpbWalletRecovery" -> {
                    clearRecovery()
                    result.success(true)
                }
                "openFile" -> {
                    val path = call.argument<String>("path")
                    val mimeType = call.argument<String>("mimeType") ?: "*/*"
                    if (path == null) {
                        result.error("bad_args", "Missing path", null)
                    } else {
                        openFile(path, mimeType, result)
                    }
                }
                "shareFile" -> {
                    val path = call.argument<String>("path")
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                    val title = call.argument<String>("title") ?: "Card.swl"
                    if (path == null) {
                        result.error("bad_args", "Missing path", null)
                    } else {
                        shareFile(path, mimeType, title, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun pickSpbWallet(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("busy", "SPB Wallet picker is already open", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(
            Intent.createChooser(intent, "Выберите файловый менеджер"),
            openRequestCode
        )
    }

    private fun createSpbWalletDocument(displayName: String, result: MethodChannel.Result) {
        if (pendingCreateResult != null) {
            result.error("busy", "SPB Wallet creator is already open", null)
            return
        }
        pendingCreateResult = result
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, displayName)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(
            Intent.createChooser(intent, "Выберите файловый менеджер для сохранения"),
            createRequestCode
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == createRequestCode) {
            val result = pendingCreateResult
            pendingCreateResult = null
            if (result == null) return
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                result.success(null)
                return
            }
            val uri = data.data!!
            val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            val persisted = persistUriPermission(uri, flags)
            val name = displayName(uri)
            result.success(mapOf(
                "uri" to uri.toString(),
                "displayName" to name,
                "displayPath" to displayPath(uri, name),
                "writable" to uriWritable(uri, flags),
                "persisted" to persisted
            ))
            return
        }
        if (requestCode != openRequestCode) return
        val result = pendingPickResult
        pendingPickResult = null
        if (result == null) return
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }
        val uri = data.data!!
        val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        val persisted = persistUriPermission(uri, flags)
        copySpbWallet(uri, null, result, uriWritable(uri, flags), persisted)
    }

    private fun persistUriPermission(uri: Uri, flags: Int): Boolean {
        return try {
            contentResolver.takePersistableUriPermission(uri, flags)
            true
        } catch (_: SecurityException) {
            false
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val wallet = walletFromViewIntent(intent) ?: return
        walletChannel?.invokeMethod("openWallet", wallet)
    }

    private fun walletFromViewIntent(intent: Intent?): Map<String, Any?>? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        return try {
            val name = displayName(uri)
            if (!name.lowercase().endsWith(".swl") &&
                intent.type != "application/x-spb-wallet" &&
                intent.type != "application/vnd.spb.wallet") {
                return null
            }
            val flags = intent.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            val persisted = persistUriPermission(uri, flags)
            copySpbWalletData(uri, name, uriWritable(uri, flags), persisted)
        } catch (_: Throwable) {
            null
        }
    }

    private fun uriWritable(uri: Uri, grantedFlags: Int = 0): Boolean {
        if (uri.scheme == "file") return true
        if (grantedFlags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0) return true
        return contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isWritePermission
        }
    }

    private fun copySpbWallet(
        uri: Uri,
        knownDisplayName: String?,
        result: MethodChannel.Result,
        writable: Boolean = uriWritable(uri),
        persisted: Boolean = contentResolver.persistedUriPermissions.any { it.uri == uri }
    ) {
        try {
            result.success(copySpbWalletData(uri, knownDisplayName, writable, persisted))
        } catch (error: Throwable) {
            result.error("copy_failed", error.message, null)
        }
    }

    private fun copySpbWalletData(
        uri: Uri,
        knownDisplayName: String? = null,
        writable: Boolean = uriWritable(uri),
        persisted: Boolean = contentResolver.persistedUriPermissions.any { it.uri == uri }
    ): Map<String, Any?> {
        val displayName = knownDisplayName?.takeIf { it.isNotBlank() } ?: displayName(uri)
        val local = File(cacheDir, "spbwallet_${System.currentTimeMillis()}_$displayName")
        contentResolver.openInputStream(uri).use { input ->
            FileOutputStream(local).use { output ->
                if (input == null) error("Cannot open selected SPB Wallet file")
                input.copyTo(output)
            }
        }
        val sourceLastModified = lastModified(uri)
        if (sourceLastModified > 0L) local.setLastModified(sourceLastModified)
        return mapOf(
            "uri" to uri.toString(),
            "localPath" to local.absolutePath,
            "displayName" to displayName,
            "displayPath" to displayPath(uri, displayName),
            "writable" to writable,
            "persisted" to persisted,
            "sourceLength" to local.length(),
            "sourceSha256" to sha256(local)
        )
    }

    internal fun writeSpbWallet(
        uriText: String,
        localPath: String,
        requestedLength: Long?,
        requestedSha256: String?,
        requestedExistingLength: Long?,
        requestedExistingSha256: String?,
        result: MethodChannel.Result
    ) {
        val recoveryFile = recoveryDataFile()
        val recoveryManifest = recoveryManifestFile()
        try {
            val uri = Uri.parse(uriText)
            val source = File(localPath)
            if (!source.isFile) error("Wallet snapshot does not exist")
            if (recoveryManifest.exists()) {
                error("A previous wallet recovery is still pending")
            }
            val expectedLength = source.length()
            val expectedSha256 = sha256(source)
            if (requestedLength != null && requestedLength != expectedLength) {
                error("Wallet snapshot size does not match the requested size")
            }
            if (requestedSha256 != null && requestedSha256 != expectedSha256) {
                error("Wallet snapshot SHA-256 does not match the requested hash")
            }
            if (requestedExistingLength != null || requestedExistingSha256 != null) {
                val existing = hashUri(uri)
                if ((requestedExistingLength != null && existing.first != requestedExistingLength) ||
                    (requestedExistingSha256 != null && existing.second != requestedExistingSha256)) {
                    error("The selected wallet was changed outside Wallet APS")
                }
            }

            recoveryFile.parentFile?.mkdirs()
            contentResolver.openInputStream(uri).use { input ->
                FileOutputStream(recoveryFile).use { output ->
                    if (input == null) error("Cannot back up selected SPB Wallet file")
                    input.copyTo(output)
                    output.fd.sync()
                }
            }
            val manifest = JSONObject().apply {
                put("uri", uriText)
                put("previousLength", recoveryFile.length())
                put("previousSha256", sha256(recoveryFile))
                put("expectedLength", expectedLength)
                put("expectedSha256", expectedSha256)
            }
            recoveryManifest.writeText(manifest.toString(), Charsets.UTF_8)

            contentResolver.openFileDescriptor(uri, "rwt").use { descriptor ->
                if (descriptor == null) error("Cannot open selected SPB Wallet file for writing")
                FileOutputStream(descriptor.fileDescriptor).use { output ->
                    source.inputStream().use { input -> input.copyTo(output) }
                    output.flush()
                    output.fd.sync()
                }
            }
            val published = hashUri(uri)
            if (published.first != expectedLength || published.second != expectedSha256) {
                error("Published wallet did not pass size/SHA-256 verification")
            }
            clearRecovery()
            result.success(mapOf("length" to published.first, "sha256" to published.second))
        } catch (error: Throwable) {
            result.error(
                "write_failed",
                error.message,
                mapOf("recoveryPath" to recoveryFile.takeIf { it.exists() }?.absolutePath)
            )
        }
    }

    private fun recoveryDirectory() = File(noBackupFilesDir, "vault_recovery")
    private fun recoveryDataFile() = File(recoveryDirectory(), "pending.swl")
    private fun recoveryManifestFile() = File(recoveryDirectory(), "pending.json")

    internal fun pendingRecovery(): Map<String, Any?>? {
        val manifestFile = recoveryManifestFile()
        val dataFile = recoveryDataFile()
        if (!manifestFile.isFile || !dataFile.isFile) return null
        return try {
            val json = JSONObject(manifestFile.readText(Charsets.UTF_8))
            mapOf(
                "uri" to json.getString("uri"),
                "previousLength" to json.getLong("previousLength"),
                "previousSha256" to json.getString("previousSha256"),
                "expectedLength" to json.getLong("expectedLength"),
                "expectedSha256" to json.getString("expectedSha256")
            )
        } catch (_: Throwable) {
            mapOf("damagedManifest" to true)
        }
    }

    internal fun restorePendingRecovery(result: MethodChannel.Result) {
        try {
            val manifestFile = recoveryManifestFile()
            val backup = recoveryDataFile()
            if (!manifestFile.isFile || !backup.isFile) error("No wallet recovery is pending")
            val manifest = JSONObject(manifestFile.readText(Charsets.UTF_8))
            val uri = Uri.parse(manifest.getString("uri"))
            val expectedLength = manifest.getLong("previousLength")
            val expectedSha256 = manifest.getString("previousSha256")
            contentResolver.openFileDescriptor(uri, "rwt").use { descriptor ->
                if (descriptor == null) error("Cannot open wallet recovery destination")
                FileOutputStream(descriptor.fileDescriptor).use { output ->
                    backup.inputStream().use { input -> input.copyTo(output) }
                    output.flush()
                    output.fd.sync()
                }
            }
            val restored = hashUri(uri)
            if (restored.first != expectedLength || restored.second != expectedSha256) {
                error("Restored wallet did not pass size/SHA-256 verification")
            }
            clearRecovery()
            result.success(mapOf("length" to restored.first, "sha256" to restored.second))
        } catch (error: Throwable) {
            result.error("restore_failed", error.message, null)
        }
    }

    internal fun clearRecovery() {
        recoveryManifestFile().delete()
        recoveryDataFile().delete()
        recoveryDirectory().takeIf { it.isDirectory && it.list()?.isEmpty() == true }?.delete()
    }

    private fun hashUri(uri: Uri): Pair<Long, String> {
        val digest = MessageDigest.getInstance("SHA-256")
        var length = 0L
        contentResolver.openInputStream(uri).use { input ->
            if (input == null) error("Cannot verify selected SPB Wallet file")
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
                length += count
            }
        }
        return length to digest.digest().joinToString("") {
            "%02x".format(it.toInt() and 0xff)
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") {
            "%02x".format(it.toInt() and 0xff)
        }
    }

    private fun openFile(path: String, mimeType: String, result: MethodChannel.Result) {
        try {
            val file = File(path)
            if (!file.exists()) error("File does not exist")
            val uri = FileProvider.getUriForFile(this, "${applicationContext.packageName}.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            result.success(true)
        } catch (error: ActivityNotFoundException) {
            result.error("no_viewer", "No application can open this file", null)
        } catch (error: Throwable) {
            result.error("open_failed", error.message, null)
        }
    }

    private fun shareFile(path: String, mimeType: String, title: String, result: MethodChannel.Result) {
        try {
            val file = File(path)
            if (!file.exists()) error("File does not exist")
            val uri = FileProvider.getUriForFile(this, "${applicationContext.packageName}.fileprovider", file)
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newRawUri(title, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, title))
            result.success(true)
        } catch (error: ActivityNotFoundException) {
            result.error("no_share_target", "No application can share this file", null)
        } catch (error: Throwable) {
            result.error("share_failed", error.message, null)
        }
    }

    private fun displayName(uri: Uri): String {
        if (uri.scheme == "file") {
            return uri.path?.let { File(it).name } ?: "wallet.swl"
        }
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null).use { cursor ->
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index)
            }
        }
        return "wallet.swl"
    }

    private fun lastModified(uri: Uri): Long {
        try {
            contentResolver.query(
                uri,
                arrayOf(DocumentsContract.Document.COLUMN_LAST_MODIFIED),
                null,
                null,
                null
            ).use { cursor ->
                if (cursor != null && cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                    if (index >= 0 && !cursor.isNull(index)) return cursor.getLong(index)
                }
            }
        } catch (_: Throwable) {}
        return 0L
    }

    private fun displayPath(uri: Uri, displayName: String): String {
        if (uri.scheme == "file") return uri.path ?: uri.toString()
        if (uri.authority == "com.android.providers.downloads.documents") {
            return "/storage/emulated/0/Download/$displayName"
        }
        return uri.toString()
    }
}
