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

  const playlistsEnabled = $derived(!!extension.features?.playlists)
  const tabs = $derived.by(() => {
    const list = [{ id: 'stations', label: 'Stanice' }]
    if (playlistsEnabled) list.push({ id: 'playlists', label: 'Playlisty' })
    list.push({ id: 'now', label: 'Teď hraje' }, { id: 'search', label: 'URL' })
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
    playback?.paused ? 'Pozastaveno' : playback?.playing ? 'Přehrává se' : 'Nehraje',
  )
  const isLive = $derived(!!playback?.playing && !playback?.paused)
  const maxPlaylists = $derived(extension.playlistLimits?.maxPlaylists ?? 10)
  const maxTracks = $derived(extension.playlistLimits?.maxTracks ?? 10)
  const atPlaylistLimit = $derived(playlists.length >= maxPlaylists)
  const selectedTracks = $derived(
    Array.isArray(selectedPlaylist?.tracks) ? selectedPlaylist.tracks : [],
  )
  const atTrackLimit = $derived(selectedTracks.length >= maxTracks)

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
      limit_playlists: 'Dosáhl jsi limitu playlistů.',
      limit_tracks: 'Dosáhl jsi limitu skladeb v playlistu.',
      invalid_url: 'Pouze YouTube odkazy.',
      empty: 'Playlist je prázdný.',
      no_db: 'Databáze není dostupná (oxmysql).',
      forbidden: 'Nemáš přístup k tomuto playlistu.',
      disabled: 'Playlisty jsou vypnuté.',
      timeout: 'Timeout — zkus znovu.',
      not_in_vehicle: 'Musíš sedět ve vozidle.',
      missing_extension: 'Chybí nyn_carradio_plus.',
      load_failed: 'Playlist se nepodařilo načíst.',
      play_failed: 'Playlist nelze přehrát.',
    }
    return map[error] || 'Operace selhala.'
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
      statusMsg = 'Vlož YouTube nebo live stream URL.'
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
      statusMsg = 'Přehrávám…'
    } else {
      stopPlusMedia()
      const map = {
        missing_extension: 'Chybí nyn_carradio_plus.',
        not_in_vehicle: 'Musíš sedět ve vozidle.',
        invalid_url: 'Neplatný YouTube / stream odkaz.',
        no_xsound: 'Video nelze přehrát — xsound neběží.',
        play_failed: 'Video nelze přehrát.',
        no_carradio: 'nyn_carradio neběží.',
      }
      statusMsg = map[res?.error] || 'Video nelze přehrát.'
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
      statusMsg = 'Přehrávám…'
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
    statusMsg = ok ? 'Zvuk zapnutý.' : 'Zvuk jde přes xsound — Pause/Resume v Teď hraje.'
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
                <h3>Chybí nyn_carradio_plus</h3>
                <p>Nahraj resource na server a ensure-ni ho. Základní Q rádio funguje bez Plus.</p>
              </div>
            {:else if tab === 'stations'}
              {#if stations.length === 0}
                <div class="ext-empty">
                  <h3>Žádné stanice</h3>
                  <p>
                    Přidej je do <code>nyn_carradio_plus/shared/config.lua</code> →
                    <code>Config.Stations</code>.
                  </p>
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
                        <strong>{station.name || 'Stanice'}</strong>
                        <span>{station.type === 'youtube' ? 'YouTube' : 'Live stream'}</span>
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
                      ← Zpět
                    </button>
                    <div class="ext-pl-detail-meta">
                      <strong>{selectedPlaylist.name || 'Playlist'}</strong>
                      <span>{selectedTracks.length}/{maxTracks} skladeb</span>
                    </div>
                    <button
                      type="button"
                      class="ext-btn primary"
                      disabled={!canPlay || busy || selectedTracks.length === 0}
                      onclick={() => playPlaylist(selectedPlaylist.id)}
                    >
                      {busy ? '…' : 'Přehrát'}
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
                          Odebrat
                        </button>
                      </div>
                    {:else}
                      <div class="ext-pl-empty">Žádné skladby — přidej YouTube URL.</div>
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
                      Přidat
                    </button>
                  </div>
                {:else}
                  <div class="ext-pl-create">
                    <input
                      type="text"
                      class="ext-input"
                      placeholder="Název playlistu"
                      bind:value={newPlaylistName}
                      disabled={busy || atPlaylistLimit}
                    />
                    <button
                      type="button"
                      class="ext-btn primary"
                      disabled={busy || atPlaylistLimit}
                      onclick={createPlaylist}
                    >
                      Nový
                    </button>
                  </div>
                  <div class="ext-pl-hint">{playlists.length}/{maxPlaylists} playlistů</div>

                  <div class="ext-pl-list">
                    {#each playlists as pl (pl.id)}
                      <div class="ext-pl-row">
                        <div class="ext-pl-row-meta">
                          <strong>{pl.name || 'Playlist'}</strong>
                          <span>{pl.trackCount ?? 0} skladeb</span>
                        </div>
                        <div class="ext-pl-row-actions">
                          <button
                            type="button"
                            class="ext-btn ext-btn-sm"
                            disabled={busy}
                            onclick={() => openPlaylist(pl.id)}
                          >
                            Otevřít
                          </button>
                          <button
                            type="button"
                            class="ext-btn primary ext-btn-sm"
                            disabled={!canPlay || busy || !(pl.trackCount > 0)}
                            onclick={() => playPlaylist(pl.id)}
                            aria-label="Přehrát"
                          >
                            <Play size={14} strokeWidth={2.2} />
                          </button>
                          <button
                            type="button"
                            class="ext-btn danger ext-btn-sm"
                            disabled={busy}
                            onclick={() => deletePlaylist(pl.id)}
                          >
                            Smazat
                          </button>
                        </div>
                      </div>
                    {:else}
                      <div class="ext-pl-empty">Zatím žádné playlisty.</div>
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
                    <strong>{playback?.title || 'Nic nehraje'}</strong>
                    <span class="ext-now-url">{playback?.url || 'Vyber stanici nebo vlož URL.'}</span>
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
                      <span>Hlasitost</span>
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
                      <button type="button" class="ext-btn" onclick={resumeTrack}>Pokračovat</button>
                    {:else if playback?.playing}
                      <button type="button" class="ext-btn" onclick={pauseTrack}>Pauza</button>
                    {/if}
                    <button type="button" class="ext-btn" onclick={unmuteClick}>Zapnout zvuk</button>
                    <button type="button" class="ext-btn danger" onclick={stopTrack} disabled={!playback}>Stop</button>
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
                    placeholder="YouTube / https://…/stream.mp3"
                    bind:value={urlInput}
                    disabled={!canPlay || busy}
                  />
                  <button type="button" class="ext-btn primary" onclick={playUrl} disabled={!canPlay || busy}>
                    {busy ? '…' : 'Play'}
                  </button>
                </div>
                <div class="ext-volume-block">
                  <div class="ext-volume-row">
                    <span>Hlasitost</span>
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
