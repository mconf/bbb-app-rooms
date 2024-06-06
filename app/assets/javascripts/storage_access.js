// based on https://developer.mozilla.org/en-US/docs/Web/API/Storage_Access_API/Using#checking_and_requesting_storage_access

async function handleCookieAccess() {
  console.debug('Starting handler of third-party cookies access');
  if (!document.hasStorageAccess) {
    // This browser doesn't support the Storage Access API
    // so let's just hope we have access!
    console.warn("This browser doesn't support the Storage Access API");
    return true;
  }

  const hasAccess = await document.hasStorageAccess();
  if (hasAccess) {
    // We have access to third-party cookies, so let's go
    console.debug('App has access to third-party cookies!');
    return true;
  }
  else {
    // Check whether third-party cookie access has been granted
    // to another same-site embed
    try {
      const permission = await navigator.permissions.query({
        name: "storage-access",
      });


      console.debug(`storage-access permission.state = ${permission.state}`);
      if (permission.state === "granted") {
        // If so, you can just call requestStorageAccess() without a user interaction,
        // and it will resolve automatically.
        await document.requestStorageAccess();
        return true;
      }
      else if (permission.state === "prompt") {
        // Need to call requestStorageAccess() after a user interaction
        console.debug('Now waiting for a click on btn-session-retry');
        $('.btn-session-retry').on('click', async function(e) {
          e.preventDefault();
          $(this).addClass('disabled');
          $(this).attr('disabled', '1');
          $(this).text('Aguardando ação do usuário');
          try {
            await document.requestStorageAccess();
            window.location = $(this).attr('href');
            return true;
          } catch (err) {
            // If there is an error obtaining storage access.
            console.warn(`Storage access was not granted: ${err}.`);
            $(this).text('Permissão negada. Por favor, redefina no navegador');
            return;
          }
        });
      }
      else if (permission.state === "denied") {
        // User has denied third-party cookie access, so we'll
        // need to do something else
        return false;
      }
    } catch (error) {
      console.warn(`Could not access storage-access permission state. Error: ${error}`);
      return false; // Again, we'll have to hope we have access!
    }
  }
}

$(document).on('turbolinks:load', handleCookieAccess);
