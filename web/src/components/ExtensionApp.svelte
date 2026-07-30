<script>
  import { onMount } from 'svelte'
  import { nuiCallback, onNuiMessage } from '../lib/nui.js'
  import '../styles/extension.css'

  let visible = $state(false)
  let mountedVisible = $state(false)
  let tab = $state('search')
  let urlInput = $state('')
  let busy = $state(false)
  let statusMsg = $state('')
  let extension = $state({ available: false, xsound: false, features: {} })
  let playback = $state(null)

  const tabs = [
    { id: 'now', label: 'Now Playing' },
    { id: 'search', label: 'Play URL' },
    { id: 'playlists', label: 'Playlists' },
    { id: 'library', label: 'Library' },
  ]

  const tabTitle = $derived(tabs.find((t) => t.id === tab)?.label || 'Radio')
  const hasPlus = $derived(!!extension.available)
  const canPlay = $derived(hasPlus && !!extension.xsound)

  function detectTitle(url) {
    if (/youtu\.?be/i.test(url)) return 'YouTube'
    return 'Live Radio'
  }

  function open(payload = {}) {
    if (payload.extension) extension = { ...extension, ...payload.extension }
    if (payload.state) {
      playback = payload.state
      if (payload.state.url) urlInput = payload.state.url
    }
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

  async function playUrl() {
    if (!canPlay || busy) return
    const url = urlInput.trim()
    if (!url) {
      statusMsg = 'Vlož YouTube nebo live stream URL.'
      return
    }

    const title = detectTitle(url)
    busy = true
    statusMsg = ''
    const res = await nuiCallback('extensionPlay', { url, title })
    busy = false

    if (res?.ok) {
      playback = { url, title, playing: true, paused: false }
      tab = 'now'
      statusMsg = 'Přehrávám…'
    } else {
      const map = {
        missing_extension: 'Chybí nyn_carradio_plus — nahraj placené rozšíření.',
        not_in_vehicle: 'Musíš sedět ve vozidle.',
        invalid_url: 'Neplatný YouTube / stream odkaz.',
      }
      statusMsg = map[res?.error] || 'Nepodařilo se přehrát.'
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
    await nuiCallback('extensionStop')
    playback = null
  }

  onMount(() => {
    const off = onNuiMessage((data) => {
      if (data.action === 'openExtension') {
        tab = data.tab || 'search'
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
    }
  })
</script>

{#if visible}
  <div class="ext-root" class:visible={mountedVisible}>
    <div class="ext-shell">
      <aside class="ext-sidebar">
        <div class="ext-brand">
          <span class="ext-brand-label">NYN EXTENSION</span>
          <span class="ext-brand-title">Car Radio+</span>
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
      </aside>

      <section class="ext-main">
        <div class="ext-topbar">
          <h2>{tabTitle}</h2>
          <button type="button" class="ext-close" onclick={close} aria-label="Close">×</button>
        </div>

        <div class="ext-content">
          {#if !hasPlus}
            <div class="ext-panel">
              <span class="ext-badge">Drop-in required</span>
              <div class="ext-panel-card">
                <h3>Chybí nyn_carradio_plus</h3>
                <p>
                  Nahraj resource na server a ensure-ni ho. Base radio si ho najde samo.
                  YouTube + live streamy hrají přes xsound; zvenku duní, uvnitř / při otevřených dveřích normálně.
                </p>
              </div>
            </div>
          {:else if tab === 'now'}
            <div class="ext-panel">
              <span class="ext-badge">xsound · cabin mix</span>
              <div class="ext-panel-card">
                <div class="ext-nowplaying">
                  <div class="ext-nowplaying-art"></div>
                  <div class="ext-nowplaying-meta">
                    <strong>{playback?.title || 'Nic nehraje'}</strong>
                    <span>{playback?.url || 'Vlož odkaz v Play URL.'}</span>
                  </div>
                </div>
              </div>
              <div class="ext-search-box">
                {#if playback?.paused}
                  <button type="button" onclick={resumeTrack}>Resume</button>
                {:else if playback?.playing}
                  <button type="button" onclick={pauseTrack}>Pause</button>
                {/if}
                <button type="button" onclick={stopTrack} disabled={!playback}>Stop</button>
              </div>
            </div>
          {:else if tab === 'search'}
            <div class="ext-panel">
              <span class="ext-badge">{canPlay ? 'YouTube + Live' : 'xsound missing'}</span>
              <div class="ext-panel-card">
                <h3>YouTube nebo live rádio</h3>
                <p>
                  Vlož YouTube odkaz nebo stream URL (mp3 / icecast), stejně jako Spin u základního radia.
                  Ve voze plný zvuk, zvenku jen dunění — otevřené dveře = slyšet normálně.
                </p>
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
          {:else if tab === 'playlists'}
            <div class="ext-panel">
              <span class="ext-badge">Playlists · soon</span>
              <div class="ext-panel-card">
                <h3>Playlisty</h3>
                <p>Fronta / playlisty přijdou později.</p>
              </div>
            </div>
          {:else}
            <div class="ext-panel">
              <span class="ext-badge">Library · soon</span>
              <div class="ext-panel-card">
                <h3>Knihovna</h3>
                <p>Uložené skladby — později.</p>
              </div>
            </div>
          {/if}
        </div>
      </section>
    </div>
  </div>
{/if}
