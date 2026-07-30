/** Stream audio player (HTML Audio) */

let currentAudio = null
let playTimeout = null

export function playStream(url, volume = 0.35) {
  stopStream()
  if (!url) return

  playTimeout = setTimeout(() => {
    const audio = new Audio(url)
    currentAudio = audio
    audio.volume = volume

    audio.addEventListener('error', () => {
      if (currentAudio === audio) {
        window.dispatchEvent(new CustomEvent('nyn-stream-error'))
      }
    })

    audio.play().catch((err) => {
      console.error('[nyn_carradio] Audio playback error:', err)
    })
    playTimeout = null
  }, 200)
}

export function stopStream() {
  if (playTimeout) {
    clearTimeout(playTimeout)
    playTimeout = null
  }
  if (currentAudio) {
    currentAudio.pause()
    currentAudio.src = ''
    currentAudio = null
  }
}
