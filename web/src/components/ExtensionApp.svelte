<script>
  import { onMount } from 'svelte'
  import { X, Play, LoaderCircle } from '@lucide/svelte'
  import { nuiCallback, onNuiMessage } from '../lib/nui.js'
  import {
    stopPlusMedia,
    setPlusVolume,
    forceUnmute,
  } from '../lib/plusMedia.js'
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
    plus_no_playlists: 'No playlists yet.',
    plus_nothing: 'Nothing playing',
    plus_pick_hint: 'Pick a station or paste a URL.',
    plus_volume: 'Volume',
    plus_resume: 'Resume',
    plus_pause: 'Pause',
    plus_unmute: 'Unmute',
    plus_stop: 'Stop',
    plus_url_ph: 'YouTube / https://…/stream.mp3',
    plus_need_url: 'Enter a YouTube or live stream URL.',
    plus_playing: 'Playing…',
    plus_sound_on: 'Sound enabled.',
    plus_sound_xsound: 'Audio goes through xsound — use Pause/Resume in Now playing.',
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
  })

  const playlistsEnabled = $derived(!!extension.features?.playlists)
  const tabs = $derived.by(() => {
    const list = [{ id: 'stations', label: locales.plus_tab_stations }]
    if (playlistsEnabled) list.push({ id: 'playlists', label: locales.plus_tab_playlists })
    list.push({ id: 'now', label: locales.plus_tab_now }, { id: 'search', label: locales.plus_tab_search })
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

  function fmt(template, ...args) {
    let i = 0
    return String(template || '').replace(/%s/g, () => String(args[i++] ?? ''))
  }

  function detectTitle(url) {
    if (/youtu\.?be/i.test(url)) return 'YouTube'
    return 'Live Radio'
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
    if (id === 'playlists' && playlistsEnabled) {
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
      playback = payload.state
      if (payload.state.url) {
        urlInput = payload.state.url
        activeStationUrl = payload.state.url
      }
      if (typeof payload.state.volume === 'number') {
        localVolume = Math.round(payload.state.volume * 100)
      }
    }
    tab = payload.tab || (stations.length ? 'stations' : 'search')
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

    const resolvedTitle = title || detectTitle(url)
    const volume = localVolume / 100

    // Always xsound from Lua — starting NUI here caused duplicate (NUI + PlayUrlPos)
    stopPlusMedia()

    busy = true
    statusMsg = ''
    const res = await nuiCallback('extensionPlay', {
      url,
      title: resolvedTitle,
      volume,
      clientPlaying: false,
    })
    busy = false

    if (res?.ok) {
      playback = { url, title: resolvedTitle, playing: true, paused: false, volume }
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
      if (Array.isArray(res.playlists)) playlists = res.playlists
      else await refreshPlaylists()
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
    busy = true
    statusMsg = ''
    const res = await nuiCallback('extensionPlaylist', {
      action: 'addTrack',
      payload: {
        playlistId: selectedPlaylist.id,
        url,
        title: detectTitle(url),
      },
    })
    busy = false
    if (res?.ok) {
      trackUrlInput = ''
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
      playback = { url, title, playing: true, paused: false, volume }
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

  function unmuteClick() {
    const ok = forceUnmute()
    statusMsg = ok ? locales.plus_sound_on : locales.plus_sound_xsound
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
      if (data.action === 'openExtension') {
        open(data)
      } else if (data.action === 'closeExtension') {
        mountedVisible = false
        setTimeout(() => {
          visible = false
        }, 220)
      } else if (data.action === 'extensionState') {
        // Shared track sync for passengers (and live updates while UI open)
        if (data.state) {
          playback = data.state
          if (data.state.url) {
            urlInput = data.state.url
            activeStationUrl = data.state.url
          }
          if (typeof data.state.volume === 'number') {
            localVolume = Math.round(data.state.volume * 100)
          }
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
                      <strong>{selectedPlaylist.name || 'Playlist'}</strong>
                      <span>{fmt(locales.plus_tracks_count, selectedTracks.length, maxTracks)}</span>
                    </div>
                    <button
                      type="button"
                      class="ext-btn primary"
                      disabled={!canPlay || busy || selectedTracks.length === 0}
                      onclick={() => playPlaylist(selectedPlaylist.id)}
                    >
                      {busy ? '…' : locales.plus_play}
                    </button>
                  </div>

                  <div class="ext-pl-tracks">
                    {#each selectedTracks as track (track.id)}
                      <div class="ext-pl-track">
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
                          <strong>{pl.name || 'Playlist'}</strong>
                          <span>{fmt(locales.plus_tracks_n, pl.trackCount ?? 0)}</span>
                        </div>
                        <div class="ext-pl-row-actions">
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
                <div class="ext-now-main">
                  <div class="ext-nowplaying-art" class:live={isLive}></div>
                  <div class="ext-nowplaying-meta">
                    <strong>{playback?.title || locales.plus_nothing}</strong>
                    <span class="ext-now-url">{playback?.url || locales.plus_pick_hint}</span>
                    <div class="ext-viz" class:active={isLive} aria-hidden="true">
                      <span class="bar"></span>
                      <span class="bar"></span>
                      <span class="bar"></span>
                      <span class="bar"></span>
                      <span class="bar"></span>
                    </div>
                  </div>
                </div>

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
                    <button type="button" class="ext-btn" onclick={unmuteClick}>{locales.plus_unmute}</button>
                    <button type="button" class="ext-btn danger" onclick={stopTrack} disabled={!playback}>{locales.plus_stop}</button>
                  </div>
                </div>
              </div>
              {#if statusMsg}
                <p class="ext-status">{statusMsg}</p>
              {/if}
            {:else}
              <div class="ext-url">
                <div class="ext-url-row">
                  <input
                    type="text"
                    class="ext-input"
                    placeholder={locales.plus_url_ph}
                    bind:value={urlInput}
                    disabled={!canPlay || busy}
                  />
                  <button type="button" class="ext-btn primary" onclick={playUrl} disabled={!canPlay || busy}>
                    {busy ? '…' : locales.plus_play}
                  </button>
                </div>
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
                {#if statusMsg}
                  <p class="ext-status">{statusMsg}</p>
                {/if}
              </div>
            {/if}
          </div>
        {/key}
      </div>
    </div>
  </div>
{/if}
