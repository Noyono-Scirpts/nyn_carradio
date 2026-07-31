<script>
  import { onMount } from 'svelte'
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
  })
  let playback = $state(null)
  let localVolume = $state(100)
  let volumeTimer = null
  let activeStationUrl = $state('')

  const tabs = [
    { id: 'stations', label: 'Stanice' },
    { id: 'now', label: 'Teď hraje' },
    { id: 'search', label: 'URL' },
  ]

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

  function detectTitle(url) {
    if (/youtu\.?be/i.test(url)) return 'YouTube'
    return 'Live Radio'
  }

  function open(payload = {}) {
    if (payload.extension) {
      extension = {
        ...extension,
        ...payload.extension,
        stations: payload.extension.stations || extension.stations || [],
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
    <div class="ext-shell">
      <aside class="ext-sidebar">
        <div class="ext-brand">
          <span class="ext-brand-label">NYN</span>
          <span class="ext-brand-title">Plus</span>
          <span class="ext-brand-sub">Car Radio+</span>
        </div>

        <nav class="ext-nav">
          {#each tabs as item}
            <button
              type="button"
              class="ext-nav-btn"
              class:active={tab === item.id}
              onclick={() => (tab = item.id)}
            >
              {item.label}
            </button>
          {/each}
        </nav>

        <div class="ext-side-status">
          <span class="ext-dot" class:on={!!playback?.playing && !playback?.paused}></span>
          <span>{playingLabel}</span>
        </div>
      </aside>

      <section class="ext-main">
        <div class="ext-topbar">
          <h2>{tabTitle}</h2>
          <button type="button" class="ext-close" onclick={close} aria-label="Close">×</button>
        </div>

        <div class="ext-content">
          {#if !hasPlus}
            <div class="ext-panel">
              <span class="ext-badge">Plus required</span>
              <div class="ext-panel-card">
                <h3>Chybí nyn_carradio_plus</h3>
                <p>Nahraj resource na server a ensure-ni ho. Základní Q rádio funguje bez Plus.</p>
              </div>
            </div>
          {:else if tab === 'stations'}
            <div class="ext-panel">
              <span class="ext-badge">Online stanice</span>
              {#if stations.length === 0}
                <div class="ext-panel-card">
                  <h3>Žádné stanice</h3>
                  <p>
                    Přidej je do <code>nyn_carradio_plus/shared/config.lua</code> →
                    <code>Config.Stations</code>.
                  </p>
                </div>
              {:else}
                <div class="ext-station-list">
                  {#each stations as station}
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
                      <span class="ext-station-play">{busy && activeStationUrl === station.url ? '…' : '▶'}</span>
                    </button>
                  {/each}
                </div>
              {/if}
              {#if statusMsg}
                <div class="ext-panel-card"><p>{statusMsg}</p></div>
              {/if}
            </div>
          {:else if tab === 'now'}
            <div class="ext-panel">
              <span class="ext-badge">xsound · cabin</span>
              <div class="ext-panel-card">
                <div class="ext-nowplaying">
                  <div class="ext-nowplaying-art" class:live={!!playback?.playing && !playback?.paused}></div>
                  <div class="ext-nowplaying-meta">
                    <strong>{playback?.title || 'Nic nehraje'}</strong>
                    <span>{playback?.url || 'Vyber stanici nebo vlož URL.'}</span>
                    <em class="ext-now-state">{playingLabel}</em>
                  </div>
                </div>
              </div>

              <div class="ext-panel-card">
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

              <div class="ext-search-box">
                {#if playback?.paused}
                  <button type="button" onclick={resumeTrack}>Pokračovat</button>
                {:else if playback?.playing}
                  <button type="button" onclick={pauseTrack}>Pauza</button>
                {/if}
                <button type="button" onclick={unmuteClick}>Zapnout zvuk</button>
                <button type="button" onclick={stopTrack} disabled={!playback}>Stop</button>
              </div>
            </div>
          {:else}
            <div class="ext-panel">
              <span class="ext-badge">{extension.xsound ? 'YouTube + Live' : 'NUI only · xsound off'}</span>
              <div class="ext-panel-card">
                <h3>Vlastní odkaz</h3>
                <p>YouTube nebo přímý stream (mp3 / icecast). Stanice z configu najdeš v záložce Stanice.</p>
              </div>
              <div class="ext-panel-card">
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
              <div class="ext-search-box">
                <input
                  type="text"
                  placeholder="YouTube / https://…/stream.mp3"
                  bind:value={urlInput}
                  disabled={!canPlay || busy}
                />
                <button type="button" onclick={playUrl} disabled={!canPlay || busy}>
                  {busy ? '…' : 'Play'}
                </button>
              </div>
              {#if statusMsg}
                <div class="ext-panel-card"><p>{statusMsg}</p></div>
              {/if}
            </div>
          {/if}
        </div>
      </section>
    </div>
  </div>
{/if}
