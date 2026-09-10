// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

window.addEventListener("favorites:error", (event) => {
  const region = document.getElementById("favorites-error")
  if (!region) return

  region.textContent = event.detail?.message || "Something went wrong."
  region.hidden = false

  window.clearTimeout(window.favoritesErrorTimeout)
  window.favoritesErrorTimeout = window.setTimeout(() => {
    region.hidden = true
  }, 5000)
})
