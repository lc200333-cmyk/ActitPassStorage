package com.example.actit_pass_storage

import android.app.Activity
import android.content.ActivityNotFoundException
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
    private var pendingPickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickSpbWallet" -> pickSpbWallet(result)
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
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
        try {
            contentResolver.takePersistableUriPermission(uri, flags)
        } catch (_: SecurityException) {
            // Some providers grant temporary access only. We can still work during this session.
        }
        copySpbWallet(uri, null, result)
    }

    private fun copySpbWallet(uri: Uri, knownDisplayName: String?, result: MethodChannel.Result) {
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
                "displayPath" to displayPath(uri, displayName)
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
