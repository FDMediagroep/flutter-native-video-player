package com.huddlecommunity.better_native_video_player

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Backs the notification's play/pause button on API < 33, where System UI derives the
 * media controls from the notification's actions instead of the session's PlaybackState.
 *
 * The callback is owned by the notification handler that currently holds the (single)
 * media notification.
 */
class VideoPlayerNotificationActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_PLAY = "com.huddlecommunity.better_native_video_player.action.PLAY"
        const val ACTION_PAUSE = "com.huddlecommunity.better_native_video_player.action.PAUSE"

        @Volatile
        private var playPauseCommand: ((Boolean) -> Unit)? = null

        fun setPlayPauseCommand(command: ((Boolean) -> Unit)?) {
            playPauseCommand = command
        }

        fun clearPlayPauseCommand(command: (Boolean) -> Unit) {
            if (playPauseCommand === command) {
                playPauseCommand = null
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_PLAY -> playPauseCommand?.invoke(true)
            ACTION_PAUSE -> playPauseCommand?.invoke(false)
        }
    }
}
