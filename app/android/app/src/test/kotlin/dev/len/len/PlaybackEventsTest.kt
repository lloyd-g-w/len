package dev.len.len

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** What focus changes and media keys mean for Dart ([PlaybackService], [PlaybackFocus]). */
class PlaybackEventsTest {
    @Test
    fun focusChangesBecomeDartEvents() {
        assertEquals("focusGain", PlaybackEvents.focusChange(PlaybackEvents.AUDIOFOCUS_GAIN))
        assertEquals("focusLoss", PlaybackEvents.focusChange(PlaybackEvents.AUDIOFOCUS_LOSS))
        assertEquals(
            "focusLossTransient",
            PlaybackEvents.focusChange(PlaybackEvents.AUDIOFOCUS_LOSS_TRANSIENT),
        )
        assertEquals("duck", PlaybackEvents.focusChange(PlaybackEvents.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK))
        // AUDIOFOCUS_GAIN_TRANSIENT (2) and the like are never sent to a holder.
        assertNull(PlaybackEvents.focusChange(2))
        assertNull(PlaybackEvents.focusChange(0))
    }

    @Test
    fun nextAndPreviousSkipTenSeconds() {
        assertEquals("forward", PlaybackEvents.mediaKey(PlaybackEvents.KEYCODE_MEDIA_NEXT))
        assertEquals("forward", PlaybackEvents.mediaKey(PlaybackEvents.KEYCODE_MEDIA_FAST_FORWARD))
        assertEquals("rewind", PlaybackEvents.mediaKey(PlaybackEvents.KEYCODE_MEDIA_PREVIOUS))
        assertEquals("rewind", PlaybackEvents.mediaKey(PlaybackEvents.KEYCODE_MEDIA_REWIND))
    }

    @Test
    fun playPauseAndHookAreLeftToTheSession() {
        assertNull(PlaybackEvents.mediaKey(85)) // KEYCODE_MEDIA_PLAY_PAUSE
        assertNull(PlaybackEvents.mediaKey(79)) // KEYCODE_HEADSETHOOK
        assertNull(PlaybackEvents.mediaKey(126)) // KEYCODE_MEDIA_PLAY
        assertNull(PlaybackEvents.mediaKey(127)) // KEYCODE_MEDIA_PAUSE
        assertNull(PlaybackEvents.mediaKey(86)) // KEYCODE_MEDIA_STOP
    }

    @Test
    fun positionsStayInTheKeptAudio() {
        assertEquals(0L, PlaybackEvents.clampPosition(-40L, 60000L))
        assertEquals(1200L, PlaybackEvents.clampPosition(1200L, 60000L))
        assertEquals(60000L, PlaybackEvents.clampPosition(61000L, 60000L))
        assertEquals(0L, PlaybackEvents.clampPosition(500L, 0L))
    }

    @Test
    fun headingFallsBackToTheNotebookThenLen() {
        assertEquals("Lecture 3", NowPlaying("Lecture 3", "Physics", true, 0L, 1L, 1f).heading)
        assertEquals("Physics", NowPlaying("", "Physics", true, 0L, 1L, 1f).heading)
        assertEquals("Len", NowPlaying("", "", true, 0L, 1L, 1f).heading)
    }
}
