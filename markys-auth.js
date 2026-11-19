(() => {
  "use strict";
  const root = document.documentElement;
  // The root HTML/PowerShell application is strictly local/offline.
  // Online authentication is implemented only in /online with its own Supabase client.
  if (window.MARKYS_LOCAL_MODE) {
    window.MARKYS_AUTH_READY = Promise.resolve({ role: "local", active: true });
    root.classList.remove("markys-auth-checking");
    return;
  }
  root.classList.remove("markys-auth-checking");
  window.location.replace("https://markyssga.vercel.app/");
})();
