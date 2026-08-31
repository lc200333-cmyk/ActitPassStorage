package com.lc200333cmyk.walletaps

import android.content.Intent
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.security.MessageDigest
import org.junit.After
import org.junit.Before
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

class TestWalletDocumentsProvider : DocumentsProvider() {
    companion object {
        const val authority = "com.example.actit_pass_storage.test.documents"
        const val documentId = "wallet.swl"
        @Volatile var failWrites = false

        fun uri(): Uri = DocumentsContract.buildDocumentUri(authority, documentId)
    }

    override fun onCreate() = true

    override fun openDocument(
        requestedId: String,
        mode: String,
        signal: CancellationSignal?
    ): ParcelFileDescriptor {
        if (requestedId != documentId) throw FileNotFoundException(requestedId)
        if (mode.contains('w') && failWrites) {
            throw FileNotFoundException("Injected write failure")
        }
        val file = File(requireNotNull(context).cacheDir, "saf-test/$documentId")
        file.parentFile?.mkdirs()
        val flags = if (mode.contains('w')) {
            ParcelFileDescriptor.MODE_READ_WRITE or
                ParcelFileDescriptor.MODE_CREATE or
                ParcelFileDescriptor.MODE_TRUNCATE
        } else {
            ParcelFileDescriptor.MODE_READ_ONLY
        }
        return ParcelFileDescriptor.open(file, flags)
    }

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
        val columns = projection ?: arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_FLAGS,
            DocumentsContract.Document.COLUMN_SIZE
        )
        val file = File(requireNotNull(context).cacheDir, "saf-test/$documentId")
        return MatrixCursor(columns).apply {
            val row = newRow()
            columns.forEach { column ->
                row.add(
                    when (column) {
                        DocumentsContract.Document.COLUMN_DOCUMENT_ID -> documentId
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME -> documentId
                        DocumentsContract.Document.COLUMN_MIME_TYPE -> "application/octet-stream"
                        DocumentsContract.Document.COLUMN_FLAGS ->
                            DocumentsContract.Document.FLAG_SUPPORTS_WRITE
                        DocumentsContract.Document.COLUMN_SIZE -> file.length()
                        else -> null
                    }
                )
            }
        }
    }

    override fun queryRoots(projection: Array<out String>?): Cursor =
        MatrixCursor(projection ?: emptyArray())

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<out String>?,
        sortOrder: String?
    ): Cursor = MatrixCursor(projection ?: emptyArray())
}

@RunWith(AndroidJUnit4::class)
class SafVaultRecoveryTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val testContext = instrumentation.context
    private val testUri = TestWalletDocumentsProvider.uri()
    private val target = File(testContext.cacheDir, "saf-test/${TestWalletDocumentsProvider.documentId}")
    private val snapshot = File(context.cacheDir, "saf-test/snapshot.swl")

    @Before
    fun grantDocumentAccess() {
        testContext.grantUriPermission(
            context.packageName,
            testUri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
    }

    @After
    fun cleanUp() {
        TestWalletDocumentsProvider.failWrites = false
        testContext.revokeUriPermission(
            testUri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
        target.parentFile?.deleteRecursively()
    }

    @Test
    fun verifiedWriteReturnsSizeAndHash() {
        val original = byteArrayOf(1, 2, 3)
        val replacement = byteArrayOf(9, 8, 7, 6)
        target.parentFile?.mkdirs()
        target.writeBytes(original)
        snapshot.writeBytes(replacement)

        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.clearRecovery()
                val result = CapturingResult()
                activity.writeSpbWallet(
                    TestWalletDocumentsProvider.uri().toString(),
                    snapshot.path,
                    replacement.size.toLong(),
                    sha256(replacement),
                    original.size.toLong(),
                    sha256(original),
                    result
                )
                assertNull(result.errorCode)
                val response = result.value as Map<*, *>
                assertEquals(replacement.size.toLong(), response["length"])
                assertEquals(sha256(replacement), response["sha256"])
                assertArrayEquals(replacement, target.readBytes())
                assertNull(activity.pendingRecovery())
            }
        }
    }

    @Test
    fun failedWriteKeepsRecoveryAndCanRestoreOriginal() {
        val original = byteArrayOf(4, 5, 6)
        val replacement = byteArrayOf(7, 8, 9)
        target.parentFile?.mkdirs()
        target.writeBytes(original)
        snapshot.writeBytes(replacement)

        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.clearRecovery()
                TestWalletDocumentsProvider.failWrites = true
                val failed = CapturingResult()
                activity.writeSpbWallet(
                    TestWalletDocumentsProvider.uri().toString(),
                    snapshot.path,
                    replacement.size.toLong(),
                    sha256(replacement),
                    original.size.toLong(),
                    sha256(original),
                    failed
                )
                assertNotNull(failed.errorCode)
                assertNotNull(activity.pendingRecovery())
                assertArrayEquals(original, target.readBytes())

                TestWalletDocumentsProvider.failWrites = false
                val restored = CapturingResult()
                activity.restorePendingRecovery(restored)
                assertNull(restored.errorCode)
                assertArrayEquals(original, target.readBytes())
                assertNull(activity.pendingRecovery())
            }
        }
    }

    @Test
    fun externallyChangedDocumentIsNotOverwritten() {
        val original = byteArrayOf(1, 1, 1)
        val externallyChanged = byteArrayOf(2, 2, 2)
        val replacement = byteArrayOf(3, 3, 3)
        target.parentFile?.mkdirs()
        target.writeBytes(externallyChanged)
        snapshot.writeBytes(replacement)

        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.clearRecovery()
                val result = CapturingResult()
                activity.writeSpbWallet(
                    TestWalletDocumentsProvider.uri().toString(),
                    snapshot.path,
                    replacement.size.toLong(),
                    sha256(replacement),
                    original.size.toLong(),
                    sha256(original),
                    result
                )
                assertNotNull(result.errorCode)
                assertArrayEquals(externallyChanged, target.readBytes())
                assertNull(activity.pendingRecovery())
            }
        }
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") {
            "%02x".format(it.toInt() and 0xff)
        }
}

private class CapturingResult : MethodChannel.Result {
    var value: Any? = null
    var errorCode: String? = null

    override fun success(result: Any?) {
        value = result
    }

    override fun error(code: String, message: String?, details: Any?) {
        errorCode = code
    }

    override fun notImplemented() {
        errorCode = "not_implemented"
    }
}
