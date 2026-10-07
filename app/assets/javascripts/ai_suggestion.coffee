# Behaviour of the modal that offers the title and the description suggested by AI.
# Opening and closing it is bootstrap's job, done from the markup of the view.

# Turbolinks caches the page as it was when the user left it. Without this, coming back
# restores a frozen modal, with its backdrop over the page and the scroll still locked.
$(document).on 'turbolinks:before-cache', ->
  modal = document.querySelector('#ai-suggestion-modal')
  return unless modal

  bootstrap.Modal.getInstance(modal)?.dispose()
  document.querySelectorAll('.modal-backdrop').forEach (el) -> el.remove()
  document.body.classList.remove('modal-open')
  document.body.style.removeProperty('overflow')
  document.body.style.removeProperty('padding-right')
