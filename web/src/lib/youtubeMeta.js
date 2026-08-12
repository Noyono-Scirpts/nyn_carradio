/**
 * YouTube metadata helpers.
 * Thumbnail needs no network (ytimg).
 * Title: try noembed/oEmbed in NUI, then server (FiveM NUI often blocks YouTube).
 */

import { nuiCallback } from './nui.js'

const GENERIC_TITLES = new Set(['youtube', 'live radio', 'playlist', ''])
const memoryCache = new Map()

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

export function youtubeThumb(urlOrId, quality = 'hqdefault') {
  const id =
    urlOrId && urlOrId.length <= 20 && !urlOrId.includes('/')
      ? urlOrId
      : extractYoutubeId(urlOrId)
  if (!id) return ''
  return `https://i.ytimg.com/vi/${id}/${quality}.jpg`
}

export function isGenericTitle(title) {
  return GENERIC_TITLES.has(String(title || '').trim().toLowerCase())
}

async function fetchJson(url, timeoutMs = 3500) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)
  try {
    const res = await fetch(url, {
      signal: controller.signal,
      headers: { Accept: 'application/json' },
    })
    if (!res.ok) return null
    return await res.json()
  } catch (_) {
    return null
  } finally {
    clearTimeout(timer)
  }
}

async function fetchViaBrowser(videoId) {
  const watchUrl = `https://www.youtube.com/watch?v=${videoId}`
  const encoded = encodeURIComponent(watchUrl)
  const endpoints = [
    `https://noembed.com/embed?url=${encoded}`,
    `https://www.youtube.com/oembed?url=${encoded}&format=json`,
  ]

  for (const endpoint of endpoints) {
    const data = await fetchJson(endpoint)
    if (data?.title && typeof data.title === 'string' && data.title.trim()) {
      return {
        title: data.title.trim(),
        thumbnail:
          typeof data.thumbnail_url === 'string'
            ? data.thumbnail_url
            : youtubeThumb(videoId),
        videoId,
      }
    }
  }
  return null
}

async function fetchViaServer(url) {
  try {
    const res = await nuiCallback('extensionResolveMeta', { urls: [url] })
    if (!res?.ok || !res.results) return null
    const id = extractYoutubeId(url)
    const hit = res.results[url] || (id && res.results[id]) || null
    if (hit?.title && !isGenericTitle(hit.title)) {
      return {
        title: hit.title,
        thumbnail: hit.thumbnail || youtubeThumb(url),
        videoId: id,
      }
    }
  } catch (_) {
    /* ignore */
  }
  return null
}

/**
 * @returns {Promise<{ title: string, thumbnail: string, videoId: string } | null>}
 */
export async function fetchYoutubeMeta(url) {
  const videoId = extractYoutubeId(url)
  if (!videoId) return null

  if (memoryCache.has(videoId)) {
    return memoryCache.get(videoId)
  }

  const thumbnail = youtubeThumb(videoId)
  let meta = await fetchViaBrowser(videoId)
  if (!meta || isGenericTitle(meta.title)) {
    meta = await fetchViaServer(url)
  }

  const result = meta && !isGenericTitle(meta.title)
    ? {
        title: meta.title,
        thumbnail: meta.thumbnail || thumbnail,
        videoId,
      }
    : { title: 'YouTube', thumbnail, videoId }

  if (!isGenericTitle(result.title)) {
    memoryCache.set(videoId, result)
  }
  return result
}

/**
 * Resolve many URLs (playlist / queue). Returns Map-like object keyed by url + videoId.
 */
export async function fetchYoutubeMetaBatch(urls) {
  const list = Array.from(new Set((urls || []).filter((u) => typeof u === 'string' && u)))
  const out = {}
  const needServer = []

  await Promise.all(
    list.map(async (url) => {
      const id = extractYoutubeId(url)
      if (!id) return
      if (memoryCache.has(id)) {
        const cached = memoryCache.get(id)
        out[url] = cached
        out[id] = cached
        return
      }
      const browser = await fetchViaBrowser(id)
      if (browser && !isGenericTitle(browser.title)) {
        memoryCache.set(id, browser)
        out[url] = browser
        out[id] = browser
        return
      }
      needServer.push(url)
    }),
  )

  if (needServer.length) {
    try {
      const res = await nuiCallback('extensionResolveMeta', { urls: needServer })
      const results = res?.results || {}
      for (const url of needServer) {
        const id = extractYoutubeId(url)
        const hit = results[url] || (id && results[id])
        if (hit?.title && !isGenericTitle(hit.title)) {
          const meta = {
            title: hit.title,
            thumbnail: hit.thumbnail || youtubeThumb(url),
            videoId: id,
          }
          if (id) memoryCache.set(id, meta)
          out[url] = meta
          if (id) out[id] = meta
        }
      }
    } catch (_) {
      /* ignore */
    }
  }

  return out
}
