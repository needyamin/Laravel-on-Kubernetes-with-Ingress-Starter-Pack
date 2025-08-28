# Laravel on Kubernetes (with Ingress) — Starter Pack

This repository contains a ready-to-use starter pack to containerize and deploy a Laravel application to Kubernetes using a single combined PHP-FPM + Nginx image and an Nginx Ingress in front of it.

> **Goal:** Make it easy to build a production-ready container image for Laravel, store persistent files in a PVC, expose the app via Ingress (with TLS support via cert-manager), and run it with sensible health checks and autoscaling.

---

## Contents of this bundle

- `Dockerfile` — Multi-stage build (Composer vendor stage → php-fpm runtime) using PHP 8.3, Nginx, and Supervisor to run `php-fpm` + `nginx` in one container.
- `.docker/` — Configuration snippets: `php.ini`, `nginx.conf`, `default.conf` (site), `supervisord.conf`.
- `k8s/` — Kubernetes manifests (`namespace`, `configmap`, `secret`, `pvc`, `deployment`, `service`, `ingress`, `hpa`) plus a `kustomization.yaml` to apply them as a group.

---

## High-level architecture & how it works

1. **Build-time (multi-stage Dockerfile):**
   - **Stage `vendor` (Composer image):** Installs PHP dependencies (via `composer install`) and prepares the optimized autoloader. The entire project is copied into `/app` during this stage.
   - **Runtime stage (php:8.3-fpm-alpine):** The compiled application from the `vendor` stage is copied into `/var/www/html` inside the runtime image. This is the image you run in Kubernetes.

2. **Single container runs both PHP & Nginx:** Supervisor starts both `php-fpm` and `nginx`. Nginx serves static files and proxies PHP requests to `php-fpm`.

3. **Kubernetes layer:** Deployment runs pods from the image, mounts a PVC at `/var/www/html/storage` for persistent uploads, exposes the app with a `Service`, and configures external access using an `Ingress` (optionally with TLS via cert-manager).

---

## Where the Laravel framework and app files live

- During build the project is copied into the `vendor` stage at `/app` (`COPY . /app`).
- At runtime the full application is placed in the container at: `/var/www/html`.
  - `public` should map to the Nginx `root` location (this is handled by `.docker/default.conf`).
  - `storage` is backed by a PVC so files persist across pod restarts.

**So:** your Laravel project (the directory containing `composer.json`, `artisan`, `app/`, `routes/`, `public/`, etc.) should be placed in the same folder as the `Dockerfile` when you build the image.

---

## Quick start (detailed)

### Prerequisites

- Docker (build & push capability)
- Kubernetes cluster (minikube, kind, EKS/GKE/AKS, or managed)
- `kubectl` configured to point at your cluster
- (Optional) cert-manager installed in the cluster if you want automated TLS

### 1) Prepare configuration

- **Secrets:** `k8s/secret-app.yaml` — put DB credentials, `APP_KEY`, `APP_ENV`, `APP_DEBUG=false`, `APP_URL`, and other secret env vars here. Prefer creating this secret from the command line or via your secret manager in production.

- **ConfigMap:** `k8s/configmap-app.yaml` — non-secret environment variables (mail driver hostnames, cache driver names, etc.)
- **PVC:** `k8s/pvc.yaml` — set a `storageClassName` compatible with your cluster or remove the field to use the cluster default StorageClass.

**Example:** set an `APP_KEY` before deploying. Create it locally (if not present) using `php artisan key:generate --show` and add it to the secret manifest or pass it via your CI/CD.

### 2) Build & push your image

```bash
docker build -t yourrepo/laravel-app:latest .
docker push yourrepo/laravel-app:latest
```

Update `k8s/deployment.yaml` (or your kustomize overlays) to point `image:` to your pushed image.

### 3) Deploy to Kubernetes

Apply everything via kustomize in the `k8s/` folder:

```bash
kubectl apply -k k8s/
```

This will create the Namespace (if present), Secret, ConfigMap, PVC, Deployment, Service, Ingress, and HPA in the order configured by kustomize.

### 4) Setup Ingress, DNS & TLS

- Edit `k8s/ingress.yaml` and replace `laravel.example.com` with your actual domain.
- If you have cert-manager, uncomment the TLS block and set annotation `cert-manager.io/cluster-issuer: <issuer-name>`.
- Set your DNS A/AAAA records to the external IP of your Ingress Controller.

---

## Useful extra steps

### Local testing of the built image

Run the container locally to sanity check the image:

