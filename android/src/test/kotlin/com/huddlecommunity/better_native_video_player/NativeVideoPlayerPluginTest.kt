package com.huddlecommunity.better_native_video_player

import android.content.Context
import android.os.Looper
import com.huddlecommunity.better_native_video_player.manager.SharedPlayerManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.FlutterException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import io.flutter.plugin.platform.PlatformViewRegistry
import org.junit.runner.RunWith
import org.mockito.ArgumentMatchers
import org.mockito.Mockito
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.nio.ByteBuffer
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class NativeVideoPlayerPluginTest {
    private val engines = mutableListOf<Engine>()
    private val controllerChannel = "native_video_player_controller_1"

    private class Engine {
        val plugin = NativeVideoPlayerPlugin()
        val messenger = Mockito.mock(BinaryMessenger::class.java)
        val binding = Mockito.mock(FlutterPlugin.FlutterPluginBinding::class.java)
        val handlers = mutableMapOf<String, BinaryMessenger.BinaryMessageHandler?>()

        init {
            val context: Context = RuntimeEnvironment.getApplication()
            Mockito.`when`(binding.applicationContext).thenReturn(context)
            Mockito.`when`(binding.binaryMessenger).thenReturn(messenger)
            Mockito.`when`(binding.platformViewRegistry)
                .thenReturn(Mockito.mock(PlatformViewRegistry::class.java))
            Mockito.doAnswer { invocation ->
                handlers[invocation.getArgument(0)] = invocation.getArgument(1)
                null
            }.`when`(messenger).setMessageHandler(
                ArgumentMatchers.anyString(),
                ArgumentMatchers.nullable(BinaryMessenger.BinaryMessageHandler::class.java)
            )
            plugin.onAttachedToEngine(binding)
        }

        fun call(channel: String, method: String, arguments: Any?): Any? {
            val handler = assertNotNull(handlers[channel])
            val message = StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall(method, arguments))
            message.flip()
            var response: ByteBuffer? = null
            handler.onMessage(message) { response = it }
            val envelope = assertNotNull(response)
            envelope.flip()
            return StandardMethodCodec.INSTANCE.decodeEnvelope(envelope)
        }

        fun setup() = call("native_video_player", "setupControllerEventChannel", mapOf("controllerId" to 1))

        fun detach() = plugin.onDetachedFromEngine(binding)
    }

    private fun attach(): Engine = Engine().also { engines.add(it) }

    @AfterTest
    fun detachEngines() {
        engines.asReversed().forEach { it.detach() }
    }

    @Test
    fun backgroundEngineDoesNotRedirectMainEngineRegistration() {
        val main = attach()
        val background = attach()

        main.setup()

        assertNotNull(main.handlers[controllerChannel])
        assertNull(background.handlers[controllerChannel])
    }

    @Test
    fun sameControllerIdRegistersIndependentlyOnEachEngine() {
        val main = attach()
        val background = attach()
        main.setup()
        background.setup()

        background.call("native_video_player", "teardownControllerEventChannel", mapOf("controllerId" to 1))

        assertNotNull(main.handlers[controllerChannel])
        assertNull(background.handlers[controllerChannel])
    }

    @Test
    fun backgroundDetachPreservesMainEngineChannelAndSink() {
        val main = attach()
        val background = attach()
        background.setup()
        background.call(controllerChannel, "listen", null)
        main.setup()
        main.call(controllerChannel, "listen", null)

        background.detach()
        engines.remove(background)
        SharedPlayerManager.sendControllerEvent(1, "pipStarted")
        shadowOf(Looper.getMainLooper()).idle()

        assertNotNull(main.handlers[controllerChannel])
        assertNull(background.handlers[controllerChannel])
        Mockito.verify(main.messenger).send(
            ArgumentMatchers.eq(controllerChannel),
            ArgumentMatchers.any(ByteBuffer::class.java)
        )
        main.setup()
    }

    @Test
    fun detachedEngineReportsRegistrationFailure() {
        val main = attach()
        val background = attach()
        val handler = assertNotNull(background.handlers["native_video_player"])
        background.detach()
        engines.remove(background)
        background.handlers["native_video_player"] = handler

        val error = assertFailsWith<FlutterException> { background.setup() }

        assertEquals("NO_ENGINE", error.code)
        main.setup()
        assertNotNull(main.handlers[controllerChannel])
    }
}
