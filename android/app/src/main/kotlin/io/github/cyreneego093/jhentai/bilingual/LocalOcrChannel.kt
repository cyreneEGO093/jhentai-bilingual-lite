// SPDX-License-Identifier: GPL-3.0-only
package io.github.cyreneego093.jhentai.bilingual

import android.content.Context
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import ai.onnxruntime.*
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import java.io.File
import java.nio.FloatBuffer
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.*

/** Optional offline OCR worker. No networking or logging of pixels/recognized text. */
class LocalOcrChannel(context: Context, messenger: BinaryMessenger) {
    private val directory = File(context.noBackupFilesDir, "bilingual-ocr-v1")
    private val channel = MethodChannel(messenger, "bilingual_lite/local_ocr")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val busy = AtomicBoolean(false)
    private val cancelled = AtomicBoolean(false)
    private val lock = Any()
    @Volatile private var disposed = false
    @Volatile private var activeId: String? = null
    private var runOptions: OrtSession.RunOptions? = null

    companion object {
        private val models = listOf(
            Triple("PP-OCRv6_det_small.onnx", 9929594L, "090f04abcd9d9a7498bc4ebf677e4cb9bdce1fe4197ddb7e529f1ef44e1ff94f"),
            Triple("PP-OCRv6_rec_small.onnx", 21234383L, "6f327246b50388f3c176ae304bd95767ea6dc0c9ae92153ef8cbe210b3c14884")
        )
    }
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "cancel" -> {
                    if (call.argument<String>("id") == activeId) cancel()
                    result.success(null)
                }
                "status" -> {
                    directory.mkdirs()
                    result.success(mapOf("directory" to directory.absolutePath,
                        "ready" to models.all { File(directory, it.first).length() == it.second }))
                }
                "recognize" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val id = call.argument<String>("id")
                    if (bytes == null || bytes.size > 16 * 1024 * 1024 || id == null) {
                        result.error("input", "OCR 图片无效。", null)
                    } else if (!busy.compareAndSet(false, true)) {
                        result.error("busy", "本地 OCR 正在处理上一张图片。", null)
                    } else {
                        cancelled.set(false)
                        activeId = id
                        worker.execute {
                            var regions: List<Map<String, Any>>? = null
                            var failure: String? = null
                            try {
                                regions = recognize(bytes)
                                checkCancelled()
                            } catch (e: Exception) {
                                failure = if (cancelled.get()) "本地 OCR 已取消。" else
                                    when (e) {
                                        is IllegalArgumentException -> e.message ?: "OCR 输入无效。"
                                        else -> "本地 OCR 运行失败，请重新下载模型或尝试框选。"
                                    }
                            } finally {
                                synchronized(lock) { runOptions?.close(); runOptions = null }
                                activeId = null
                                busy.set(false)
                            }
                            // Release the worker before Dart may submit the next tile.
                            main.post {
                                if (!disposed) {
                                    if (failure == null) result.success(regions)
                                    else result.error("ocr", failure, null)
                                }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun cancel() {
        cancelled.set(true)
        synchronized(lock) { runOptions?.setTerminate(true) }
    }
    fun dispose() {
        disposed = true
        cancel()
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }
    private fun checkCancelled() {
        if (cancelled.get() || disposed) throw IllegalStateException("cancelled")
    }
    private fun verifyModels() {
        models.forEach { (name, size, expected) ->
            checkCancelled()
            val file = File(directory, name)
            require(file.length() == size) { "请先到翻译设置下载本地 OCR 模型。" }
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(65536)
                while (true) {
                    checkCancelled()
                    val n = input.read(buffer)
                    if (n < 0) break
                    digest.update(buffer, 0, n)
                }
            }
            val actual = digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
            require(actual == expected) { "OCR 模型校验失败，请删除模型并重新下载。" }
        }
    }
    private fun recognize(bytes: ByteArray): List<Map<String, Any>> {
        verifyModels()
        checkCancelled()
        check(OpenCVLoader.initLocal())
        Core.setNumThreads(2)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth in 1..1536 && bounds.outHeight in 1..1536) { "OCR 图片应先分块处理。" }
        val bitmap = requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size)) { "无法解码 OCR 图片。" }
        val rgba = Mat()
        val bgr = Mat()
        try {
            Utils.bitmapToMat(bitmap, rgba)
            Imgproc.cvtColor(rgba, bgr, Imgproc.COLOR_RGBA2BGR)
        } finally { bitmap.recycle(); rgba.release() }
        try {
            val env = OrtEnvironment.getEnvironment()
            env.setTelemetry(false)
            OrtSession.SessionOptions().use { options ->
                options.setIntraOpNumThreads(2)
                options.setInterOpNumThreads(1)
                synchronized(lock) {
                    runOptions = OrtSession.RunOptions()
                    if (cancelled.get()) runOptions!!.setTerminate(true)
                }
                env.createSession(File(directory, models[0].first).absolutePath, options).use { detector ->
                    env.createSession(File(directory, models[1].first).absolutePath, options).use { recognizer ->
                        val rawChars = recognizer.metadata.customMetadata["character"]
                            ?: throw IllegalArgumentException("OCR 模型缺少字典。")
                        val chars = listOf("") + rawChars.split("\n") + listOf(" ")
                        val boxes = detect(env, detector, bgr)
                        require(boxes.size <= 100) { "文字行过多，请框选较小区域。" }
                        return boxes.mapNotNull { box ->
                            checkCancelled()
                            val crop = extract(bgr, box)
                            try {
                                val (text, score) = read(env, recognizer, crop, chars)
                                if (text.isBlank() || score < .55) null else {
                                    val x0 = box.minOf { it.x } / bgr.cols()
                                    val y0 = box.minOf { it.y } / bgr.rows()
                                    val x1 = box.maxOf { it.x } / bgr.cols()
                                    val y1 = box.maxOf { it.y } / bgr.rows()
                                    mapOf("text" to text, "confidence" to score, "bbox" to listOf(y0,x0,y1,x1))
                                }
                            } finally { crop.release() }
                        }
                    }
                }
            }
        } finally { bgr.release() }
    }
    /** BGR [-1,1] CHW, matching the fixed RapidOCR small models. */
    private fun tensor(env: OrtEnvironment, image: Mat): OnnxTensor {
        val count = image.rows() * image.cols()
        val bytes = ByteArray(count * 3)
        image.get(0, 0, bytes)
        val floats = FloatArray(count * 3)
        for (i in 0 until count) for (c in 0..2) {
            floats[c * count + i] = (bytes[i * 3 + c].toInt() and 255) / 127.5f - 1f
        }
        return OnnxTensor.createTensor(env, FloatBuffer.wrap(floats),
            longArrayOf(1, 3, image.rows().toLong(), image.cols().toLong()))
    }
    private fun detect(env: OrtEnvironment, session: OrtSession, image: Mat): List<Array<Point>> {
        val scale = min(1.0, 960.0 / max(image.rows(), image.cols()))
        val w = max(32, (image.cols() * scale / 32).roundToInt() * 32)
        val h = max(32, (image.rows() * scale / 32).roundToInt() * 32)
        val resized = Mat(); val probability = Mat(); val binary = Mat(); val hierarchy = Mat()
        val contours = ArrayList<MatOfPoint>()
        try {
            Imgproc.resize(image, resized, Size(w.toDouble(), h.toDouble()))
            tensor(env, resized).use { input ->
                session.run(mapOf(session.inputNames.first() to input), runOptions).use { output ->
                    val value = output[0] as OnnxTensor
                    val shape = value.info.shape
                    val mh = shape[2].toInt(); val mw = shape[3].toInt()
                    val scores = FloatArray(mh * mw)
                    value.floatBuffer.get(scores)
                    probability.create(mh, mw, CvType.CV_32FC1)
                    probability.put(0, 0, scores)
                    Imgproc.threshold(probability, binary, .3, 255.0, Imgproc.THRESH_BINARY)
                    binary.convertTo(binary, CvType.CV_8UC1)
                    Imgproc.findContours(binary, contours, hierarchy, Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE)
                    require(contours.size <= 1000) { "页面纹理过于复杂，请框选文字。" }
                    return contours.mapNotNull { contour ->
                        checkCancelled()
                        val outline = MatOfPoint2f(*contour.toArray())
                        val mask = Mat.zeros(mh, mw, CvType.CV_8UC1)
                        try {
                            val rect = Imgproc.minAreaRect(outline)
                            if (min(rect.size.width, rect.size.height) < 2) return@mapNotNull null
                            Imgproc.drawContours(mask, listOf(contour), 0, Scalar(255.0), -1)
                            if (Core.mean(probability, mask).`val`[0] < .6) return@mapNotNull null
                            // Rectangle expansion, not upstream polygon-unclip or bubble detection.
                            val pad = rect.size.area() * 1.5 / (2 * (rect.size.width + rect.size.height))
                            rect.size.width += pad * 2; rect.size.height += pad * 2
                            val points = Array(4) { Point() }; rect.points(points)
                            val ordered = order(points)
                            ordered.forEach {
                                it.x = (it.x / mw * image.cols()).coerceIn(0.0, image.cols() - 1.0)
                                it.y = (it.y / mh * image.rows()).coerceIn(0.0, image.rows() - 1.0)
                            }
                            ordered
                        } finally { outline.release(); mask.release() }
                    }
                }
            }
        } finally {
            contours.forEach { it.release() }
            resized.release(); probability.release(); binary.release(); hierarchy.release()
        }
    }
    private fun order(points: Array<Point>): Array<Point> {
        val sorted = points.sortedBy { it.x }
        val left = sorted.take(2).sortedBy { it.y }; val right = sorted.takeLast(2).sortedBy { it.y }
        return arrayOf(left[0], right[0], right[1], left[1])
    }
    private fun distance(a: Point, b: Point) = hypot(a.x - b.x, a.y - b.y)
    private fun extract(image: Mat, points: Array<Point>): Mat {
        val w = max(1, max(distance(points[0], points[1]), distance(points[3], points[2])).roundToInt())
        val h = max(1, max(distance(points[0], points[3]), distance(points[1], points[2])).roundToInt())
        val source = MatOfPoint2f(*points)
        val target = MatOfPoint2f(Point(0.0,0.0),Point(w.toDouble(),0.0),Point(w.toDouble(),h.toDouble()),Point(0.0,h.toDouble()))
        val transform = Imgproc.getPerspectiveTransform(source, target); val crop = Mat()
        try {
            Imgproc.warpPerspective(image,crop,transform,Size(w.toDouble(),h.toDouble()),Imgproc.INTER_CUBIC,Core.BORDER_REPLICATE)
            if (h >= w * 1.5) Core.rotate(crop, crop, Core.ROTATE_90_COUNTERCLOCKWISE)
            return crop
        } catch (e: Exception) { crop.release(); throw e }
        finally { source.release(); target.release(); transform.release() }
    }
    private fun read(env: OrtEnvironment, session: OrtSession, crop: Mat, chars: List<String>): Pair<String, Double> {
        val width = ceil(48.0 * crop.cols() / crop.rows()).toInt()
        require(width <= 1536) { "文字行太长，请框选较小区域。" }
        val resized = Mat(); val padded = Mat()
        try {
            Imgproc.resize(crop, resized, Size(max(1,width).toDouble(),48.0))
            // Approximate normalized zero padding with mid-grey before normalization.
            Core.copyMakeBorder(resized,padded,0,0,0,max(320,width)-width,Core.BORDER_CONSTANT,Scalar(127.5,127.5,127.5))
            tensor(env,padded).use { input ->
                session.run(mapOf(session.inputNames.first() to input),runOptions).use { output ->
                    val value = output[0] as OnnxTensor; val shape = value.info.shape
                    val steps = shape[1].toInt(); val classes = shape[2].toInt()
                    require(classes == chars.size) { "OCR 字典与模型不一致。" }
                    val buffer = value.floatBuffer; val row = FloatArray(classes)
                    val text = StringBuilder()
                    var previous = -1; var confidence = 0.0; var count = 0
                    repeat(steps) {
                        checkCancelled(); buffer.get(row)
                        var index = 0
                        for (j in 1 until classes) if (row[j] > row[index]) index = j
                        if (index != 0 && index != previous) {
                            text.append(chars[index]); confidence += row[index]; count++
                        }
                        previous = index
                    }
                    return text.toString().trim() to if (count == 0) 0.0 else confidence/count
                }
            }
        } finally { resized.release(); padded.release() }
    }
}

