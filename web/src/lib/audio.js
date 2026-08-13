let currentAudio = null
let playGeneration = 0

function stopInternal() {
  if (!currentAudio) return
  const audio = currentAudio
  currentAudio = null
  try {
    audio.oncanplay = null
    audio.onerror = null
    audio.pause()
    audio.removeAttribute('src')
    audio.load()
  } catch (_) {
    /* ignore */
  }
}

export function playStream(url, volume = 0.45) {
  if (!url) {
    stopStream()
    return
  }

  const gen = ++playGeneration
  stopInternal()

  const audio = new Audio()
  currentAudio = audio
  audio.volume = volume
  audio.preload = 'auto'

  audio.onerror = () => {
    if (gen !== playGeneration || currentAudio !== audio) return
    console.error('[nyn_carradio] Stream error:', url)
    window.dispatchEvent(new CustomEvent('nyn-stream-error'))
  }

  const tryPlay = () => {
    if (gen !== playGeneration || currentAudio !== audio) return
    const p = audio.play()
    if (p && typeof p.catch === 'function') {
      p.catch((err) => {
        // Interrupted by a newer play/stop — not a real failure
        if (gen !== playGeneration || currentAudio !== audio) return
        if (err && (err.name === 'AbortError' || /interrupted/i.test(String(err.message)))) {
          return
        }
        console.error('[nyn_carradio] Audio playback error:', err)
      })
    }
  }

  audio.oncanplay = () => {
    audio.oncanplay = null
    tryPlay()
  }

  audio.src = url
  tryPlay()
}

export function stopStream() {
  playGeneration += 1
  stopInternal()
}
