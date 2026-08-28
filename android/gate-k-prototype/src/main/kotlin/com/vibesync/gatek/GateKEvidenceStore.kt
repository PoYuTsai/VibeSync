package com.vibesync.gatek

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStreamWriter
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * App-private metadata-only evidence sink. The final file is replaced with an
 * atomic move so readers never observe a partially written JSON document.
 */
class GateKEvidenceStore(
    private val filesDir: File,
) {
    companion object {
        const val FILE_NAME = "gate-k-evidence.json"
        private const val TEMP_FILE_NAME = ".gate-k-evidence.json.tmp"
    }

    val evidenceFile: File
        get() = File(filesDir, FILE_NAME)

    @Synchronized
    fun write(packet: GateKEvidencePacket): File {
        val json = GateKEvidenceJson.encode(packet)
        if (!filesDir.isDirectory && !filesDir.mkdirs()) {
            throw IOException("evidence directory unavailable")
        }
        val target = evidenceFile
        val temporary = File(filesDir, TEMP_FILE_NAME)
        try {
            FileOutputStream(temporary).use { output ->
                val writer = OutputStreamWriter(output, StandardCharsets.UTF_8)
                writer.write(json)
                writer.flush()
                output.fd.sync()
            }
            Files.move(
                temporary.toPath(),
                target.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING,
            )
            return target
        } catch (error: IOException) {
            temporary.delete()
            throw error
        } catch (error: UnsupportedOperationException) {
            temporary.delete()
            throw IOException("atomic evidence move unavailable", error)
        }
    }

    fun read(): String? = evidenceFile.takeIf(File::isFile)?.readText(StandardCharsets.UTF_8)
}
