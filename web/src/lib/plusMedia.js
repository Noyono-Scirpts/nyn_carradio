/**
 * Plus media in carradio NUI.
 * YouTube iframe is always hidden (audio-only). Prefer xsound from Lua for YT.
 */

let ytApiReady = null
let ytPlayer = null
let htmlAudio = null
let currentKind = null
let pendingVolume = 0.8

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

/** Hidden host — never show the YouTube embed on screen */
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

function stopHtmlAudio() {
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
  stopHtmlAudio()
  destroyYt()
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
  if (currentKind === 'stream' && htmlAudio) {
    htmlAudio.volume = pendingVolume
  }
}

/** Call from Unmute button / click — has user gesture */
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
    htmlAudio.volume = pendingVolume
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

/** Hidden YT attempt (used by plusPlay from Lua). Prefer xsound for YouTube. */
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

export function playPlusStream(url, volume = 0.8) {
  if (!url) return false
  stopPlusMedia()
  currentKind = 'stream'
  pendingVolume = Math.max(0, Math.min(1, Number(volume) || 0.8))
  const audio = new Audio(url)
  htmlAudio = audio
  audio.volume = pendingVolume
  audio.play().catch((err) => {
    if (err?.name === 'AbortError') return
    console.error('[nyn_carradio] Plus stream error:', err)
  })
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
