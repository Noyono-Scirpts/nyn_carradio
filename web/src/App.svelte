<script>
  import { onMount } from 'svelte'
  import RadioHud from './components/RadioHud.svelte'
  import ExtensionApp from './components/ExtensionApp.svelte'
  import { onNuiMessage } from './lib/nui.js'
  import {
    playPlusStream,
    stopPlusMedia,
    setPlusVolume,
    setPlusMuffle,
  } from './lib/plusMedia.js'

  onMount(() => {
    return onNuiMessage((data) => {
      if (!data || !data.action) return

      if (data.action === 'plusPlay') {
        const volume = typeof data.volume === 'number' ? data.volume : 0.8
        if (data.kind === 'youtube') {
          stopPlusMedia()
        } else if (data.kind === 'stream' && data.url) {
          playPlusStream(data.url, volume)
        }
      } else if (data.action === 'plusStop') {
        stopPlusMedia()
      } else if (data.action === 'plusVolume') {
        setPlusVolume(data.volume)
      } else if (data.action === 'plusMuffle') {
        setPlusMuffle(!!data.muffled)
      } else if (data.action === 'stopAll') {
        stopPlusMedia()
      }

    })
  })
</script>

<RadioHud />
<ExtensionApp />
