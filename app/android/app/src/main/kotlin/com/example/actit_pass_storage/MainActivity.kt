package com.example.actit_pass_storage

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "actit_pass_storage/spb_wallet"
    private val openRequestCode = 7401
    private val createRequestCode = 7402
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingCreateResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickSpbWallet" -> pickSpbWallet(result)
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
                    if (uri == null || localPath == null) {
                        result.error("bad_args", "Missing uri or localPath", null)
                    } else {
                        writeSpbWallet(uri, localPath, result)
                    }
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
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, openRequestCode)
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
        startActivityForResult(intent, createRequestCode)
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
            val displayName = knownDisplayName?.takeIf { it.isNotBlank() } ?: displayName(uri)
            val local = File(cacheDir, "spbwallet_${System.currentTimeMillis()}_$displayName")
            contentResolver.openInputStream(uri).use { input ->
                FileOutputStream(local).use { output ->
                    if (input == null) error("Cannot open selected SPB Wallet file")
                    input.copyTo(output)
                }
            }
            result.success(mapOf(
                "uri" to uri.toString(),
                "localPath" to local.absolutePath,
                "displayName" to displayName,
                "displayPath" to displayPath(uri, displayName),
                "writable" to writable,
                "persisted" to persisted
            ))
        } catch (error: Throwable) {
            result.error("copy_failed", error.message, null)
        }
    }

    private fun writeSpbWallet(uriText: String, localPath: String, result: MethodChannel.Result) {
        try {
            val uri = Uri.parse(uriText)
            contentResolver.openOutputStream(uri, "wt").use { output ->
                if (output == null) error("Cannot open selected SPB Wallet file for writing")
                File(localPath).inputStream().use { input -> input.copyTo(output) }
                output.flush()
            }
            result.success(true)
        } catch (error: Throwable) {
            result.error("write_failed", error.message, null)
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
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null).use { cursor ->
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index)
            }
        }
        return "wallet.swl"
    }

    private fun displayPath(uri: Uri, displayName: String): String {
        if (uri.scheme == "file") return uri.path ?: uri.toString()
        if (uri.authority == "com.android.providers.downloads.documents") {
            return "/storage/emulated/0/Download/$displayName"
        }
        return uri.toString()
    }
}
