(() => {
  "use strict";
  const SUPABASE_URL = "https://vibybosdqavejvqsuvph.supabase.co";
  const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_sTICN13TDw4NGkskMuEHmA_JsjEXt8m";
  if (!window.supabase || typeof window.supabase.createClient !== "function") {
    throw new Error("Biblioteca de conexão com o Supabase não foi carregada.");
  }
  const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
  });
  // The public waiting-room queue is fetched through the same-origin API,
  // which applies a short in-memory cache and reads from the MARKYS SGA Supabase project.
  let queueVersion = 0;
  let lastQueueSnapshot = null;
  let queueReadSequence = 0;
  let queueWritesInProgress = 0;
  let currentProfile = null;
  let publicClinicId = null;
  let resolveAuth;
  let writeChain = Promise.resolve();
  const signedUrlCache = new Map();
  const authReady = new Promise(resolve => { resolveAuth = resolve; });

  function localDay() {
    const now = new Date();
    return [now.getFullYear(), String(now.getMonth() + 1).padStart(2, "0"), String(now.getDate()).padStart(2, "0")].join("-");
  }
  function safeSegment(value) {
    return String(value || "arquivo").normalize("NFKD").replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-zA-Z0-9._-]/g, "_").slice(-110) || "arquivo";
  }
  async function rpc(name, args) {
    const result = await client.rpc(name, args || {});
    if (result.error) {
      const message = result.error.message || "Falha de comunicação com o Supabase.";
      if (result.error.code === "40001" || /QUEUE_CONFLICT/.test(message)) {
        const conflict = new Error("A fila foi atualizada em outro dispositivo. Atualize a tela antes de salvar novamente.");
        conflict.code = "QUEUE_CONFLICT";
        throw conflict;
      }
      const error = new Error(message);
      error.code = result.error.code || "";
      throw error;
    }
    return result.data;
  }
  function isMissingRpc(error) {
    return !!error && (
      error.code === "PGRST202" ||
      error.code === "42883" ||
      /could not find the function|function .* does not exist|schema cache.*function/i.test(error.message || "")
    );
  }
  function cloneQueueSnapshot(queue) {
    return (Array.isArray(queue) ? queue : []).map(patient => {
      const copy = JSON.parse(JSON.stringify(patient));
      if (copy && copy.document && copy.document.path) delete copy.document.url;
      return copy;
    });
  }

  async function createSignedUrl(bucket, path) {
    const key = bucket + ":" + path;
    const cached = signedUrlCache.get(key);
    if (cached && cached.expiresAt > Date.now()) return cached.url;
    const { data, error } = await client.storage.from(bucket).createSignedUrl(path, 3600);
    if (error) throw error;
    const url = data && data.signedUrl;
    if (!url) throw new Error("Não foi possível gerar o link seguro do arquivo.");
    signedUrlCache.set(key, { url, expiresAt: Date.now() + 3300000 });
    return url;
  }
  async function hydratePatientDocuments(queue) {
    await Promise.all(queue.map(async patient => {
      if (patient && patient.document && patient.document.path) {
        try {
          patient.document.url = await createSignedUrl("markys-sga-documents", patient.document.path);
        } catch (_) {
          patient.document.url = "";
        }
      }
    }));
    return queue;
  }

  async function uploadResumable(bucket, path, file, onProgress) {
    if (!window.tus || typeof window.tus.Upload !== "function") {
      throw new Error("O módulo de envio de arquivos grandes não foi carregado. Atualize a página.");
    }
    const { data, error } = await client.auth.getSession();
    if (error) throw error;
    if (!data || !data.session) throw new Error("Sua sessão expirou. Entre novamente.");
    return await new Promise((resolve, reject) => {
      const upload = new window.tus.Upload(file, {
        endpoint: "https://vibybosdqavejvqsuvph.storage.supabase.co/storage/v1/upload/resumable",
        retryDelays: [0, 3000, 5000, 10000, 20000],
        headers: {
          authorization: "Bearer " + data.session.access_token,
          apikey: SUPABASE_PUBLISHABLE_KEY,
        },
        uploadDataDuringCreation: true,
        removeFingerprintOnSuccess: true,
        chunkSize: 6 * 1024 * 1024,
        fingerprint: () => Promise.resolve(bucket + ":" + path),
        metadata: {
          bucketName: bucket,
          objectName: path,
          contentType: file.type || "application/octet-stream",
          cacheControl: "3600",
          metadata: JSON.stringify({ originalName: file.name })
        },
        onError: reject,
        onProgress(bytesUploaded, bytesTotal) {
          if (typeof onProgress === "function") onProgress(Math.floor(bytesUploaded / bytesTotal * 100));
        },
        onSuccess: resolve
      });
      upload.findPreviousUploads().then(previous => {
        if (previous.length) upload.resumeFromPreviousUpload(previous[0]);
        upload.start();
      }).catch(reject);
    });
  }

  window.MARKYS_AUTH_READY = authReady;
  window.MARKYS_CLOUD = {
    client,
    get profile() { return currentProfile; },
    resolveAuth(profile) {
      currentProfile = profile;
      resolveAuth(profile);
    },
    subscribeQueueChanges(callback) {
      if (typeof callback !== "function") return null;
      let active = true;
      let channel = null;
      authReady.then(async profile => {
        if (!active || !profile || !["master", "recepcao", "profissional"].includes(profile.role)) return;
        const { data: sessionData } = await client.auth.getSession();
        if (sessionData && sessionData.session && client.realtime && typeof client.realtime.setAuth === "function") {
          await client.realtime.setAuth(sessionData.session.access_token);
        }
        if (!active) return;
        const clinicId = profile.role === "master" ? (profile.clinic_id || "00000000-0000-4000-8000-000000000001") : profile.clinic_id;
        if (!clinicId) return;
        channel = client.channel("markys-sga-queue-clinic-" + clinicId, { config: { private: true } });
        channel
          .on("broadcast", { event: "queue_changed" }, payload => {
            if (active) callback(payload);
          })
          .subscribe();
      }).catch(() => {});
      return () => {
        active = false;
        if (channel) void client.removeChannel(channel);
      };
    },
    async readQueue(options) {
      await authReady;
      const publicMode = !!(options && options.publicMode);
      const readSequence = publicMode ? 0 : ++queueReadSequence;
      let data;
      if (publicMode) {
        const clinicSlug = (new URLSearchParams(location.search).get("clinic") || "clinica-principal").trim();
        const response = await fetch("/api/public-queue?clinic=" + encodeURIComponent(clinicSlug), {
          method: "GET",
          cache: "no-store",
          credentials: "same-origin"
        });
        if (!response.ok) {
          let message = "Não foi possível carregar as chamadas públicas.";
          try {
            const body = await response.json();
            if (body && body.error) message = body.error;
          } catch (_) {}
          throw new Error(message);
        }
        data = await response.json();
        publicClinicId = typeof data.clinic_id === "string" && /^[0-9a-f-]{36}$/i.test(data.clinic_id) ? data.clinic_id : null;
        if (!publicClinicId) throw new Error("A sala pública recebeu um identificador de clínica inválido.");
      } else {
        const clinicId = currentProfile && currentProfile.role === "master"
          ? (currentProfile.clinic_id || "00000000-0000-4000-8000-000000000001")
          : currentProfile && currentProfile.clinic_id;
        if (!clinicId) throw new Error("Sua conta não está vinculada a uma clínica.");
        data = await rpc("markys_sga_queue_get_tenant", { p_clinic_id: clinicId });
      }
      queueVersion = Number(data && data.version || 0);
      const queue = Array.isArray(data && data.queue) ? data.queue : [];
      if (!publicMode && readSequence === queueReadSequence && queueWritesInProgress === 0) {
        lastQueueSnapshot = cloneQueueSnapshot(queue);
      }
      return publicMode ? queue : await hydratePatientDocuments(queue);
    },
    async writeQueue(queue) {
      await authReady;
      const snapshot = cloneQueueSnapshot(queue);
      // Capture the exact base state when the user action is queued. Reading
      // lastQueueSnapshot later inside writeChain can make a stale UI snapshot
      // look like a fresh edit and silently revert a preceding action.
      const baseSnapshot = lastQueueSnapshot;
      const expectedSnapshot = Array.isArray(baseSnapshot)
        ? cloneQueueSnapshot(baseSnapshot)
        : null;
      queueReadSequence++;
      queueWritesInProgress++;
      const operation = writeChain.then(async () => {
        if (!Array.isArray(expectedSnapshot)) {
          throw new Error("Atualize a fila antes de salvar novamente.");
        }
        const before = new Map();
        const after = new Map();
        for (const patient of expectedSnapshot) {
          const id = String(patient && patient.id || "");
          if (!id || before.has(id)) throw new Error("A fila anterior contém identificadores inválidos ou duplicados.");
          before.set(id, patient);
        }
        for (const patient of snapshot) {
          const id = String(patient && patient.id || "");
          if (!id || after.has(id)) throw new Error("A fila contém identificadores inválidos ou duplicados.");
          after.set(id, patient);
        }
        const changes = [];
        for (const [id, oldPatient] of before) {
          if (!after.has(id)) changes.push({ id, oldPatient, newPatient: null });
        }
        for (const [id, newPatient] of after) {
          const oldPatient = before.has(id) ? before.get(id) : null;
          if (!oldPatient || JSON.stringify(oldPatient) !== JSON.stringify(newPatient)) {
            changes.push({ id, oldPatient, newPatient });
          }
        }
        let appliedChanges = 0;
        try {
          if (changes.length) {
            // Tenant RPC: one atomic queue update, scoped to the clinic.
            const clinicId = currentProfile && currentProfile.role === "master"
              ? (currentProfile.clinic_id || "00000000-0000-4000-8000-000000000001")
              : currentProfile && currentProfile.clinic_id;
            if (!clinicId) throw new Error("Sua conta não está vinculada a uma clínica.");
            const data = await rpc("markys_sga_queue_write_tenant", {
              p_changes: changes.map(change => ({
                id: change.id,
                expected: change.oldPatient,
                patient: change.newPatient
              })),
              p_clinic_id: clinicId
            });
            queueVersion = Number(data && data.version || queueVersion + 1);
            appliedChanges = changes.length;
          }
        } catch (error) {
          // Never keep a stale snapshot after a concurrency conflict.
          // This prevents repeated writes against the same outdated patient state.
          if (error && error.code === "QUEUE_CONFLICT") {
            lastQueueSnapshot = null;
            queueReadSequence++;
          }
          // A multi-patient action may have committed some individual RPCs.
          // Force a fresh read before any retry so stale UI data cannot undo them.
          if (appliedChanges > 0) lastQueueSnapshot = null;
          throw error;
        }
        // If another queued write completed from the same base snapshot, its
        // merged server state is not represented by this UI snapshot. Invalidate
        // the local base so the next action must read the authoritative queue.
        lastQueueSnapshot = lastQueueSnapshot === baseSnapshot ? snapshot : null;
        return true;
      });
      writeChain = operation.catch(() => {});
      try {
        return await operation;
      } finally {
        queueWritesInProgress = Math.max(0, queueWritesInProgress - 1);
      }
    },
    async uploadPatientDocument(patientId, file) {
      await authReady;
      if (!currentProfile || !["master", "recepcao"].includes(currentProfile.role)) {
        throw new Error("Somente a recepção pode anexar documentos de pacientes.");
      }
      if (!file || file.size > 50 * 1024 * 1024 || (file.type && file.type !== "application/pdf")) {
        throw new Error("Anexe um PDF válido de até 50 MB.");
      }
      const clinicId = currentProfile.role === "master" ? (currentProfile.clinic_id || "00000000-0000-4000-8000-000000000001") : currentProfile.clinic_id;
      if (!clinicId) throw new Error("Sua conta não está vinculada a uma clínica.");
      const path = "clinics/" + clinicId + "/patients/" + safeSegment(patientId) + "/" + Date.now() + "-" + safeSegment(file.name);
      if (file.size > 6 * 1024 * 1024) {
        await uploadResumable("markys-sga-documents", path, file);
      } else {
        const { error } = await client.storage.from("markys-sga-documents").upload(path, file, {
          contentType: "application/pdf", upsert: false
        });
        if (error) throw error;
      }
      // The destination path is generated before upload and is the canonical Storage path.
      const storedPath = path;
      const url = await createSignedUrl("markys-sga-documents", storedPath);
      return { name: file.name, path: storedPath, url };
    },
    async listSlideshow() {
      await authReady;
      const isPublicScreen = new URLSearchParams(location.search).get("painel") === "1" || location.pathname === "/sala" || location.pathname === "/sala/";
      if (isPublicScreen) {
        const clinicSlug = (new URLSearchParams(location.search).get("clinic") || "clinica-principal").trim();
        const response = await fetch("/api/public-media?clinic=" + encodeURIComponent(clinicSlug), {
          method: "GET", cache: "no-store", credentials: "same-origin"
        });
        if (!response.ok) throw new Error("Não foi possível carregar as mídias públicas da clínica.");
        const payload = await response.json();
        if (!payload || payload.clinic_slug !== clinicSlug || !Array.isArray(payload.items)) {
          throw new Error("A resposta de mídia pública é inválida.");
        }
        return payload.items;
      }
      const clinicId = currentProfile && currentProfile.role === "master"
        ? (currentProfile.clinic_id || "00000000-0000-4000-8000-000000000001")
        : currentProfile && currentProfile.clinic_id;
      if (!clinicId) throw new Error("Não foi possível identificar a clínica para listar a mídia.");
      const prefix = "clinics/" + clinicId + "/media";
      const { data, error } = await client.storage.from("markys-sga-media").list(prefix, {
        limit: 1000, sortBy: { column: "name", order: "asc" }
      });
      if (error) throw error;
      const files = (data || []).filter(item => item && item.id && item.name);
      return await Promise.all(files.map(async item => {
        const path = prefix + "/" + item.name;
        const signedUrl = await createSignedUrl("markys-sga-media", path);
        const displayName = item.name.replace(/^\\d+_/, "");
        const type = item.metadata && (item.metadata.mimetype || item.metadata.contentType) ||
          (/\\.(mp4|webm|ogg|mov|m4v)$/i.test(displayName) ? "video/" + displayName.split(".").pop().toLowerCase() :
           /\\.(png|jpg|jpeg|gif|webp|avif)$/i.test(displayName) ? "image/" + displayName.split(".").pop().toLowerCase() : "application/octet-stream");
        return { name: displayName, type, url: signedUrl };
      }));
    },
    async uploadSlideshow(file, onProgress) {
      await authReady;
      if (!currentProfile || !["master", "recepcao"].includes(currentProfile.role)) {
        throw new Error("Somente a recepção pode enviar fotos e vídeos para a sala.");
      }
      if (!file || !/^(image|video)\//i.test(file.type) || file.size > 52428800) {
        throw new Error("Envie uma foto ou vídeo de até 50 MB.");
      }
      const clinicId = currentProfile.role === "master" ? (currentProfile.clinic_id || "00000000-0000-4000-8000-000000000001") : currentProfile.clinic_id;
      if (!clinicId) throw new Error("Sua conta não está vinculada a uma clínica.");
      const path = "clinics/" + clinicId + "/media/" + Date.now() + "_" + safeSegment(file.name);
      if (file.size > 6 * 1024 * 1024) {
        await uploadResumable("markys-sga-media", path, file, onProgress);
      } else {
        const { error } = await client.storage.from("markys-sga-media").upload(path, file, {
          contentType: file.type, upsert: false
        });
        if (error) throw error;
      }
      signedUrlCache.delete("markys-sga-media:" + path);
      return true;
    }
  };
})();