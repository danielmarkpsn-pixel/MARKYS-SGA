(() => {
  "use strict";
  // No cloud client is loaded by the legacy local application.
  // The online application has its own isolated Supabase integration in /online.
  window.MARKYS_CLOUD = null;
  window.MARKYS_AUTH_READY = Promise.resolve(null);
})();
