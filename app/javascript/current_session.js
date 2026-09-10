// Identifies which signed-in user (if any) is "current" on the page right
// now, read fresh from a data attribute the layout renders server-side.
//
// Favorites requests are async and outlive Turbo navigations: if a user
// logs out, or switches accounts, while a favorite toggle or guest-merge
// request is still in flight, its response must not be applied to
// whatever page is showing when it resolves - that would leak one
// account's favorite state onto another account's (or a guest's) screen.
// Callers capture this before firing a request and compare it again when
// the response arrives; a mismatch means the response is stale and should
// be discarded.
export function currentUserId() {
  return document.body.dataset.currentUserId || null
}
