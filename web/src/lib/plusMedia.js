/**
 * Plus media in carradio NUI.
 * Streams prefer Web Audio (optional low-pass muffle). Falls back to plain Audio on CORS fail.
 * YouTube stays xsound-only from Lua.
 */

let ytApiReady = null
let ytPlayer = null
let htmlAudio = null
let currentKind = null
let pendingVolume = 0.8
let muffled = false

/** Web Audio graph for stream LPF */
let audioCtx = null
let mediaSource = null
let filterNode = null
let gainNode = null
let usingWebAudio = false

const MUFFLE_FREQ = 580
const CLEAR_FREQ = 18000
const MUFFLE_VOL_MUL = 0.22

export function preloadYtApi() {
  if (ytApiReady) return ytApiReady
  ytApiReady = new Promise((resolve) => {
    if (window.YT && window.YT.Player) {
      resolve(true)
      return
    }
    const prev = window.onYouTubeIframeAPIReady
    window.onYouTubeIframeAPIReady = () => {
      if (typeof prev === 'function') prev()
      resolve(true)
    }
    if (!document.getElementById('nyn-yt-api')) {
      const tag = document.createElement('script')
      tag.id = 'nyn-yt-api'
      tag.src = 'https://www.youtube.com/iframe_api'
      document.head.appendChild(tag)
    }
    setTimeout(() => resolve(!!(window.YT && window.YT.Player)), 5000)
  })
  return ytApiReady
}

function ensureHost() {
  let host = document.getElementById('nyn-plus-player')
  if (!host) {
    host = document.createElement('div')
    host.id = 'nyn-plus-player'
    host.setAttribute(
      'style',
      [
        'position:fixed',
        'left:-9999px',
        'top:0',
        'width:1px',
        'height:1px',
        'opacity:0',
        'pointer-events:none',
        'overflow:hidden',
        'z-index:-1',
      ].join(';'),
    )
    document.body.appendChild(host)
  }
  return host
}

function teardownWebAudio() {
  try {
    mediaSource?.disconnect()
  } catch (_) {
    /* ignore */
  }
  try {
    filterNode?.disconnect()
  } catch (_) {
    /* ignore */
  }
  try {
    gainNode?.disconnect()
  } catch (_) {
    /* ignore */
  }
  mediaSource = null
  filterNode = null
  gainNode = null
  usingWebAudio = false
  // Keep AudioContext — recreating every play is heavy; close only on full stop
}

function stopHtmlAudio() {
  teardownWebAudio()
  if (!htmlAudio) return
  try {
    htmlAudio.pause()
    htmlAudio.removeAttribute('src')
    htmlAudio.load()
  } catch (_) {
    /* ignore */
  }
  htmlAudio = null
}

function destroyYt() {
  if (ytPlayer) {
    try {
      ytPlayer.stopVideo?.()
      ytPlayer.destroy?.()
    } catch (_) {
      /* ignore */
    }
    ytPlayer = null
  }
  const host = document.getElementById('nyn-plus-player')
  if (host) {
    host.innerHTML = ''
    if (host.parentNode) host.parentNode.removeChild(host)
  }
}

export function stopPlusMedia() {
  currentKind = null
  muffled = false
  stopHtmlAudio()
  destroyYt()
  if (audioCtx) {
    try {
      audioCtx.close()
    } catch (_) {
      /* ignore */
    }
    audioCtx = null
  }
}

function applyMuffleToGraph() {
  if (!filterNode || !gainNode || !audioCtx) return
  const t = audioCtx.currentTime
  if (muffled) {
    filterNode.frequency.setTargetAtTime(MUFFLE_FREQ, t, 0.05)
    gainNode.gain.setTargetAtTime(pendingVolume * MUFFLE_VOL_MUL, t, 0.05)
  } else {
    filterNode.frequency.setTargetAtTime(CLEAR_FREQ, t, 0.05)
    gainNode.gain.setTargetAtTime(pendingVolume, t, 0.05)
  }
}

