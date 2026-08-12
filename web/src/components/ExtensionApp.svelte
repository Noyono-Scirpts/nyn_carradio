<script>
  import { onMount } from 'svelte'
  import { X, Play, LoaderCircle, ListPlus, SkipForward } from '@lucide/svelte'
  import { nuiCallback, onNuiMessage } from '../lib/nui.js'
  import {
    stopPlusMedia,
    setPlusVolume,
  } from '../lib/plusMedia.js'
  import {
    fetchYoutubeMeta,
    fetchYoutubeMetaBatch,
    youtubeThumb,
    isGenericTitle,
  } from '../lib/youtubeMeta.js'
  import '../styles/extension.css'

  let visible = $state(false)
  let mountedVisible = $state(false)
  let tab = $state('stations')
  let urlInput = $state('')
  let busy = $state(false)
  let statusMsg = $state('')
  let extension = $state({
    available: false,
    xsound: false,
    features: {},
    maxVolume: 1,
    defaultVolume: 1,
    stations: [],
    playlistLimits: { maxPlaylists: 10, maxTracks: 10 },
  })
  let playback = $state(null)
  let localVolume = $state(100)
  let volumeTimer = null
  let activeStationUrl = $state('')

  let playlists = $state([])
  let selectedPlaylist = $state(null)
  let newPlaylistName = $state('')
  let trackUrlInput = $state('')
  let showPlaylistPicker = $state(false)
  let renamingId = $state(null)
  let renameInput = $state('')

  let locales = $state({
    plus_tab_stations: 'Stations',
    plus_tab_playlists: 'Playlists',
    plus_tab_now: 'Now playing',
    plus_tab_search: 'URL',
    plus_status_paused: 'Paused',
    plus_status_playing: 'Playing',
    plus_status_idle: 'Idle',
    plus_missing_title: 'nyn_carradio_plus missing',
    plus_missing_body: 'Add the resource to your server and ensure it. Base Q radio works without Plus.',
    plus_no_stations_title: 'No stations',
    plus_no_stations_body: 'Add them in nyn_carradio_plus/shared/config.lua → Config.Stations.',
    plus_station: 'Station',
    plus_live_stream: 'Live stream',
    plus_back: '← Back',
    plus_tracks_count: '%s/%s tracks',
    plus_play: 'Play',
    plus_remove: 'Remove',
    plus_no_tracks: 'No tracks — add a YouTube URL.',
    plus_add: 'Add',
    plus_playlist_name_ph: 'Playlist name',
    plus_new: 'New',
    plus_playlists_count: '%s/%s playlists',
    plus_tracks_n: '%s tracks',
    plus_open: 'Open',
    plus_delete: 'Delete',
    plus_rename: 'Rename',
    plus_duplicate: 'Duplicate',
    plus_save: 'Save',
    plus_cancel: 'Cancel',
    plus_renamed: 'Playlist renamed.',
    plus_duplicated: 'Playlist duplicated.',
    plus_copy_suffix: '%s (copy)',
    plus_no_playlists: 'No playlists yet.',
    plus_nothing: 'Nothing playing',
    plus_pick_hint: 'Pick a station or paste a URL.',
    plus_volume: 'Volume',
    plus_resume: 'Resume',
    plus_pause: 'Pause',
    plus_stop: 'Stop',
    plus_skip: 'Skip',
    plus_queue: 'Queue',
    plus_queued: 'Added to queue (%s)',
    plus_queue_hint: '%s / %s in queue',
    plus_queue_now: 'Now',
    plus_queue_next: 'Up next',
    plus_queue_empty: 'Queue is empty — paste a YouTube link and hit Queue.',
    plus_url_ph: 'YouTube / https://…/stream.mp3',
    plus_need_url: 'Enter a YouTube or live stream URL.',
    plus_playing: 'Playing…',
    plus_err_limit_playlists: 'Playlist limit reached.',
    plus_err_limit_tracks: 'Track limit reached for this playlist.',
    plus_err_invalid_url: 'YouTube links only.',
    plus_err_empty: 'Playlist is empty.',
    plus_err_no_db: 'Database unavailable (oxmysql).',
    plus_err_forbidden: 'You cannot access this playlist.',
    plus_err_disabled: 'Playlists are disabled.',
    plus_err_timeout: 'Timed out — try again.',
    plus_err_not_in_vehicle: 'You must be in a vehicle.',
    plus_err_missing_extension: 'nyn_carradio_plus is missing.',
    plus_err_load_failed: 'Failed to load playlist.',
    plus_err_play_failed: 'Could not play playlist.',
    plus_err_failed: 'Operation failed.',
    plus_err_no_xsound: 'Cannot play — xsound is not running.',
    plus_err_no_carradio: 'nyn_carradio is not running.',
    plus_err_play_video: 'Could not play media.',
    plus_add_to_playlist: 'Add to playlist',
    plus_pick_playlist: 'Save to…',
    plus_saved_to_playlist: 'Added to %s',
    plus_streams_no_playlist: 'Only YouTube links can be saved to playlists.',
    plus_create_playlist_first: 'Create a playlist first.',
  })

  const playlistsEnabled = $derived(!!extension.features?.playlists)
  const tabs = $derived.by(() => {
    const list = [{ id: 'stations', label: locales.plus_tab_stations }]
    if (playlistsEnabled) list.push({ id: 'playlists', label: locales.plus_tab_playlists })
    list.push({ id: 'now', label: locales.plus_tab_now })
    return list
  })

  const tabTitle = $derived(tabs.find((t) => t.id === tab)?.label || 'Plus')
  const hasPlus = $derived(!!extension.available)
  const canPlay = $derived(hasPlus)
  const stations = $derived(Array.isArray(extension.stations) ? extension.stations : [])
  const maxVolumePct = $derived(Math.round((extension.maxVolume ?? 1) * 100))
  const volumeFill = $derived(
    Math.min(100, Math.max(0, (localVolume / Math.max(maxVolumePct, 1)) * 100)),
  )
  const playingLabel = $derived(
    playback?.paused
      ? locales.plus_status_paused
      : playback?.playing
        ? locales.plus_status_playing
        : locales.plus_status_idle,
  )
  const isLive = $derived(!!playback?.playing && !playback?.paused)
  const maxPlaylists = $derived(extension.playlistLimits?.maxPlaylists ?? 10)
  const maxTracks = $derived(extension.playlistLimits?.maxTracks ?? 10)
  const atPlaylistLimit = $derived(playlists.length >= maxPlaylists)
  const selectedTracks = $derived(
    Array.isArray(selectedPlaylist?.tracks) ? selectedPlaylist.tracks : [],
  )
  const atTrackLimit = $derived(selectedTracks.length >= maxTracks)
  const saveableUrl = $derived((playback?.url || urlInput || '').trim())
  const canSaveToPlaylist = $derived(playlistsEnabled && !!saveableUrl && isYoutubeUrl(saveableUrl))
  const queueTracks = $derived(
    Array.isArray(playback?.playlist?.tracks) ? playback.playlist.tracks : [],
  )
  const queueIndex = $derived(Math.max(1, Number(playback?.playlist?.index) || 1))
  const queueTotal = $derived(queueTracks.length)
  const canSkip = $derived(queueTotal > 0 && queueIndex < queueTotal)
  const canQueueUrl = $derived(!!urlInput.trim() && isYoutubeUrl(urlInput.trim()))

  function fmt(template, ...args) {
    let i = 0
    return String(template || '').replace(/%s/g, () => String(args[i++] ?? ''))
  }

  function detectTitle(url) {
    if (/youtu\.?be/i.test(url)) return 'YouTube'
    return 'Live Radio'
  }

  async function resolvePlayMeta(url, fallbackTitle) {
    const trimmed = (url || '').trim()
    if (!isYoutubeUrl(trimmed)) {
      return {
        title: fallbackTitle || detectTitle(trimmed),
        thumbnail: '',
      }
    }
    const meta = await fetchYoutubeMeta(trimmed)
    return {
      title:
        meta?.title && !isGenericTitle(meta.title)
          ? meta.title
          : fallbackTitle && !isGenericTitle(fallbackTitle)
            ? fallbackTitle
            : meta?.title || fallbackTitle || 'YouTube',
      thumbnail: meta?.thumbnail || youtubeThumb(trimmed) || '',
    }
  }

  function trackArt(url, thumb) {
    if (thumb) return thumb
    return youtubeThumb(url) || ''
  }

  /** Soft enrich generic titles after sync — never blocks playback. */
  async function enrichPlaybackMeta(state) {
    if (!state?.url || !isYoutubeUrl(state.url)) return
    if (state.title && !isGenericTitle(state.title) && state.thumbnail) {
      await enrichPlaylistLikeTracks(state)
      return
    }
    const meta = await fetchYoutubeMeta(state.url)
    if (!meta) return
    // Only patch if still same URL
    if (playback?.url !== state.url) return
    playback = {
      ...playback,
      title:
        isGenericTitle(playback.title) && meta.title && !isGenericTitle(meta.title)
          ? meta.title
          : playback.title || meta.title,
      thumbnail: playback.thumbnail || meta.thumbnail,
    }
    await enrichPlaylistLikeTracks(playback)
  }

  async function enrichPlaylistLikeTracks(state) {
    const tracks = state?.playlist?.tracks
    if (!Array.isArray(tracks) || !tracks.length) return
    const need = tracks.filter((t) => t?.url && isGenericTitle(t.title)).map((t) => t.url)
    if (!need.length) return
    const results = await fetchYoutubeMetaBatch(need)
    if (playback?.url !== state.url && playback?.playlist !== state.playlist) {
      // still apply if same playlist object on current playback
    }
    if (!playback?.playlist?.tracks) return
    let changed = false
    const nextTracks = playback.playlist.tracks.map((t) => {
      const hit = results[t.url]
      if (hit?.title && isGenericTitle(t.title) && !isGenericTitle(hit.title)) {
        changed = true
        return { ...t, title: hit.title }
      }
      return t
    })
    if (changed) {
      playback = {
        ...playback,
        playlist: { ...playback.playlist, tracks: nextTracks },
      }
    }
  }

  async function enrichSelectedPlaylistTracks(tracks) {
    if (!Array.isArray(tracks) || !tracks.length || !selectedPlaylist) return
    const need = tracks.filter((t) => t?.url && isGenericTitle(t.title)).map((t) => t.url)
    if (!need.length) return
    const results = await fetchYoutubeMetaBatch(need)
    if (!selectedPlaylist) return
    let changed = false
    const nextTracks = (selectedPlaylist.tracks || []).map((t) => {
      const hit = results[t.url]
      if (hit?.title && isGenericTitle(t.title) && !isGenericTitle(hit.title)) {
        changed = true
        return { ...t, title: hit.title }
      }
      return t
    })
    if (changed) {
      selectedPlaylist = { ...selectedPlaylist, tracks: nextTracks }
    }
  }

  function isYoutubeUrl(url) {
    return /youtu\.?be/i.test(url || '')
  }

  function truncateUrl(url, max = 44) {
    const s = String(url || '')
    if (s.length <= max) return s
    return `${s.slice(0, max - 1)}…`
  }

  function playlistError(error) {
    const map = {
      limit_playlists: locales.plus_err_limit_playlists,
      limit_tracks: locales.plus_err_limit_tracks,
      invalid_url: locales.plus_err_invalid_url,
      empty: locales.plus_err_empty,
      no_db: locales.plus_err_no_db,
      forbidden: locales.plus_err_forbidden,
      disabled: locales.plus_err_disabled,
      timeout: locales.plus_err_timeout,
      not_in_vehicle: locales.plus_err_not_in_vehicle,
      missing_extension: locales.plus_err_missing_extension,
      load_failed: locales.plus_err_load_failed,
      play_failed: locales.plus_err_play_failed,
    }
    return map[error] || locales.plus_err_failed
  }

  function applyPlaylistLimits(limits) {
    if (!limits) return
    extension = {
      ...extension,
      playlistLimits: {
        maxPlaylists: limits.maxPlaylists ?? 10,
        maxTracks: limits.maxTracks ?? 10,
      },
    }
  }

  async function refreshPlaylists() {
    if (!playlistsEnabled) return
    const res = await nuiCallback('extensionPlaylist', { action: 'list', payload: {} })
    if (res?.ok) {
      playlists = Array.isArray(res.playlists) ? res.playlists : []
      applyPlaylistLimits(res.limits)
    } else if (res?.error) {
      statusMsg = playlistError(res.error)
    }
  }

  async function selectTab(id) {
    tab = id
    showPlaylistPicker = false
    if ((id === 'playlists' || id === 'now') && playlistsEnabled) {
      await refreshPlaylists()
    }
  }

  function open(payload = {}) {
    if (payload.locales) {
      locales = { ...locales, ...payload.locales }
    }
    if (payload.extension) {
      extension = {
        ...extension,
        ...payload.extension,
        stations: payload.extension.stations || extension.stations || [],
        playlistLimits: payload.extension.playlistLimits || extension.playlistLimits || {
          maxPlaylists: 10,
          maxTracks: 10,
        },
      }
      const def = payload.extension.defaultVolume ?? 1
      if (typeof def === 'number') localVolume = Math.round(def * 100)
    }
    if (payload.state) {
      playback = {
        ...payload.state,
        thumbnail:
          payload.state.thumbnail ||
          (isYoutubeUrl(payload.state.url) ? youtubeThumb(payload.state.url) : '') ||
          '',
      }
      if (payload.state.url) {
        urlInput = payload.state.url
        activeStationUrl = payload.state.url
      }
      if (typeof payload.state.volume === 'number') {
        localVolume = Math.round(payload.state.volume * 100)
      }
      enrichPlaybackMeta(playback)
    }
    tab = payload.tab || (stations.length ? 'stations' : 'now')
    visible = true
    requestAnimationFrame(() => {
      mountedVisible = true
    })
    if (payload.extension?.features?.playlists) {
      refreshPlaylists()
    }
  }

  function close() {
    mountedVisible = false
    setTimeout(() => {
      visible = false
      nuiCallback('closeExtension')
    }, 220)
  }

  async function startPlay(url, title) {
    if (!canPlay || busy) return
    url = (url || '').trim()
    if (!url) {
      statusMsg = locales.plus_need_url
      return
    }

    const meta = await resolvePlayMeta(url, title)
    const resolvedTitle = meta.title
    const volume = localVolume / 100

    // Always xsound from Lua — starting NUI here caused duplicate (NUI + PlayUrlPos)
    stopPlusMedia()

    busy = true
    statusMsg = ''
    const res = await nuiCallback('extensionPlay', {
      url,
      title: resolvedTitle,
      thumbnail: meta.thumbnail || undefined,
      volume,
      clientPlaying: false,
    })
    busy = false

    if (res?.ok) {
      playback = {
        url,
        title: resolvedTitle,
        thumbnail: meta.thumbnail || '',
        playing: true,
        paused: false,
        volume,
      }
      activeStationUrl = url
      urlInput = url
      tab = 'now'
      statusMsg = locales.plus_playing
    } else {
      stopPlusMedia()
      const map = {
        missing_extension: locales.plus_err_missing_extension,
        not_in_vehicle: locales.plus_err_not_in_vehicle,
        invalid_url: locales.plus_err_invalid_url,
        no_xsound: locales.plus_err_no_xsound,
        play_failed: locales.plus_err_play_failed,
        no_carradio: locales.plus_err_no_carradio,
      }
      statusMsg = map[res?.error] || locales.plus_err_play_video
    }
  }

  async function playUrl() {
    await startPlay(urlInput, detectTitle(urlInput.trim()))
  }

  async function queueUrl() {
    if (!canPlay || busy) return
    const url = (urlInput || '').trim()
    if (!url) {
      statusMsg = locales.plus_need_url
      return
    }
    if (!isYoutubeUrl(url)) {
      statusMsg = playlistError('invalid_url')
      return
    }

    const meta = await resolvePlayMeta(url)
    const title = meta.title
    const volume = localVolume / 100
    busy = true
    statusMsg = ''
    const res = await nuiCallback('extensionQueue', {
      url,
      title,
      thumbnail: meta.thumbnail || undefined,
      volume,
    })
    busy = false

    if (res?.ok) {
      tab = 'now'
      const total = (playback?.playlist?.tracks?.length || 0) + (playback?.playlist ? 1 : 1)
      statusMsg = fmt(locales.plus_queued, String(total))
      // Optimistic: extensionState sync will refresh exact playlist
      if (!playback) {
        playback = {
          url,
          title,
          thumbnail: meta.thumbnail || '',
          playing: true,
          paused: false,
          volume,
          playlist: { name: 'Queue', index: 1, tracks: [{ url, title }] },
        }
      }
    } else {
      statusMsg = playlistError(res?.error) || locales.plus_err_play_failed
    }
  }

  async function skipTrack() {
    if (!canPlay || busy || !canSkip) return
    busy = true
    statusMsg = ''
    const res = await nuiCallback('extensionSkip')
    busy = false
    if (!res?.ok) {
      statusMsg = playlistError(res?.error) || locales.plus_err_failed
    }
  }

  async function playStation(station) {
    if (!station?.url) return
    await startPlay(station.url, station.name || detectTitle(station.url))
  }

  async function openPlaylist(id) {
    if (busy || !id) return
    busy = true
    statusMsg = ''
    const res = await nuiCallback('extensionPlaylist', { action: 'get', payload: { id } })
    busy = false
    if (res?.ok && res.playlist) {
      selectedPlaylist = res.playlist
      applyPlaylistLimits(res.limits)
      trackUrlInput = ''
      enrichSelectedPlaylistTracks(res.playlist.tracks)
    } else {
      statusMsg = playlistError(res?.error)
    }
  }

  function backToPlaylistList() {
    selectedPlaylist = null
    trackUrlInput = ''
    refreshPlaylists()
  }

  async function createPlaylist() {
    if (busy || atPlaylistLimit) return
    const name = (newPlaylistName || '').trim() || 'Playlist'
    busy = true
    statusMsg = ''
    const res = await nuiCallback('extensionPlaylist', { action: 'create', payload: { name } })
    busy = false
    if (res?.ok) {
      newPlaylistName = ''
      if (Array.isArray(res.playlists)) playlists = res.playlists
      else await refreshPlaylists()
    } else {
      statusMsg = playlistError(res?.error)
    }
  }

  async function deletePlaylist(id) {
    if (busy || !id) return
    busy = true
    statusMsg = ''
    const res = await nuiCallback('extensionPlaylist', { action: 'delete', payload: { id } })
    busy = false
    if (res?.ok) {
      if (selectedPlaylist?.id === id) selectedPlaylist = null
      if (renamingId === id) {
        renamingId = null
        renameInput = ''
      }
      if (Array.isArray(res.playlists)) playlists = res.playlists
      else await refreshPlaylists()
    } else {
      statusMsg = playlistError(res?.error)
    }
  }

  function startRename(pl) {
    if (!pl?.id || busy) return
    renamingId = pl.id
    renameInput = pl.name || ''
  }

  function cancelRename() {
    renamingId = null
    renameInput = ''
  }

  async function saveRename(id) {
    if (busy || !id) return
    const name = (renameInput || '').trim()
    if (!name) {
      statusMsg = locales.plus_playlist_name_ph
      return
    }
    busy = true
    statusMsg = ''
    const res = await nuiCallback('extensionPlaylist', {
      action: 'rename',
      payload: { id, name },
    })
    busy = false
    if (res?.ok) {
      renamingId = null
      renameInput = ''
      if (Array.isArray(res.playlists)) playlists = res.playlists
      else await refreshPlaylists()
      if (selectedPlaylist?.id === id) {
        selectedPlaylist = { ...selectedPlaylist, name }
      }
      statusMsg = locales.plus_renamed
    } else {
      statusMsg = playlistError(res?.error)
    }
  }

  async function duplicatePlaylist(id, name) {
    if (busy || !id || atPlaylistLimit) return
    busy = true
    statusMsg = ''
    const res = await nuiCallback('extensionPlaylist', {
      action: 'duplicate',
      payload: {
        id,
        name: fmt(locales.plus_copy_suffix, name || 'Playlist'),
      },
    })
    busy = false
    if (res?.ok) {
      if (Array.isArray(res.playlists)) playlists = res.playlists
      else await refreshPlaylists()
      statusMsg = locales.plus_duplicated
    } else {
      statusMsg = playlistError(res?.error)
    }
  }

  async function addTrack() {
    if (!selectedPlaylist || busy || atTrackLimit) return
    const url = (trackUrlInput || '').trim()
    if (!url || !isYoutubeUrl(url)) {
      statusMsg = playlistError('invalid_url')
      return
    }
    await addUrlToPlaylist(selectedPlaylist.id, url, (await resolvePlayMeta(url)).title)
    trackUrlInput = ''
  }

  async function addUrlToPlaylist(playlistId, url, title) {
    if (!playlistId || busy || !url || !isYoutubeUrl(url)) {
      statusMsg = playlistError('invalid_url')
      return false
    }

    busy = true
    statusMsg = ''
    const res = await nuiCallback('extensionPlaylist', {
      action: 'addTrack',
      payload: {
        playlistId,
        url,
        title: title || detectTitle(url),
      },
    })
    busy = false

    if (res?.ok) {
      const pl = playlists.find((p) => p.id === playlistId)
      statusMsg = fmt(locales.plus_saved_to_playlist, pl?.name || 'Playlist')
      showPlaylistPicker = false
      if (selectedPlaylist?.id === playlistId && Array.isArray(res.tracks)) {
        selectedPlaylist = { ...selectedPlaylist, tracks: res.tracks }
      }
      if (Array.isArray(res.playlists)) playlists = res.playlists
      else await refreshPlaylists()
      return true
    }

    statusMsg = playlistError(res?.error)
    return false
  }

  function togglePlaylistPicker() {
    if (!canSaveToPlaylist) {
      statusMsg = locales.plus_streams_no_playlist
      return
    }
    if (!playlists.length) {
      statusMsg = locales.plus_create_playlist_first
      return
    }
    showPlaylistPicker = !showPlaylistPicker
  }

  async function quickAddToPlaylist(playlistId) {
    const url = saveableUrl
    const title = playback?.title || detectTitle(url)
    await addUrlToPlaylist(playlistId, url, title)
  }

  function onUrlKeydown(event) {
    if (event.key === 'Enter') {
      event.preventDefault()
      playUrl()
    }
  }

  async function removeTrack(trackId) {
    if (!selectedPlaylist || busy || !trackId) return
    busy = true
    statusMsg = ''
    const res = await nuiCallback('extensionPlaylist', {
      action: 'removeTrack',
      payload: { playlistId: selectedPlaylist.id, trackId },
    })
    busy = false
    if (res?.ok) {
      if (Array.isArray(res.tracks)) {
        selectedPlaylist = { ...selectedPlaylist, tracks: res.tracks }
      } else {
        await openPlaylist(selectedPlaylist.id)
      }
      if (Array.isArray(res.playlists)) playlists = res.playlists
    } else {
      statusMsg = playlistError(res?.error)
    }
  }

  async function playPlaylist(id) {
    if (!canPlay || busy || !id) return
    const volume = localVolume / 100
    stopPlusMedia()
    busy = true
    statusMsg = ''
    const res = await nuiCallback('extensionPlayPlaylist', { id, volume })
    busy = false

    if (res?.ok) {
      const detail = selectedPlaylist?.id === id ? selectedPlaylist : null
      const first = detail?.tracks?.[0]
      const meta = playlists.find((p) => p.id === id)
      const title = first?.title || detail?.name || meta?.name || 'Playlist'
      const url = first?.url || ''
      const tracks = Array.isArray(detail?.tracks)
        ? detail.tracks.map((t) => ({ url: t.url, title: t.title || 'YouTube' }))
        : url
          ? [{ url, title }]
          : []
      playback = {
        url,
        title,
        playing: true,
        paused: false,
        volume,
        playlist: tracks.length
          ? { id, name: detail?.name || meta?.name || 'Playlist', index: 1, tracks }
          : undefined,
      }
      if (url) {
        activeStationUrl = url
        urlInput = url
      }
      tab = 'now'
      statusMsg = locales.plus_playing
    } else {
      stopPlusMedia()
      statusMsg = playlistError(res?.error)
    }
  }

  async function pauseTrack() {
    await nuiCallback('extensionPause')
    if (playback) playback = { ...playback, playing: false, paused: true }
  }

  async function resumeTrack() {
    await nuiCallback('extensionResume')
    if (playback) playback = { ...playback, playing: true, paused: false }
  }

  async function stopTrack() {
    stopPlusMedia()
    await nuiCallback('extensionStop')
    playback = null
    activeStationUrl = ''
  }

  function onVolumeInput(e) {
    localVolume = Number(e.currentTarget.value)
    setPlusVolume(localVolume / 100)
    clearTimeout(volumeTimer)
    volumeTimer = setTimeout(() => {
      nuiCallback('extensionSetVolume', { volume: localVolume / 100 })
    }, 120)
  }

  function stationInitial(name) {
    const t = (name || '?').trim()
    return t.slice(0, 2).toUpperCase()
  }

  onMount(() => {
    const off = onNuiMessage((data) => {
      if (data.action === 'init' && data.locales) {
        locales = { ...locales, ...data.locales }
      } else if (data.action === 'openExtension') {
        open(data)
      } else if (data.action === 'closeExtension') {
        mountedVisible = false
        setTimeout(() => {
          visible = false
        }, 220)
      } else if (data.action === 'playlistTracksEnriched') {
        if (
          selectedPlaylist?.id === data.playlistId &&
          Array.isArray(data.tracks)
        ) {
          selectedPlaylist = { ...selectedPlaylist, tracks: data.tracks }
        }
      } else if (data.action === 'extensionState') {
        // Shared track sync for passengers (and live updates while UI open)
        if (data.state) {
          const next = {
            ...data.state,
            thumbnail:
              data.state.thumbnail ||
              (isYoutubeUrl(data.state.url) ? youtubeThumb(data.state.url) : '') ||
              '',
          }
          playback = next
          if (data.state.url) {
            urlInput = data.state.url
            activeStationUrl = data.state.url
          }
          if (typeof data.state.volume === 'number') {
            localVolume = Math.round(data.state.volume * 100)
          }
          enrichPlaybackMeta(next)
        } else {
          playback = null
          activeStationUrl = ''
        }
      }
    })

    const onKey = (event) => {
      if (event.key === 'Escape' && visible) close()
    }
    window.addEventListener('keyup', onKey)

    return () => {
      off()
      window.removeEventListener('keyup', onKey)
      clearTimeout(volumeTimer)
    }
  })
