# NAIS

NAIS is a styled nginx autoindex page with convenient playlist download and
link-copying actions.

[Website](https://meghdadfadaee.github.io/nais/) ·
[GitHub](https://github.com/meghdadfadaee/nais)

## Installation

The interactive installer requires nginx, curl, root access through either the
current user or `sudo`, and an nginx service managed by `systemctl` or
`service`:

```sh
curl -fsSL https://meghdadfadaee.github.io/nais/setup.sh | sh
```

It asks for:

- `server_name`: one hostname or IP address.
- `root_path`: the absolute path whose files nginx should list.
- `assets_path`: where the NAIS CSS, JavaScript, and favicon are installed.
  The default is `/var/www/nais-assets`.
- `certificates_path`: an optional directory containing `fullchain.pem` and
  `privkey.pem`.

Without a certificates path, the generated site serves HTTP on port 80. With a
certificates path, it serves HTTPS on port 443 and redirects HTTP to HTTPS.

The installer detects common nginx virtual-host include directories. If none is
configured, it adds a managed `nais-sites/*.conf` include to nginx's main
configuration. It validates changes with `nginx -t` before reloading or starting
nginx. Re-running the installer refreshes the assets and replaces the managed
NAIS site configuration.

The installer does not install nginx or obtain TLS certificates.
The nginx worker user must have permission to traverse and read `root_path`; the
installer does not change permissions on existing content.
