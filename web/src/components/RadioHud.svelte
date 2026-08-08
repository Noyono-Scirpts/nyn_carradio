<script>
  import { onMount } from 'svelte'
  import { nuiCallback, onNuiMessage } from '../lib/nui.js'
  import { playStream, stopStream } from '../lib/audio.js'
  import '../styles/radio.css'

  let visible = $state(false)
  let mountedVisible = $state(false)
  let mini = $state(false)
  let stations = $state([])
  let currentIndex = $state(0)
  let displayName = $state('Off')
  let displayType = $state('off')
  let displayImage = $state('')
  let logoBroken = $state(false)
  let autoHideTimer = null
  let closeTimeout = null

  let locales = $state({
    prefix: 'NYN',
    title: 'CAR RADIO',
    off: 'Off',
    stream_error: 'Stream error',
    footer: 'Scroll / Arrows - Select',
  })

  const statusLabel = $derived(
    `${locales.prefix ? `${locales.prefix} ` : ''}${locales.title || ''}`.trim()
  )

  const sliderTransform = $derived(
    `translateX(-${currentIndex * 80 + 32}px)`
  )

  function getLogoSrc(imageName) {
    if (!imageName) return ''
    if (imageName.startsWith('http://') || imageName.startsWith('https://')) {
      return imageName
    }
    return `./images/${imageName}`
  }

  function applyLocales(next) {
    if (!next) return
    locales = { ...locales, ...next }
  }

  function clearAutoHide() {
    if (autoHideTimer) {
      clearTimeout(autoHideTimer)
      autoHideTimer = null
    }
  }

  function resetAutoHide(duration = 3500) {
    clearAutoHide()
    autoHideTimer = setTimeout(() => closeUI(), duration)
  }

  function showUI(nextStations) {
    if (closeTimeout) {
      clearTimeout(closeTimeout)
      closeTimeout = null
    }
    visible = true
    requestAnimationFrame(() => {
      mountedVisible = true
    })
    if (nextStations) {
      stations = nextStations
    }
  }

  function hideUI() {
    clearAutoHide()
    mountedVisible = false
    if (closeTimeout) clearTimeout(closeTimeout)
    closeTimeout = setTimeout(() => {
      visible = false
      closeTimeout = null
    }, 350)
  }

  function closeUI() {
    hideUI()
    nuiCallback('close')
  }

  function setActiveVisuals(index, station) {
    if (!station) return
    currentIndex = index
    displayName = station.name
    displayType = station.type
    displayImage = station.image || ''
    logoBroken = false
  }

  async function selectStation(index, { notify = true } = {}) {
    if (!stations.length) return
    if (index < 0 || index >= stations.length) return

    const station = stations[index]
    setActiveVisuals(index, station)

    if (autoHideTimer) {
      resetAutoHide(3500)
    }

    // Stop current HTML stream; Lua will send playStream for stream stations
    // (do NOT play here too — double play caused pause/play DOMException)
    if (station.type !== 'stream') {
      stopStream()
    }

    if (notify) {
      await nuiCallback('selectStation', {
        index,
        name: station.name,
        image: station.image,
        type: station.type,
        value: station.value,
      })
    } else if (station.type === 'stream' && station.value) {
      playStream(station.value)
    }
  }

  function syncFromPayload(data) {
    if ((!stations || stations.length === 0) && data.stations) {
      stations = data.stations
    }

    currentIndex = data.index ?? 0
    displayName = data.name || locales.off
    displayType = data.type || 'off'
    displayImage = data.image || ''
    logoBroken = false
  }

  onMount(() => {
    const offStreamError = () => {
      displayName = locales.stream_error || 'Stream error'
    }
    window.addEventListener('nyn-stream-error', offStreamError)

    const offMessage = onNuiMessage((data) => {
      if (data.locales) applyLocales(data.locales)

      switch (data.action) {
        case 'open':
          clearAutoHide()
          mini = false
          showUI(data.stations)
          break
        case 'close':
          hideUI()
          break
        case 'nextStation':
          if (stations.length) {
            selectStation((currentIndex + 1) % stations.length)
          }
          break
        case 'prevStation':
          if (stations.length) {
            selectStation((currentIndex - 1 + stations.length) % stations.length)
          }
          break
        case 'cycleNext':
          clearAutoHide()
          mini = true
          showUI(stations.length === 0 ? data.stations : null)
          if (stations.length > 0) {
            selectStation((currentIndex + 1) % stations.length)
          }
          resetAutoHide(3500)
          break
        case 'cyclePrev':
          clearAutoHide()
          mini = true
          showUI(stations.length === 0 ? data.stations : null)
          if (stations.length > 0) {
            selectStation((currentIndex - 1 + stations.length) % stations.length)
          }
          resetAutoHide(3500)
          break
        case 'syncVisuals':
          clearAutoHide()
          if ((!stations || stations.length === 0) && data.stations) {
            stations = data.stations
          }
          if (data.showUI) {
            mini = true
            showUI()
            resetAutoHide(3500)
          }
          syncFromPayload(data)
          break
        case 'playStream':
          playStream(data.url)
          break
        case 'stopStream':
          stopStream()
          break
        case 'stopAll':
          stopStream()
          clearAutoHide()
          currentIndex = 0
          displayName = locales.off || 'Off'
          displayType = 'off'
          displayImage = ''
          logoBroken = false
          break
        default:
          break
      }
    })

    const onKey = (event) => {
      if (event.key === 'Escape' && visible) {
        closeUI()
      }
    }
    window.addEventListener('keyup', onKey)

    return () => {
      offMessage()
      window.removeEventListener('keyup', onKey)
      window.removeEventListener('nyn-stream-error', offStreamError)
      clearAutoHide()
      if (closeTimeout) clearTimeout(closeTimeout)
      stopStream()
    }
  })
</script>

{#if visible}
  <div class="radio-root" class:visible={mountedVisible}>
    <div class="radio-card" class:mini>
      <div class="radio-header">
        <div class="status-indicator">
          <span class="pulse-dot"></span>
          <span class="status-text">{statusLabel}</span>
        </div>

        <div class="station-info-row">
          {#if displayImage && !logoBroken}
            <img
              class="active-logo"
              src={getLogoSrc(displayImage)}
              alt="logo"
              onerror={() => (logoBroken = true)}
            />
          {/if}
          <div class="station-name" class:off={displayType === 'off'}>
            {displayName}
          </div>
        </div>

        <div class="visualizer-container" class:active={displayType !== 'off'}>
          <div class="bar"></div>
          <div class="bar"></div>
          <div class="bar"></div>
          <div class="bar"></div>
          <div class="bar"></div>
        </div>
      </div>

      <div class="stations-container">
        <div class="stations-wrapper" style:transform={sliderTransform}>
          {#each stations as station, index (index)}
            <button
              type="button"
              class="station-circle"
              class:active={index === currentIndex}
              data-type={station.type}
              onclick={() => selectStation(index)}
            >
              {#if station.image}
                <img
                  src={getLogoSrc(station.image)}
                  alt={station.name}
                  onerror={(e) => {
                    e.currentTarget.style.display = 'none'
                    e.currentTarget.parentElement.textContent = station.icon || ''
                  }}
                />
              {:else}
                {station.icon}
              {/if}
            </button>
          {/each}
        </div>
      </div>

      <div class="radio-footer">{locales.footer}</div>
    </div>
  </div>
{/if}
