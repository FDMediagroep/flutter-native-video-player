package com.example.native_video_player_example

import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.huddlecommunity.better_native_video_player.NativeVideoPlayerPlugin
import com.huddlecommunity.better_native_video_player.manager.SharedPlayerManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

@UnstableApi
@RunWith(AndroidJUnit4::class)
class MultiEngineTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val engines = mutableListOf<Engine>()

    private inner class Engine {
        val manager = SharedPlayerManager()
        lateinit var engine: FlutterEngine
        lateinit var channel: MethodChannel

        init {
            val ready = CountDownLatch(1)
            onMain {
                engine = FlutterEngine(context, null, false)
                engine.plugins.add(NativeVideoPlayerPlugin(manager))
                channel = MethodChannel(engine.dartExecutor.binaryMessenger, "engine_test")
                channel.setMethodCallHandler { call, result ->
                    if (call.method == "ready") {
                        ready.countDown()
                        result.success(null)
                    } else result.notImplemented()
                }
                engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            }
            engines.add(this)
            assertTrue("Dart engine did not start", ready.await(30, TimeUnit.SECONDS))
        }

        fun call(method: String, arguments: Any? = null): Any? {
            val done = CountDownLatch(1)
            var response: Any? = null
            var error: String? = null
            onMain {
                channel.invokeMethod(method, arguments, object : MethodChannel.Result {
                    override fun success(result: Any?) { response = result; done.countDown() }
                    override fun error(code: String, message: String?, details: Any?) {
                        error = "$code: $message"; done.countDown()
                    }
                    override fun notImplemented() { error = "Not implemented: $method"; done.countDown() }
                })
            }
            assertTrue("Timed out: $method", done.await(15, TimeUnit.SECONDS))
            assertNull(error, error)
            return response
        }

        fun plugin(method: String, arguments: Any?) =
            call("plugin", mapOf("method" to method, "arguments" to arguments))

        fun destroy() {
            onMain { engine.destroy() }
            engines.remove(this)
        }
    }

    private fun onMain(block: () -> Unit) = instrumentation.runOnMainSync(block)

    private fun waitUntil(condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 15000
        while (SystemClock.elapsedRealtime() < deadline) {
            var satisfied = false
            onMain { satisfied = condition() }
            if (satisfied) return
            SystemClock.sleep(50)
        }
        fail("Playback condition did not become true")
    }

    private fun localAudio(): File {
        val dataSize = 16000 * 2 * 20
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray()).putInt(36 + dataSize)
        header.put("WAVEfmt ".toByteArray()).putInt(16)
        header.putShort(1).putShort(1).putInt(16000).putInt(32000)
        header.putShort(2).putShort(16)
        header.put("data".toByteArray()).putInt(dataSize)
        return File(context.cacheDir, "engine-test.wav").also {
            it.outputStream().use { output ->
                output.write(header.array())
                output.write(ByteArray(dataSize))
            }
        }
    }

    @After
    fun cleanup() { engines.toList().asReversed().forEach { it.destroy() } }

    @Test
    fun controllerEventsSurviveBackgroundEngineAttachCancelAndDetach() {
        val main = Engine()
        val background = Engine()
        main.call("setup")
        background.call("setup")
        onMain { main.manager.sendControllerEvent(1, "pipStarted") }
        assertEquals(1, (main.call("events") as List<*>).size)
        assertEquals(0, (background.call("events") as List<*>).size)
        background.call("cancel")
        background.destroy()
        onMain { main.manager.sendControllerEvent(1, "pipStopped") }
        assertEquals(2, (main.call("events") as List<*>).size)
        main.call("setup")
    }

    @Test
    fun matchingTextureIdsRouteIndependentlyAndSurviveOtherEngineDetach() {
        assertTextureIsolation(detachMain = true)
    }

    @Test
    fun backgroundEngineDetachDoesNotInterruptMainPlayback() {
        assertTextureIsolation(detachMain = false)
    }

    private fun assertTextureIsolation(detachMain: Boolean) {
        val main = Engine()
        val background = Engine()
        val survivor = if (detachMain) background else main
        val args = mapOf("viewId" to 42, "controllerId" to 1, "showNativeControls" to false)
        assertNotNull(main.plugin("createTextureView", args))
        assertNotNull(background.plugin("createTextureView", args))
        main.plugin("setVolume", mapOf("viewId" to 42, "volume" to 0.25))
        background.plugin("setVolume", mapOf("viewId" to 42, "volume" to 0.75))
        lateinit var survivingPlayer: ExoPlayer
        onMain {
            val mainPlayer = main.manager.getOrCreatePlayer(context, 1).first
            val backgroundPlayer = background.manager.getOrCreatePlayer(context, 1).first
            survivingPlayer = if (detachMain) backgroundPlayer else mainPlayer
            assertNotSame(mainPlayer, backgroundPlayer)
            assertEquals(0.25f, mainPlayer.volume, 0.001f)
            assertEquals(0.75f, backgroundPlayer.volume, 0.001f)
        }
        survivor.plugin("load", mapOf("viewId" to 42, "url" to localAudio().toURI().toString(), "autoPlay" to true))
        waitUntil { survivingPlayer.isPlaying }
        var positionBeforeDetach = 0L
        onMain { positionBeforeDetach = survivingPlayer.currentPosition }
        (if (detachMain) main else background).destroy()
        survivor.plugin("setVolume", mapOf("viewId" to 42, "volume" to 0.5))
        onMain { assertEquals(0.5f, survivor.manager.getOrCreatePlayer(context, 1).first.volume, 0.001f) }
        waitUntil { survivingPlayer.isPlaying && survivingPlayer.currentPosition > positionBeforeDetach + 500 }
        survivor.plugin("viewDisposed", mapOf("viewId" to 42))
        survivor.plugin("disposeController", mapOf("controllerId" to 1))
    }
}