</script>

{#if visible}
  <div class="ext-root" class:visible={mountedVisible}>
    <div class="ext-shell" aria-label={tabTitle}>
      <header class="ext-header">
        <div class="ext-brand">
          <span class="ext-brand-label">
            <span class="ext-brand-nyn">NYN</span>
            <span class="ext-brand-plus">PLUS</span>
          </span>
          <span class="ext-brand-title">Car Radio+</span>
        </div>

        <nav class="ext-tabs" aria-label="Plus tabs">
          {#each tabs as item (item.id)}
            <button
              type="button"
              class="ext-tab"
              class:active={tab === item.id}
              onclick={() => selectTab(item.id)}
            >
              {item.label}
            </button>
          {/each}
        </nav>

        <div class="ext-header-end">
          <div class="ext-live" title={playingLabel}>
            <span class="ext-dot" class:on={isLive}></span>
            <span class="ext-live-label">{playingLabel}</span>
          </div>
          <button type="button" class="ext-close" onclick={close} aria-label="Close">
            <X size={18} strokeWidth={2.2} />
          </button>
        </div>
      </header>

      <div class="ext-body">
        {#key tab}
          <div class="ext-pane">
            {#if !hasPlus}
              <div class="ext-empty">
                <h3>{locales.plus_missing_title}</h3>
                <p>{locales.plus_missing_body}</p>
              </div>
            {:else if tab === 'stations'}
              {#if stations.length === 0}
                <div class="ext-empty">
                  <h3>{locales.plus_no_stations_title}</h3>
                  <p>{locales.plus_no_stations_body}</p>
                </div>
              {:else}
                <div class="ext-station-list">
                  {#each stations as station (station.url)}
                    <button
                      type="button"
                      class="ext-station"
                      class:active={activeStationUrl === station.url && playback?.playing}
                      disabled={!canPlay || busy}
                      onclick={() => playStation(station)}
                    >
                      {#if station.image}
                        <img class="ext-station-art" src={station.image} alt="" />
                      {:else}
                        <div class="ext-station-art fallback">{stationInitial(station.name)}</div>
                      {/if}
                      <div class="ext-station-meta">
                        <strong>{station.name || locales.plus_station}</strong>
                        <span>{station.type === 'youtube' ? 'YouTube' : locales.plus_live_stream}</span>
                      </div>
                      <span class="ext-station-play">
                        {#if busy && activeStationUrl === station.url}
                          <LoaderCircle size={14} strokeWidth={2.2} class="ext-spin-icon" />
                        {:else}
                          <Play size={14} strokeWidth={2.2} />
                        {/if}
                      </span>
                    </button>
                  {/each}
                </div>
              {/if}
              {#if statusMsg}
                <p class="ext-status">{statusMsg}</p>
              {/if}
            {:else if tab === 'playlists' && playlistsEnabled}
              <div class="ext-playlists">
                {#if selectedPlaylist}
                  <div class="ext-pl-detail-head">
                    <button
                      type="button"
                      class="ext-btn"
                      onclick={backToPlaylistList}
                      disabled={busy}
                    >
                      {locales.plus_back}
                    </button>
                    <div class="ext-pl-detail-meta">
                      {#if renamingId === selectedPlaylist.id}
                        <div class="ext-pl-rename-row">
                          <input
                            type="text"
                            class="ext-input"
                            bind:value={renameInput}
                            disabled={busy}
                            onkeydown={(e) => {
                              if (e.key === 'Enter') saveRename(selectedPlaylist.id)
                              if (e.key === 'Escape') cancelRename()
                            }}
                          />
                          <button
                            type="button"
                            class="ext-btn primary ext-btn-sm"
                            disabled={busy || !renameInput.trim()}
                            onclick={() => saveRename(selectedPlaylist.id)}
                          >
                            {locales.plus_save}
                          </button>
                          <button
                            type="button"
                            class="ext-btn ext-btn-sm"
                            disabled={busy}
                            onclick={cancelRename}
                          >
                            {locales.plus_cancel}
                          </button>
                        </div>
                      {:else}
                        <strong>{selectedPlaylist.name || 'Playlist'}</strong>
                        <span>{fmt(locales.plus_tracks_count, selectedTracks.length, maxTracks)}</span>
                      {/if}
                    </div>
                    <div class="ext-pl-detail-actions">
                      {#if renamingId !== selectedPlaylist.id}
                        <button
                          type="button"
                          class="ext-btn ext-btn-sm"
                          disabled={busy}
                          onclick={() => startRename(selectedPlaylist)}
                        >
                          {locales.plus_rename}
                        </button>
                        <button
                          type="button"
                          class="ext-btn ext-btn-sm"
                          disabled={busy || atPlaylistLimit}
                          onclick={() => duplicatePlaylist(selectedPlaylist.id, selectedPlaylist.name)}
                        >
                          {locales.plus_duplicate}
                        </button>
                      {/if}
                      <button
                        type="button"
                        class="ext-btn primary"
                        disabled={!canPlay || busy || selectedTracks.length === 0}
                        onclick={() => playPlaylist(selectedPlaylist.id)}
                      >
                        {busy ? '…' : locales.plus_play}
                      </button>
                    </div>
                  </div>

                  <div class="ext-pl-tracks">
                    {#each selectedTracks as track (track.id)}
                      <div class="ext-pl-track">
                        {#if trackArt(track.url)}
                          <img class="ext-pl-track-thumb" src={trackArt(track.url)} alt="" />
                        {/if}
                        <div class="ext-pl-track-meta">
                          <strong>{track.title || 'YouTube'}</strong>
                          <span>{truncateUrl(track.url)}</span>
                        </div>
                        <button
                          type="button"
                          class="ext-btn danger ext-btn-sm"
                          disabled={busy}
                          onclick={() => removeTrack(track.id)}
                        >
                          {locales.plus_remove}
                        </button>
                      </div>
                    {:else}
                      <div class="ext-pl-empty">{locales.plus_no_tracks}</div>
                    {/each}
                  </div>

                  <div class="ext-pl-add-row">
                    <input
                      type="text"
                      class="ext-input"
                      placeholder="YouTube URL"
                      bind:value={trackUrlInput}
                      disabled={busy || atTrackLimit}
                    />
                    <button
                      type="button"
                      class="ext-btn primary"
                      disabled={busy || atTrackLimit || !trackUrlInput.trim()}
                      onclick={addTrack}
                    >
                      {locales.plus_add}
                    </button>
                  </div>
                {:else}
                  <div class="ext-pl-create">
                    <input
                      type="text"
                      class="ext-input"
                      placeholder={locales.plus_playlist_name_ph}
                      bind:value={newPlaylistName}
                      disabled={busy || atPlaylistLimit}
                    />
                    <button
                      type="button"
                      class="ext-btn primary"
                      disabled={busy || atPlaylistLimit}
                      onclick={createPlaylist}
                    >
                      {locales.plus_new}
                    </button>
                  </div>
                  <div class="ext-pl-hint">{fmt(locales.plus_playlists_count, playlists.length, maxPlaylists)}</div>

                  <div class="ext-pl-list">
                    {#each playlists as pl (pl.id)}
                      <div class="ext-pl-row">
                        <div class="ext-pl-row-meta">
                          {#if renamingId === pl.id}
                            <div class="ext-pl-rename-row">
                              <input
                                type="text"
                                class="ext-input"
                                bind:value={renameInput}
                                disabled={busy}
                                onkeydown={(e) => {
                                  if (e.key === 'Enter') saveRename(pl.id)
                                  if (e.key === 'Escape') cancelRename()
                                }}
                              />
                              <button
                                type="button"
                                class="ext-btn primary ext-btn-sm"
                                disabled={busy || !renameInput.trim()}
                                onclick={() => saveRename(pl.id)}
                              >
                                {locales.plus_save}
                              </button>
                              <button
                                type="button"
                                class="ext-btn ext-btn-sm"
                                disabled={busy}
                                onclick={cancelRename}
                              >
                                {locales.plus_cancel}
                              </button>
                            </div>
                          {:else}
                            <strong>{pl.name || 'Playlist'}</strong>
                            <span>{fmt(locales.plus_tracks_n, pl.trackCount ?? 0)}</span>
                          {/if}
                        </div>
                        <div class="ext-pl-row-actions">
                          {#if renamingId !== pl.id}
                            <button
                              type="button"
                              class="ext-btn ext-btn-sm"
                              disabled={busy}
                              onclick={() => openPlaylist(pl.id)}
                            >
                              {locales.plus_open}
                            </button>
                            <button
                              type="button"
                              class="ext-btn ext-btn-sm"
                              disabled={busy}
                              onclick={() => startRename(pl)}
                            >
                              {locales.plus_rename}
                            </button>
                            <button
                              type="button"
                              class="ext-btn ext-btn-sm"
                              disabled={busy || atPlaylistLimit}
                              onclick={() => duplicatePlaylist(pl.id, pl.name)}
                            >
                              {locales.plus_duplicate}
                            </button>
                            <button
                              type="button"
                              class="ext-btn primary ext-btn-sm"
                              disabled={!canPlay || busy || !(pl.trackCount > 0)}
                              onclick={() => playPlaylist(pl.id)}
                              aria-label={locales.plus_play}
                            >
                              <Play size={14} strokeWidth={2.2} />
                            </button>
                            <button
                              type="button"
                              class="ext-btn danger ext-btn-sm"
                              disabled={busy}
                              onclick={() => deletePlaylist(pl.id)}
                            >
                              {locales.plus_delete}
                            </button>
                          {/if}
                        </div>
                      </div>
                    {:else}
                      <div class="ext-pl-empty">{locales.plus_no_playlists}</div>
                    {/each}
                  </div>
                {/if}
              </div>
              {#if statusMsg}
                <p class="ext-status">{statusMsg}</p>
              {/if}
            {:else if tab === 'now'}
              <div class="ext-now">
                <div class="ext-url-row">
                  <input
                    type="text"
                    class="ext-input"
                    placeholder={locales.plus_url_ph}
                    bind:value={urlInput}
                    disabled={!canPlay || busy}
                    onkeydown={onUrlKeydown}
                  />
                  <button type="button" class="ext-btn primary" onclick={playUrl} disabled={!canPlay || busy}>
                    {busy ? '…' : locales.plus_play}
                  </button>
                  <button
                    type="button"
                    class="ext-btn"
                    onclick={queueUrl}
                    disabled={!canPlay || busy || !canQueueUrl}
                    title={locales.plus_queue}
                  >
                    {locales.plus_queue}
                  </button>
                </div>

                <div class="ext-now-main">
                  <div class="ext-nowplaying-art" class:live={isLive} class:has-img={!!trackArt(playback?.url, playback?.thumbnail)}>
                    {#if trackArt(playback?.url, playback?.thumbnail)}
                      <img src={trackArt(playback.url, playback.thumbnail)} alt="" />
                    {/if}
                  </div>
                  <div class="ext-nowplaying-meta">
                    <strong>{playback?.title || locales.plus_nothing}</strong>
                    <span class="ext-now-url">{playback?.url || saveableUrl || locales.plus_pick_hint}</span>
                    <div class="ext-viz" class:active={isLive} aria-hidden="true">
                      <span class="bar"></span>
                      <span class="bar"></span>
                      <span class="bar"></span>
                      <span class="bar"></span>
                      <span class="bar"></span>
                    </div>
                  </div>
                </div>

                {#if queueTotal > 0}
                  <div class="ext-queue">
                    <div class="ext-queue-head">
                      <span class="ext-queue-title">{playback?.playlist?.name || locales.plus_queue}</span>
                      <span class="ext-queue-count">{fmt(locales.plus_queue_hint, queueIndex, queueTotal)}</span>
                    </div>
                    <div class="ext-queue-list" role="list">
                      {#each queueTracks as track, i (track.url + '-' + i)}
                        {@const pos = i + 1}
                        {@const isCurrent = pos === queueIndex}
                        {@const isPast = pos < queueIndex}
                        <div
                          class="ext-queue-item"
                          class:current={isCurrent}
                          class:past={isPast}
                          role="listitem"
                        >
                          <span class="ext-queue-pos">
                            {#if isCurrent}{locales.plus_queue_now}{:else if pos === queueIndex + 1}{locales.plus_queue_next}{:else}{pos}{/if}
                          </span>
                          {#if trackArt(track.url)}
                            <img class="ext-queue-thumb" src={trackArt(track.url)} alt="" />
                          {/if}
                          <div class="ext-queue-meta">
                            <strong>{track.title || 'YouTube'}</strong>
                            <span>{truncateUrl(track.url, 36)}</span>
                          </div>
                        </div>
                      {/each}
                    </div>
                  </div>
                {/if}

                {#if playlistsEnabled}
                  <div class="ext-quick-pl">
                    <button
                      type="button"
                      class="ext-btn ext-quick-pl-btn"
                      disabled={busy || !canSaveToPlaylist}
                      onclick={togglePlaylistPicker}
                      title={canSaveToPlaylist ? locales.plus_add_to_playlist : locales.plus_streams_no_playlist}
                    >
                      <ListPlus size={15} strokeWidth={2.2} />
                      <span>{locales.plus_add_to_playlist}</span>
                    </button>

                    {#if showPlaylistPicker && playlists.length > 0}
                      <div class="ext-pl-picker" role="listbox" aria-label={locales.plus_pick_playlist}>
                        <span class="ext-pl-picker-label">{locales.plus_pick_playlist}</span>
                        <div class="ext-pl-picker-list">
                          {#each playlists as pl (pl.id)}
                            <button
                              type="button"
                              class="ext-pl-picker-item"
                              disabled={busy || (pl.trackCount ?? 0) >= maxTracks}
                              onclick={() => quickAddToPlaylist(pl.id)}
                            >
                              <strong>{pl.name || 'Playlist'}</strong>
                              <span>{fmt(locales.plus_tracks_n, pl.trackCount ?? 0)}</span>
                            </button>
                          {/each}
                        </div>
                      </div>
                    {/if}
                  </div>
                {/if}

                <div class="ext-controls">
                  <div class="ext-volume-block">
                    <div class="ext-volume-row">
                      <span>{locales.plus_volume}</span>
                      <strong>{localVolume}%</strong>
                    </div>
                    <input
                      class="ext-volume"
                      type="range"
                      min="0"
                      max={maxVolumePct}
                      step="1"
                      value={localVolume}
                      style="--fill: {volumeFill}%"
                      oninput={onVolumeInput}
                    />
                  </div>
                  <div class="ext-transport">
                    {#if playback?.paused}
                      <button type="button" class="ext-btn" onclick={resumeTrack}>{locales.plus_resume}</button>
                    {:else if playback?.playing}
                      <button type="button" class="ext-btn" onclick={pauseTrack}>{locales.plus_pause}</button>
                    {/if}
                    <button
                      type="button"
                      class="ext-btn"
                      onclick={skipTrack}
                      disabled={!playback || busy || !canSkip}
                      title={locales.plus_skip}
                    >
                      <SkipForward size={14} strokeWidth={2.2} />
                      <span>{locales.plus_skip}</span>
                    </button>
                    <button type="button" class="ext-btn danger" onclick={stopTrack} disabled={!playback}>{locales.plus_stop}</button>
                  </div>
                </div>
              </div>
              {#if statusMsg}
                <p class="ext-status">{statusMsg}</p>
              {/if}
            {/if}
          </div>
        {/key}
      </div>
    </div>
  </div>
{/if}