```bash
# map port 8080 (image exposes 8080)
docker run --rm -p 8080:8080 \
  -e APP_ENV=local -e APP_DEBUG=true \
  -e DB_CONNECTION=sqlite -v $(pwd)/storage:/var/www/html/storage \
  yourrepo/laravel-app:latest

# Visit http://localhost:8080
```

### Run artisan commands in a running pod

```bash
kubectl exec -it deploy/laravel-app -- php artisan migrate --force
kubectl exec -it $(kubectl get pods -l app=laravel-app -o name | head -n1) -- php artisan key:generate
```

For one-off tasks in Kubernetes you can also use a temporary `Job` or `kubectl run --rm -it --image=yourrepo/laravel-app:latest -- php artisan ...`.

---

## Health checks

- **Readiness** points to `/healthz` by default. Add this route to your Laravel routes (e.g. `routes/web.php`):

```php
Route::get('/healthz', fn() => response('OK', 200));
```

- **Liveness** probe can be the same endpoint or a simple PHP CLI script that exits 0.

Make sure probes are tuned so they don't mark pods as unhealthy during normal startup (consider `initialDelaySeconds`).

---

## Storage and file permissions

- PVC is mounted at `/var/www/html/storage` to persist user uploads, generated files, etc.
- `bootstrap/cache` uses `emptyDir` because it is typically ephemeral and safe to regenerate at startup. If you need it persistent, change the manifest.

**Permissions:** The Dockerfile creates a `www` user and chowns app files to `www:www`. If you run into permission issues when developing locally, ensure the host-mounted volumes map correctly and that UID/GID conflicts are handled.

---

## Worker queues, Redis, and background processes

- For queues you will typically run queue workers as separate Deployments (not inside the web container) so they can scale independently. Add `redis`/`database` connection envs to the secret/configmap and create a `Deployment` for `php artisan queue:work` or use a process manager.
- For Octane you would need a different image/runtime configured for Swoole or RoadRunner; this starter focuses on classic PHP-FPM.

---

## HPA and scaling

- The provided HPA (`k8s/hpa.yaml`) targets 70% CPU between 2 and 10 replicas — adjust these numbers to your traffic and cluster resources.
- Remember: scaling stateless web pods is simple, but **shared writable state** (files) should be moved to object storage (S3), or ensure the PVC supports access from many pods (some storage drivers do not).

---

## Security & best practices

- Do not store plaintext credentials in Git. Use sealed-secrets, external secret manager, or create Kubernetes secrets at deploy time.
- Set `APP_DEBUG=false` in production.
- Keep `composer install --no-dev --no-interaction --optimize-autoloader` in your Docker build to avoid shipping dev dependencies.
- Use image scanning and a trusted base image. Keep PHP and system packages up to date.

---

## .dockerignore (recommended)

```
node_modules
vendor
.git
.env
/storage/*
!.storage/.gitkeep
npm-debug.log
docker-compose.override.yml
.docker/**/cache
```

This prevents copying heavy or sensitive folders into the Docker build context.

---

## Common troubleshooting

- **Blank page / 500 errors**: check `kubectl logs` for PHP-FPM and Nginx. Ensure `APP_KEY` is set and `storage` write permissions are correct.
- **Migrations not running**: run migrations with `kubectl exec` or via CI job; check DB connectivity and secrets.
- **Ingress 404**: confirm the `host` in the ingress matches your request `Host` header and that the Ingress Controller is healthy.

---

## CI/CD tips

- Build the image in CI and push to a registry; tag images by git commit SHA.
- Use `kubectl set image` or update your kustomize overlay in CI to perform rolling updates.
- Run `php artisan config:cache` and other cache commands at build time (already attempted in the Dockerfile). If these commands require runtime secrets, run them at container start or in an init container.

---

## Appendix: Useful commands

```bash
# Apply kustomize
kubectl apply -k k8s/

# Show logs
kubectl logs -l app=laravel-app

# Exec into a pod
kubectl exec -it deploy/laravel-app -- /bin/sh

# Run one-off artisan
kubectl run --rm -it --image=yourrepo/laravel-app:latest artisan -- php artisan migrate --force
```

---

## Next steps / customizations

- Split Nginx into a sidecar container if you want clear separation of concerns.
- Replace the `emptyDir` for cache with a shared fast cache storage if required.
- Add a `Job` manifest for running migrations or a `preStop` hook to drain requests gracefully.

---

If you want, I can also:
- Provide an example `docker-compose.yml` for local development.
- Produce a ready-to-use `k8s/deploy-job-migrations.yaml` for running migrations as a Job.
- Convert the combined image into a two-container `Deployment` (php-fpm + nginx sidecar).
