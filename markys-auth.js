(() => {
  "use strict";
  const cloud = window.MARKYS_CLOUD;
  const client = cloud.client;
  const root = document.documentElement;
  const localMode = !!window.MARKYS_LOCAL_MODE;
  const params = new URLSearchParams(location.search);
  const publicMode = params.get("painel") === "1" || location.pathname === "/sala" || location.pathname === "/sala/";
  const financeMode = location.pathname === "/financeiro" || location.pathname === "/financeiro.html";
  const hashParams = new URLSearchParams(location.hash.replace(/^#/, ""));
  const authFlow = hashParams.get("type") || params.get("flow") || "";
  let overlay = null;

  function cleanAuthUrl() {
    const clean = location.pathname + location.search;
    history.replaceState({}, document.title, clean);
  }

  function showAccessMessage(message) {
    if (overlay) overlay.remove();
    overlay = document.createElement("div");
    overlay.className = "markys-sga-auth-overlay";
    overlay.innerHTML = `
      <section class="markys-sga-auth-card" aria-labelledby="markys-sga-auth-title">
        <img src="/markys-sga.svg" alt="MARKYS SGA" class="markys-sga-auth-logo">
        <h1 id="markys-sga-auth-title">Sala de espera</h1>
        <p id="markys-sga-auth-info"></p>
      </section>`;
    document.body.appendChild(overlay);
    overlay.querySelector("#markys-sga-auth-info").textContent = message;
    root.classList.remove("markys-sga-auth-checking", "markys-auth-checking");
  }

  function showPasswordSetup(message) {
    if (overlay) overlay.remove();
    overlay = document.createElement("div");
    overlay.className = "markys-sga-auth-overlay";
    overlay.innerHTML = `
      <section class="markys-sga-auth-card" aria-labelledby="markys-sga-auth-title">
        <img src="/markys-sga.svg" alt="MARKYS SGA" class="markys-sga-auth-logo">
        <h1 id="markys-sga-auth-title">Definir senha</h1>
        <p>Crie uma senha para acessar o MARKYS SGA. Use pelo menos 8 caracteres.</p>
        <form id="markys-sga-password-form">
          <label for="markys-sga-new-password">Nova senha</label>
          <input id="markys-sga-new-password" name="password" type="password" autocomplete="new-password" minlength="8" required>
          <label for="markys-sga-confirm-password">Confirmar senha</label>
          <input id="markys-sga-confirm-password" name="confirm" type="password" autocomplete="new-password" minlength="8" required>
          <button type="submit" class="markys-sga-auth-submit">Salvar senha</button>
          <div class="markys-sga-auth-message" id="markys-sga-password-message" role="alert"></div>
        </form>
      </section>`;
    document.body.appendChild(overlay);
    root.classList.remove("markys-sga-auth-checking", "markys-auth-checking");
    const form = overlay.querySelector("#markys-sga-password-form");
    const messageBox = overlay.querySelector("#markys-sga-password-message");
    if (message) messageBox.textContent = message;
    form.addEventListener("submit", async event => {
      event.preventDefault();
      const button = form.querySelector("button");
      const password = form.elements.password.value;
      if (password.length < 8) {
        messageBox.textContent = "A senha deve ter pelo menos 8 caracteres.";
        return;
      }
      if (password !== form.elements.confirm.value) {
        messageBox.textContent = "As senhas não coincidem.";
        return;
      }
      button.disabled = true;
      button.textContent = "Salvando...";
      messageBox.textContent = "";
      try {
        const { error } = await client.auth.updateUser({ password });
        if (error) throw error;
        await client.auth.signOut();
        cleanAuthUrl();
        showLogin("Senha criada com sucesso. Entre com seu e-mail e a nova senha.");
      } catch (error) {
        messageBox.textContent = error.message || "Não foi possível salvar a senha. Abra novamente o link recebido por e-mail.";
      } finally {
        button.disabled = false;
        button.textContent = "Salvar senha";
      }
    });
  }

  function showRecovery(message) {
    if (overlay) overlay.remove();
    overlay = document.createElement("div");
    overlay.className = "markys-sga-auth-overlay";
    overlay.innerHTML = `
      <section class="markys-sga-auth-card" aria-labelledby="markys-sga-auth-title">
        <img src="/markys-sga.svg" alt="MARKYS SGA" class="markys-sga-auth-logo">
        <h1 id="markys-sga-auth-title">Esqueci a senha</h1>
        <p>Informe seu e-mail. Enviaremos um link para criar uma nova senha.</p>
        <form id="markys-sga-recovery-form">
          <label for="markys-sga-recovery-email">E-mail</label>
          <input id="markys-sga-recovery-email" name="email" type="email" autocomplete="username" required>
          <button type="submit" class="markys-sga-auth-submit">Enviar link</button>
          <button type="button" id="markys-sga-back-login" class="markys-sga-auth-submit" style="margin-top:8px;background:#647780">Voltar ao login</button>
          <div class="markys-sga-auth-message" id="markys-sga-recovery-message" role="alert"></div>
        </form>
      </section>`;
    document.body.appendChild(overlay);
    root.classList.remove("markys-sga-auth-checking", "markys-auth-checking");
    const form = overlay.querySelector("#markys-sga-recovery-form");
    const messageBox = overlay.querySelector("#markys-sga-recovery-message");
    if (message) messageBox.textContent = message;
    overlay.querySelector("#markys-sga-back-login").addEventListener("click", () => showLogin(""));
    form.addEventListener("submit", async event => {
      event.preventDefault();
      const button = form.querySelector('button[type="submit"]');
      button.disabled = true;
      button.textContent = "Enviando...";
      messageBox.textContent = "";
      try {
        const email = form.elements.email.value.trim();
        const redirectTo = location.origin + location.pathname + "?flow=recovery";
        const { error } = await client.auth.resetPasswordForEmail(email, { redirectTo });
        if (error) throw error;
        messageBox.textContent = "Se o e-mail estiver cadastrado, você receberá um link para definir uma nova senha.";
      } catch (error) {
        messageBox.textContent = error.message || "Não foi possível enviar o link. Tente novamente.";
      } finally {
        button.disabled = false;
        button.textContent = "Enviar link";
      }
    });
  }

  function showLogin(message) {
    if (overlay) overlay.remove();
    overlay = document.createElement("div");
    overlay.className = "markys-sga-auth-overlay";
    overlay.innerHTML = `
      <section class="markys-sga-auth-card" aria-labelledby="markys-sga-auth-title">
        <img src="/markys-sga.svg" alt="MARKYS SGA" class="markys-sga-auth-logo">
        <h1 id="markys-sga-auth-title">MARKYS SGA</h1>
        <p>Acesse sua conta para entrar no aplicativo.</p>
        <form id="markys-sga-auth-form">
          <label for="markys-sga-auth-email">E-mail</label>
          <input id="markys-sga-auth-email" name="email" type="email" autocomplete="username" required>
          <label for="markys-sga-auth-password">Senha</label>
          <input id="markys-sga-auth-password" name="password" type="password" autocomplete="current-password" required>
          <button type="submit" class="markys-sga-auth-submit">Entrar</button>
          <button type="button" id="markys-sga-forgot-password" class="markys-sga-auth-submit" style="margin-top:8px;background:#647780">Esqueci a senha</button>
          <div class="markys-sga-auth-message" id="markys-sga-auth-message" role="alert"></div>
        </form>
      </section>`;
    document.body.appendChild(overlay);
    root.classList.remove("markys-sga-auth-checking", "markys-auth-checking");
    if (message) overlay.querySelector("#markys-sga-auth-message").textContent = message;
    const form = overlay.querySelector("#markys-sga-auth-form");
    overlay.querySelector("#markys-sga-forgot-password").addEventListener("click", () => showRecovery(""));
    form.addEventListener("submit", async event => {
      event.preventDefault();
      const button = form.querySelector('button[type="submit"]');
      const messageBox = form.querySelector("#markys-sga-auth-message");
      const email = form.elements.email.value.trim();
      const password = form.elements.password.value;
      button.disabled = true;
      button.textContent = "Verificando...";
      messageBox.textContent = "";
      try {
        const { error } = await client.auth.signInWithPassword({ email, password });
        if (error) throw error;
        await validateSession();
      } catch (error) {
        messageBox.textContent = error.message || "Não foi possível entrar. Confira seus dados.";
      } finally {
        button.disabled = false;
        button.textContent = "Entrar";
      }
    });
  }

  function addLogoutButton() {
    if (document.getElementById("markys-sga-logout")) return;
    const profile = cloud.profile;
    if (profile && ["master", "financeiro"].includes(profile.role) && !publicMode && !financeMode && !document.getElementById("markys-sga-finance")) {
      const financeButton = document.createElement("a");
      financeButton.id = "markys-sga-finance";
      financeButton.href = "/financeiro.html";
      financeButton.textContent = "Financeiro";
      financeButton.setAttribute("aria-label", "Abrir módulo Financeiro");
      financeButton.style.cssText = "position:fixed;right:280px;bottom:18px;z-index:9998;border:0;border-radius:10px;padding:11px 16px;background:#173b73;color:#fff;text-decoration:none;font:700 13px Segoe UI,Arial,sans-serif;box-shadow:0 4px 16px #0002;cursor:pointer";
      document.body.appendChild(financeButton);
    }
    if (profile && profile.role === "master" && !publicMode && !document.getElementById("markys-sga-admin-logins")) {
      const adminButton = document.createElement("a");
      adminButton.id = "markys-sga-admin-logins";
      adminButton.href = "/admin-logins.html";
      adminButton.textContent = "Administrar logins";
      adminButton.setAttribute("aria-label", "Abrir administração de logins");
      adminButton.style.cssText = "position:fixed;right:154px;bottom:18px;z-index:9998;border:0;border-radius:10px;padding:11px 16px;background:#087f8c;color:#fff;text-decoration:none;font:700 13px Segoe UI,Arial,sans-serif;box-shadow:0 4px 16px #0002;cursor:pointer";
      document.body.appendChild(adminButton);
    }
    const button = document.createElement("button");
    button.id = "markys-sga-logout";
    button.type = "button";
    button.textContent = "Sair da conta";
    button.setAttribute("aria-label", "Sair da conta");
    button.style.cssText = "position:fixed;right:18px;bottom:18px;z-index:9998;border:0;border-radius:10px;padding:11px 16px;background:#20313a;color:#fff;font:700 13px Segoe UI,Arial,sans-serif;box-shadow:0 4px 16px #0002;cursor:pointer";
    button.addEventListener("click", async () => {
      button.disabled = true;
      button.textContent = "Saindo...";
      const { error } = await client.auth.signOut();
      if (error) {
        button.disabled = false;
        button.textContent = "Sair da conta";
        alert("Não foi possível encerrar a sessão: " + (error.message || "tente novamente."));
      }
    });
    document.body.appendChild(button);
  }

  async function validateSession() {
    const { data, error } = await client.auth.getUser();
    if (error || !data.user) {
      if (publicMode) showAccessMessage("Abra esta tela pelo botão disponível na recepção e mantenha uma sessão autorizada.");
      else showLogin("");
      return false;
    }
    const { data: profile, error: profileError } = await client
      .from("profiles")
      .select("id, display_name, role, active")
      .eq("id", data.user.id)
      .maybeSingle();
    if (profileError || !profile || !profile.active) {
      await client.auth.signOut();
      showLogin("Conta sem perfil ativo. Solicite ao administrador a liberação do acesso.");
      return false;
    }
    if (financeMode && !["master", "financeiro"].includes(profile.role)) {
      showAccessMessage("Acesso restrito ao Master e aos usuários com perfil Financeiro.");
      return false;
    }
    if (publicMode && !["master", "recepcao"].includes(profile.role)) {
      showAccessMessage("Abra esta tela pelo botão disponível na recepção. Esta conta não tem permissão para exibir as chamadas.");
      return false;
    }
    if (overlay) {
      overlay.remove();
      overlay = null;
    }
    cloud.resolveAuth(profile);
    await cloud.readQueue({ publicMode });
    addLogoutButton();
    root.classList.remove("markys-sga-auth-checking", "markys-auth-checking");
    return true;
  }

  if (localMode) {
    if (financeMode) {
      showAccessMessage("O módulo Financeiro exige autenticação com perfil Master ou Financeiro.");
      return;
    }
    cloud.resolveAuth({ role: "local", active: true });
    root.classList.remove("markys-sga-auth-checking", "markys-auth-checking");
    return;
  }

  // The hallway display is intentionally public and read-only. It uses a
  // separate anonymous Supabase client and never inherits a staff session.
  if (publicMode) {
    cloud.resolveAuth({ role: "public_display", active: true });
    root.classList.remove("markys-sga-auth-checking", "markys-auth-checking");
    return;
  }

  if (authFlow === "invite" || authFlow === "recovery" || authFlow === "signup") {
    showPasswordSetup(authFlow === "invite" ? "Defina sua senha para ativar o acesso." : "Defina sua nova senha.");
    return;
  }

  client.auth.onAuthStateChange((event) => {
    if (event === "SIGNED_OUT") location.reload();
  });

  validateSession().catch(error => {
    showLogin(error.message || "Não foi possível validar a sessão. Tente novamente.");
  });
})();