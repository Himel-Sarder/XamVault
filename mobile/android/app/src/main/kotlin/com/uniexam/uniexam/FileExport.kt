package com.uniexam.uniexam

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * Writes a downloaded report into the device's Downloads folder.
 *
 * The bytes arrive already fetched: a report is behind the caller's bearer token, so the
 * app downloads it and then asks this to put it somewhere the person can find it. A
 * plain link could not have carried the token.
 *
 * On API 29 and up this goes through MediaStore, which needs no storage permission and
 * hands back a `content://` URI that other apps can open directly — so a teacher can go
 * straight from "saved" to reading the PDF. Below that, scoped storage does not exist
 * and writing to the public folder would need WRITE_EXTERNAL_STORAGE; rather than put a
 * permission prompt in front of an export, the file goes to the app's own external
 * directory and the caller is told where it landed.
 */
class FileExport(private val context: Context) {

    /**
     * @return where it went: a `uri` to open it with, and a `location` to show a person.
     */
    fun save(bytes: ByteArray, filename: String, mimeType: String): Map<String, Any?> {
        val safe = sanitise(filename)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(bytes, safe, mimeType)
        } else {
            saveToAppDirectory(bytes, safe)
        }
    }

    private fun saveViaMediaStore(
        bytes: ByteArray,
        filename: String,
        mimeType: String,
    ): Map<String, Any?> {
        val resolver = context.contentResolver
        val details = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, filename)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            // Hidden from other apps until the bytes are all there, so nothing can read
            // a half-written report.
            put(MediaStore.Downloads.IS_PENDING, 1)
        }

        val target = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, details)
            ?: throw IllegalStateException("Downloads folder is not available")

        try {
            resolver.openOutputStream(target)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Could not open the file for writing")
        } catch (error: Exception) {
            // Do not leave a pending, empty row behind.
            resolver.delete(target, null, null)
            throw error
        }

        details.clear()
        details.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(target, details, null, null)

        // MediaStore renames on collision, so report the name it actually used rather
        // than the one that was asked for.
        val actual = displayName(target) ?: filename
        return mapOf("uri" to target.toString(), "location" to "Downloads/$actual")
    }

    private fun saveToAppDirectory(bytes: ByteArray, filename: String): Map<String, Any?> {
        val directory = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: context.filesDir
        if (!directory.exists()) directory.mkdirs()

        val file = uniqueFile(directory, filename)
        file.writeBytes(bytes)
        // No content:// URI here, so nothing to open it with; the path is what there is.
        return mapOf("uri" to null, "location" to file.absolutePath)
    }

    /** Opens the saved file in whatever the device uses for that type. */
    fun open(uriString: String, mimeType: String): Boolean {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse(uriString), mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(intent)
            true
        } catch (error: Exception) {
            // No PDF or spreadsheet viewer installed. The file is still saved, so this
            // is a disappointment rather than a failure.
            false
        }
    }

    private fun displayName(uri: Uri): String? {
        return try {
            context.contentResolver.query(
                uri,
                arrayOf(MediaStore.Downloads.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (error: Exception) {
            null
        }
    }

    /** Strips anything that would be a path rather than a name. */
    private fun sanitise(filename: String): String {
        val cleaned = filename
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .replace(Regex("""[^A-Za-z0-9._-]"""), "-")
            .trim('-', '.')
        return cleaned.ifEmpty { "report" }
    }

    private fun uniqueFile(directory: File, filename: String): File {
        val file = File(directory, filename)
        if (!file.exists()) return file
        val stem = filename.substringBeforeLast('.', filename)
        val suffix = filename.substringAfterLast('.', "")
        val dot = if (suffix.isEmpty()) "" else "."
        var n = 1
        while (true) {
            val candidate = File(directory, "$stem ($n)$dot$suffix")
            if (!candidate.exists()) return candidate
            n++
        }
    }
}
