package com.naveen.expense_manager.expense_manager

import android.content.ContentUris
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.SamplerConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "expense_manager/offline_models"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listModels" -> {
                        try {
                            result.success(queryOfflineModels().map { it.toMap() })
                        } catch (error: Exception) {
                            result.error("offline_list_failed", error.message, null)
                        }
                    }
                    "infer" -> handleInfer(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleInfer(call: MethodCall, result: MethodChannel.Result) {
        val modelName = call.argument<String>("modelName")?.trim().orEmpty()
        val prompt = call.argument<String>("prompt")?.trim().orEmpty()
        val maxTokens = call.argument<Int>("maxTokens")?.takeIf { it > 0 } ?: 4096

        if (modelName.isEmpty()) {
            result.error("offline_model_missing", "Offline model name is required.", null)
            return
        }
        if (prompt.isEmpty()) {
            result.error("offline_prompt_missing", "Prompt is required.", null)
            return
        }

        Thread {
            try {
                val modelRecord = queryOfflineModels(modelName).firstOrNull()
                    ?: throw IllegalStateException("Model \"$modelName\" not found in device storage.")
                val localModel = ensureLocalModelFile(modelRecord)
                val cacheDirPath = File(cacheDir, "litertlm_cache").apply { mkdirs() }.absolutePath

                val engineConfig = EngineConfig(
                    localModel.absolutePath,
                    Backend.CPU(),
                    Backend.CPU(),
                    Backend.CPU(),
                    maxTokens,
                    cacheDirPath,
                )

                val responseText = Engine(engineConfig).use { engine ->
                    engine.initialize()
                    val conversationConfig = ConversationConfig(
                        Contents.of(
                            Content.Text(
                                "Extract financial transactions from SMS. Return only JSON array output. No markdown."
                            )
                        ),
                        emptyList(),
                        emptyList(),
                        SamplerConfig(40, 0.95, 0.2, 7),
                        false,
                    )
                    engine.createConversation(conversationConfig).use { conversation ->
                        val message = conversation.sendMessage(prompt, emptyMap<String, Any>())
                        message.contents.contents
                            .filterIsInstance<Content.Text>()
                            .joinToString(separator = "") { it.text }
                            .trim()
                    }
                }

                runOnUiThread {
                    result.success(responseText.ifEmpty { "[]" })
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("offline_inference_failed", error.message, null)
                }
            }
        }.start()
    }

    private fun queryOfflineModels(exactName: String? = null): List<OfflineModelRecord> {
        val models = mutableListOf<OfflineModelRecord>()
        val seenNames = mutableSetOf<String>()

        // --- 1. MediaStore: search all indexed external files (superset of Downloads) ---
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,
        )
        val selection = buildString {
            append("${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?")
            if (!exactName.isNullOrBlank()) {
                append(" AND ${MediaStore.MediaColumns.DISPLAY_NAME} = ?")
            }
        }
        val selectionArgs = buildList {
            add("%.litertlm")
            if (!exactName.isNullOrBlank()) add(exactName)
        }.toTypedArray()

        val mediaStoreUri = MediaStore.Files.getContentUri("external")
        try {
            contentResolver.query(
                mediaStoreUri,
                projection,
                selection,
                selectionArgs,
                "${MediaStore.MediaColumns.DATE_MODIFIED} DESC",
            )?.use { cursor ->
                val idIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                val nameIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
                val modifiedIndex = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)

                while (cursor.moveToNext()) {
                    val displayName = cursor.getString(nameIndex)?.trim().orEmpty()
                    if (!displayName.endsWith(".litertlm")) continue
                    if (exactName != null && displayName != exactName) continue
                    if (!seenNames.add(displayName)) continue

                    val id = cursor.getLong(idIndex)
                    val size = if (cursor.isNull(sizeIndex)) 0L else cursor.getLong(sizeIndex)
                    val modified = if (cursor.isNull(modifiedIndex)) 0L else cursor.getLong(modifiedIndex) * 1000L

                    models.add(
                        OfflineModelRecord(
                            name = displayName,
                            uri = ContentUris.withAppendedId(mediaStoreUri, id),
                            sourceFile = null,
                            sizeBytes = size,
                            modifiedAtMillis = modified,
                        )
                    )
                }
            }
        } catch (_: Exception) { /* MediaStore query failed, continue to direct scan */ }

        // --- 2. Direct filesystem scan ---
        val scanDirs = buildList {
            // App's own external files dir — always accessible, no permission needed.
            // This is where the Flutter-side importer copies models to.
            getExternalFilesDir(null)?.let { add(File(it, "models")) }
            // Public Downloads (accessible with READ_EXTERNAL_STORAGE on older Android)
            add(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS))
            // AI Edge Gallery — only works if MANAGE_EXTERNAL_STORAGE granted AND Android < 11.
            // Kept as best-effort; fails silently on Android 11+.
            add(File(Environment.getExternalStorageDirectory(), "Android/data/com.google.aiedge.gallery/files"))
            add(File(Environment.getExternalStorageDirectory(), "Android/data/com.google.aiedge.gallery/files/models"))
        }

        for (dir in scanDirs) {
            try {
                if (!dir.exists() || !dir.canRead()) continue
                dir.walkTopDown().maxDepth(4)
                    .filter { it.isFile && it.name.endsWith(".litertlm") }
                    .forEach { file ->
                        if (exactName != null && file.name != exactName) return@forEach
                        if (!seenNames.add(file.name)) return@forEach
                        models.add(
                            OfflineModelRecord(
                                name = file.name,
                                uri = Uri.fromFile(file),
                                sourceFile = file,
                                sizeBytes = file.length(),
                                modifiedAtMillis = file.lastModified(),
                            )
                        )
                    }
            } catch (_: SecurityException) {
                // Path blocked without MANAGE_EXTERNAL_STORAGE — skip silently
            } catch (_: Exception) { /* Other errors, skip */ }
        }

        return models
    }

    private fun ensureLocalModelFile(record: OfflineModelRecord): File {
        // If the source file is directly accessible, use it — avoids copying 2+ GB models
        record.sourceFile?.let { file ->
            if (file.exists() && file.canRead()) return file
        }

        val modelsDir = File(cacheDir, "offline_models").apply { mkdirs() }
        val localFile = File(modelsDir, sanitizeFileName(record.name))

        if (localFile.exists() && (record.sizeBytes <= 0L || localFile.length() == record.sizeBytes)) {
            return localFile
        }

        val input = if (record.uri.scheme == "file") {
            FileInputStream(File(record.uri.path!!))
        } else {
            contentResolver.openInputStream(record.uri)
                ?: throw IllegalStateException("Could not open model file ${record.name}.")
        }

        input.use { inp ->
            FileOutputStream(localFile).use { out ->
                inp.copyTo(out)
            }
        }

        return localFile
    }

    private fun sanitizeFileName(name: String): String {
        return name.replace(Regex("[^A-Za-z0-9._-]"), "_")
    }

    private data class OfflineModelRecord(
        val name: String,
        val uri: Uri,
        val sourceFile: File?,
        val sizeBytes: Long,
        val modifiedAtMillis: Long,
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "name" to name,
            "sizeBytes" to sizeBytes,
            "modifiedAtMillis" to modifiedAtMillis,
        )
    }
}
