# be-data-sync

Deploys the `data-sync` FastAPI service to CentOS/Rocky 8 VMs under systemd.
Only runs on hosts where `be_role == 'service'`.

## Layout

```
ansible.cfg                        inventory + roles_path
inventory/hosts.ini                service group, be_role=service
playbooks/playbook-data-sync.yml   tags: install, deploy
group_vars/service.yml             app_env / redis_host / log_level
roles/be-data-sync/                defaults, tasks, handlers, templates, meta
```

## Usage

Run from `ansible/` — `ansible.cfg` there sets the inventory and roles path.

```bash
ansible-playbook playbooks/playbook-data-sync.yml                 # full run
ansible-playbook playbooks/playbook-data-sync.yml --tags install  # packages, repo, venv
ansible-playbook playbooks/playbook-data-sync.yml --tags deploy   # config + service only
ansible-playbook playbooks/playbook-data-sync.yml --check --diff  # dry run
```

## Key variables

Full list in `defaults/main.yml`.

| Variable | Default | Purpose |
|---|---|---|
| `data_sync_app_env` | `production` | `APP_ENV` |
| `data_sync_log_level` | `INFO` | `LOG_LEVEL` |
| `data_sync_redis_host` | `localhost` | `REDIS_HOST` |
| `data_sync_redis_password` | `""` | must come from vault |
| `data_sync_repo_url` / `_version` | placeholder / `v1.0.0` | source checkout |
| `data_sync_root` | `/srv/data-sync` | app dir; venv at `<root>/venv` |

## REDIS_PASSWORD

Defaults to empty and `deploy.yml` asserts it is set, so a missing credential fails
at deploy rather than starting a service that cannot authenticate.

```bash
ansible-vault create group_vars/service/vault.yml   # data_sync_redis_password: <secret>
ansible-playbook playbooks/playbook-data-sync.yml --ask-vault-pass
```

Delivered via `EnvironmentFile` (`0640 root:data-sync`), not an `Environment=` line —
unit files are world-readable.

## Notes

- **One `be_role` gate** in `tasks/main.yml` wraps both includes, so it applies to
  new tasks automatically.
- **`dnf`, not `yum`** — on Rocky 8 `yum` is a symlink to dnf, and Ansible's `yum`
  module is deprecated (`ansible-lint` fails on it).

## Verified

`ansible-lint` passes at the **production** profile; `--syntax-check` clean; tag
routing and `group_vars` loading confirmed via `--list-tasks` and
`ansible-inventory --host`.
 