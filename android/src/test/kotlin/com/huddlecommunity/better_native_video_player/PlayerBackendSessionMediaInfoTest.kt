package com.huddlecommunity.better_native_video_player

import android.content.Context
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.huddlecommunity.better_native_video_player.manager.SharedPlayerManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.runner.RunWith
import org.mockito.Mockito
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertEquals

@UnstableApi
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class PlayerBackendSessionMediaInfoTest {
    private val context: Context = RuntimeEnvironment.getApplication()
    private val messenger = Mockito.mock(BinaryMessenger::class.java)
    private val manager = Mockito.spy(SharedPlayerManager()).also {
        Mockito.doReturn(Mockito.mock(ExoPlayer::class.java))
            .`when`(it).buildPlayer(context, null, false, false)
    }

    private fun attachView(viewId: Long, title: String) = PlayerBackendSession(
        context,
        manager,
        viewId,
        mapOf("controllerId" to 1, "mediaInfo" to mapOf("title" to title)),
        messenger
    ) {}

    private fun PlayerBackendSession.setMediaInfo(title: String) {
        methodHandler.handleMethodCall(
            MethodCall("setMediaInfo", mapOf("mediaInfo" to mapOf("title" to title))),
            Mockito.mock(MethodChannel.Result::class.java)
        )
    }

    @Test
    fun siblingViewKeepsMetadataUpdatedThroughAnotherController() {
        val first = attachView(1L, "A")
        first.setMediaInfo("B")

        // The sibling controller still carries title A in its creation args.
        val second = attachView(2L, "A")

        assertEquals("B", second.currentMediaInfo?.get("title"))
        assertEquals("B", first.currentMediaInfo?.get("title"))
        assertEquals("B", manager.getMediaInfo(1)?.get("title"))
    }

    @Test
    fun explicitUpdateAfterAttachReplacesSharedMetadata() {
        val first = attachView(1L, "A")
        val second = attachView(2L, "A")

        second.setMediaInfo("C")

        assertEquals("C", first.currentMediaInfo?.get("title"))
        assertEquals("C", manager.getMediaInfo(1)?.get("title"))
    }
}