/** Outside cabin = low-pass + quieter (NUI stream only) */
export function setPlusMuffle(enabled) {
  muffled = !!enabled
  if (usingWebAudio) {
    applyMuffleToGraph()
    return true
  }
  if (currentKind === 'stream' && htmlAudio) {
    htmlAudio.volume = muffled ? pendingVolume * MUFFLE_VOL_MUL : pendingVolume
    return true
  }
  return false
}

export function setPlusVolume(volume) {
  pendingVolume = Math.max(0, Math.min(1, Number(volume) || 0))
  if (currentKind === 'youtube' && ytPlayer) {
    try {
      ytPlayer.setVolume(Math.round(pendingVolume * 100))
      if (pendingVolume <= 0.001) ytPlayer.mute()
      else ytPlayer.unMute()
    } catch (_) {
      /* ignore */
    }
  }
  if (currentKind === 'stream') {
    if (usingWebAudio && gainNode && audioCtx) {
      applyMuffleToGraph()
    } else if (htmlAudio) {
      htmlAudio.volume = muffled ? pendingVolume * MUFFLE_VOL_MUL : pendingVolume
    }
  }
}

export function forceUnmute() {
  if (currentKind === 'youtube' && ytPlayer) {
    try {
      ytPlayer.unMute()
      ytPlayer.setVolume(Math.round(pendingVolume * 100))
      ytPlayer.playVideo()
      return true
    } catch (err) {
      console.error('[nyn_carradio] forceUnmute failed', err)
    }
  }
  if (currentKind === 'stream' && htmlAudio) {
    htmlAudio.muted = false
    if (audioCtx?.state === 'suspended') audioCtx.resume().catch(() => {})
    if (usingWebAudio) applyMuffleToGraph()
    else htmlAudio.volume = muffled ? pendingVolume * MUFFLE_VOL_MUL : pendingVolume
    htmlAudio.play().catch(() => {})
    return true
  }
  return false
}

function ytErrorLabel(code) {
  const map = {
    2: 'invalid param',
    5: 'HTML5 player',
    100: 'not found / private',
    101: 'embedding disabled',
    150: 'embedding disabled',
    153: 'missing referer / client id',
  }
  return map[code] || 'unknown'
}

export async function playPlusYoutube(videoId, volume = 0.8) {
  if (!videoId) return false

  stopHtmlAudio()
  if (ytPlayer) {
    try {
      ytPlayer.stopVideo?.()
      ytPlayer.destroy?.()
    } catch (_) {
      /* ignore */
    }
    ytPlayer = null
  }

  currentKind = 'youtube'
  pendingVolume = Math.max(0, Math.min(1, Number(volume) || 0.8))

  await preloadYtApi()
  if (!(window.YT && window.YT.Player)) {
    console.error('[nyn_carradio] YT API missing')
    destroyYt()
    currentKind = null
    return false
  }

  const host = ensureHost()
  host.innerHTML = ''
  const mount = document.createElement('div')
  mount.id = 'nyn-yt-frame'
  host.appendChild(mount)

  const origin =
    typeof window !== 'undefined' && window.location?.origin
      ? window.location.origin
      : 'https://cfx-nui-nyn_carradio'

  return new Promise((resolve) => {
    let done = false
    const finish = (ok) => {
      if (done) return
      done = true
      if (!ok) {
        destroyYt()
        currentKind = null
      }
      resolve(ok)
    }

    try {
      ytPlayer = new window.YT.Player('nyn-yt-frame', {
        width: 1,
        height: 1,
        videoId,
        host: 'https://www.youtube-nocookie.com',
        playerVars: {
          autoplay: 1,
          mute: 0,
          controls: 0,
          rel: 0,
          playsinline: 1,
          fs: 0,
          enablejsapi: 1,
          origin,
          modestbranding: 1,
        },
        events: {
          onReady: (e) => {
            try {
              e.target.unMute()
              e.target.setVolume(Math.round(pendingVolume * 100))
              e.target.playVideo()
            } catch (_) {
              /* ignore */
            }
          },
          onStateChange: (e) => {
            if (e.data === 1) {
              try {
                e.target.unMute()
                e.target.setVolume(Math.round(pendingVolume * 100))
              } catch (_) {
                /* ignore */
              }
              console.log('[nyn_carradio] YT playing (hidden)', videoId)
              finish(true)
            }
          },
          onError: (e) => {
            console.error(
              '[nyn_carradio] YT error',
              e?.data,
              `(${ytErrorLabel(e?.data)})`,
              videoId,
            )
            finish(false)
          },
        },
      })
    } catch (err) {
      console.error('[nyn_carradio] YT Player create failed', err)
      finish(false)
    }

    setTimeout(() => {
      if (!done) finish(false)
    }, 8000)
  })
}

