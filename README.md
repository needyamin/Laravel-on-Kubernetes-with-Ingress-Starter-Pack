# Laravel on Kubernetes (with Ingress) — Starter Pack

This bundle gives you **everything in one place** to containerize and deploy a Laravel app on Kubernetes with an Nginx Ingress.

## What’s inside

- `Dockerfile` — Multi‑stage build with PHP‑FPM 8.3 + Nginx via Supervisor.
- `.docker/` — PHP/Nginx/Supervisor configs.
- `k8s/` — Namespace, ConfigMap, Secret, PVC, Deployment, Service, Ingress, HPA, and a `kustomization.yaml`.

## Quick start

1. **Set secrets / config**
   - Edit `k8s/secret-app.yaml` (DB creds, `APP_KEY`, `APP_URL`).
   - Edit `k8s/configmap-app.yaml` to adjust non‑secret envs.
   - Set a valid `storageClassName` in `k8s/pvc.yaml` (or remove that line to use your cluster default StorageClass).

2. **Build & push your image**
   ```bash
   docker build -t yourrepo/laravel-app:latest .
   docker push yourrepo/laravel-app:latest
   ```
   - Update `image:` in `k8s/deployment.yaml` accordingly.

3. **Apply to your cluster**
   ```bash
   kubectl apply -k k8s/
   ```

4. **Ingress / DNS / TLS**
   - Replace `laravel.example.com` in `k8s/ingress.yaml` with your domain.
   - If using cert-manager, uncomment TLS bits and set `cert-manager.io/cluster-issuer`.
   - Point DNS A/AAAA records at your Ingress Controller’s external IP.

5. **Laravel storage & cache**
   - A PVC is mounted at `/var/www/html/storage` for persistent files.
   - `/var/www/html/bootstrap/cache` uses `emptyDir` (ephemeral).

6. **Health checks**
   - Readiness probe points to `/healthz`. Add a simple route in `routes/web.php`:
     ```php
     Route::get('/healthz', fn() => response('OK', 200));
     ```

7. **Scaling**
   - HPA targets 70% CPU utilization between 2–10 replicas. Tweak in `k8s/hpa.yaml`.

## Notes
- If you already serve assets via a CDN, adjust Nginx cache headers in `.docker/default.conf`.
- For Redis/Queue/Octane, add the relevant envs to `k8s/secret-app.yaml` and side services in your cluster.
- If you prefer a sidecar Nginx instead of the combined image, swap the Dockerfile and split into two containers in the Deployment.
