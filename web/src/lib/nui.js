/**
 * FiveM NUI helpers
 */

export function getResourceName() {
  try {
    if (typeof GetParentResourceName === 'function') {
      return GetParentResourceName()
    }
  } catch (_) {
    /* browser preview */
  }
  return 'nyn_carradio'
}

export async function nuiCallback(name, data = {}) {
  try {
    const res = await fetch(`https://${getResourceName()}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data),
    })
    return await res.json().catch(() => ({ ok: true }))
  } catch (_) {
    return { ok: false }
  }
}

export function onNuiMessage(handler) {
  const listener = (event) => handler(event.data || {})
  window.addEventListener('message', listener)
  return () => window.removeEventListener('message', listener)
}
