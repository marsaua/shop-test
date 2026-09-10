// Client-only favorites storage for guests (not signed in). Authenticated
// users' favorites always live on the server; nothing here is ever written
// for a signed-in session, so a previous account's picks can never leak
// into another account via this storage.
const STORAGE_KEY = "shop_trololo.guest_favorites"
const STORAGE_VERSION = 1

// Versioned so a future format change can detect and migrate (or discard)
// older shapes instead of misreading them. Anything that isn't exactly
// { v: STORAGE_VERSION, ids: [...] } - wrong version, corrupted JSON,
// tampered-with data, or the old unversioned array this key used to hold -
// is treated as invalid and dropped rather than trusted.
function readIds() {
  let raw
  try {
    raw = window.localStorage.getItem(STORAGE_KEY)
  } catch (error) {
    return []
  }

  if (!raw) return []

  let parsed
  try {
    parsed = JSON.parse(raw)
  } catch (error) {
    return []
  }

  if (!parsed || typeof parsed !== "object" || parsed.v !== STORAGE_VERSION || !Array.isArray(parsed.ids)) {
    return []
  }

  return dedupe(parsed.ids.map(Number).filter((id) => Number.isInteger(id) && id > 0))
}

function writeIds(ids) {
  const unique = dedupe(ids.map(Number).filter((id) => Number.isInteger(id) && id > 0))

  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify({ v: STORAGE_VERSION, ids: unique }))
  } catch (error) {
    // localStorage unavailable (private browsing, quota exceeded, etc.) -
    // the toggle still works for this page view, it just won't persist.
  }

  return unique
}

function dedupe(ids) {
  return Array.from(new Set(ids))
}

export function getGuestFavoriteIds() {
  return readIds()
}

export function setGuestFavoriteIds(ids) {
  return writeIds(ids)
}

export function isGuestFavorite(productId) {
  return readIds().includes(Number(productId))
}

export function addGuestFavorite(productId) {
  return writeIds([ ...readIds(), Number(productId) ])
}

export function removeGuestFavorite(productId) {
  return writeIds(readIds().filter((id) => id !== Number(productId)))
}

export function clearGuestFavorites() {
  return writeIds([])
}
