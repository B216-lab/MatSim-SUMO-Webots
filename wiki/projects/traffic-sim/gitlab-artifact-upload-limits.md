# GitLab CI artifact upload limit (HTTP 413)

## Symptom

`karla-marksa:visualize` (and other jobs with MP4 artifacts) finish successfully, then fail at **Uploading artifacts**:

```text
ERROR: Uploading artifacts as "archive" to coordinator... 413 Request Entity Too Large
FATAL: too large
```

A ~1.5 MB MP4 triggers this. The simulation and recording are fine; **nginx in front of GitLab** is rejecting the POST body.

nginx’s default `client_max_body_size` is **1 m**. That is unrelated to recording duration — shortening the clip only dodges the misconfiguration.

## Fix (GitLab server admin on `ilab-irk.ru`)

Apply **both** layers below. If GitLab sits behind another reverse proxy, raise the limit there too.

### 1. GitLab application limit

**Admin Area → Settings → CI/CD → Maximum artifacts size (MB)**

Set to at least **100** (GitLab default) or higher, e.g. **500**. Save.

Also check **project/group** overrides: **Settings → CI/CD → General pipelines → Maximum artifacts size**.

### 2. GitLab Omnibus nginx (`/etc/gitlab/gitlab.rb`)

On the GitLab host:

```ruby
# Allow large artifact uploads from runners (0 = unlimited).
nginx['client_max_body_size'] = '0'

# Application-side cap in MB (must be >= largest expected artifact).
gitlab_rails['max_artifacts_size'] = 500
```

Then:

```bash
sudo gitlab-ctl reconfigure
sudo gitlab-ctl hup nginx
```

Or use the helper script in this repo (copy to the GitLab server and run as root):

```bash
sudo ./scripts/gitlab/fix-artifact-upload-413.sh
```

### 3. External reverse proxy (if any)

If `ilab-irk.ru` terminates TLS on a **separate** nginx/ingress (not Omnibus), add inside the `server` block:

```nginx
client_max_body_size 0;
```

Reload that proxy after editing.

### Verify

From **webots-vm** (where the runner uploads artifacts):

```bash
# Replace SIZE with bytes to test; 2097152 = 2MB probe
./scripts/gitlab/probe-artifact-upload-limit.sh https://ilab-irk.ru 2097152
```

After the fix, re-run `karla-marksa:visualize` — a 300 s WeBots MP4 (~1.5–2 MB) should upload without 413.

## References

- [GitLab: Error 413 when uploading artifacts](https://support.gitlab.com/hc/en-us/articles/23156779679004-Error-413-Request-Entity-Too-Large-Error-when-uploading-artifacts)
- [Maximum artifacts size (instance / group / project)](https://docs.gitlab.com/ee/administration/settings/continuous_integration.html#maximum-artifacts-size)