function playPlainStream(url) {
  const audio = new Audio(url)
  htmlAudio = audio
  audio.volume = muffled ? pendingVolume * MUFFLE_VOL_MUL : pendingVolume
  audio.play().catch((err) => {
    if (err?.name === 'AbortError') return
    console.error('[nyn_carradio] Plus stream error:', err)
  })
  usingWebAudio = false
  console.log('[nyn_carradio] stream plain Audio (no LPF)')
  return true
}

/**
 * Live stream with optional low-pass. Web Audio needs CORS on the stream URL —
 * if that fails we fall back to plain <audio> (volume muffle only).
 */
export function playPlusStream(url, volume = 0.8) {
  if (!url) return false
  stopPlusMedia()
  currentKind = 'stream'
  pendingVolume = Math.max(0, Math.min(1, Number(volume) || 0.8))
  muffled = false

  const audio = new Audio()
  audio.crossOrigin = 'anonymous'
  audio.preload = 'auto'
  htmlAudio = audio

  try {
    if (!audioCtx || audioCtx.state === 'closed') {
      audioCtx = new (window.AudioContext || window.webkitAudioContext)()
    }
    mediaSource = audioCtx.createMediaElementSource(audio)
    filterNode = audioCtx.createBiquadFilter()
    filterNode.type = 'lowpass'
    filterNode.Q.value = 0.7
    filterNode.frequency.value = CLEAR_FREQ
    gainNode = audioCtx.createGain()
    gainNode.gain.value = pendingVolume
    mediaSource.connect(filterNode)
    filterNode.connect(gainNode)
    gainNode.connect(audioCtx.destination)
    usingWebAudio = true
    console.log('[nyn_carradio] stream Web Audio + LPF ready')
  } catch (err) {
    console.warn('[nyn_carradio] Web Audio graph failed, plain Audio:', err)
    teardownWebAudio()
    htmlAudio = null
    return playPlainStream(url)
  }

  audio.src = url
  const playPromise = audio.play()
  if (playPromise && typeof playPromise.catch === 'function') {
    playPromise.catch((err) => {
      if (err?.name === 'AbortError') return
      // CORS / autoplay — rebuild as plain element
      console.warn('[nyn_carradio] Web Audio play failed, plain fallback:', err?.message || err)
      const resumeUrl = url
      const vol = pendingVolume
      stopHtmlAudio()
      currentKind = 'stream'
      pendingVolume = vol
      playPlainStream(resumeUrl)
    })
  }

  if (audioCtx?.state === 'suspended') {
    audioCtx.resume().catch(() => {})
  }

  return true
}

export function extractYoutubeId(url) {
  if (!url || typeof url !== 'string') return null
  const patterns = [
    /youtu\.be\/([a-zA-Z0-9_-]{6,})/,
    /[?&]v=([a-zA-Z0-9_-]{6,})/,
    /shorts\/([a-zA-Z0-9_-]{6,})/,
    /embed\/([a-zA-Z0-9_-]{6,})/,
    /live\/([a-zA-Z0-9_-]{6,})/,
  ]
  for (const re of patterns) {
    const m = url.match(re)
    if (m?.[1]) return m[1]
  }
  return null
}
