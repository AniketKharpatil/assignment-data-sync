# be-data-sync

Deploys the `data-sync` FastAPI service to CentOS/Rocky 8 VMs under systemd,
following the platform's `be-{service}` role naming convention.

The role only acts on hosts where `be_role == 'service'`; everything else is
skipped.

## Layout

The Ansible tree lives under `ansible/` to keep the VM estate separate from the
Kubernetes artefacts in `helm/` and `standard/`. Paths below are relative to
`ansible/`:

```
ansible.cfg                        inventory + roles_path
inventory/hosts.ini                `service` group, be_role=service
playbooks/playbook-data-sync.yml   tags: install, deploy
group_vars/service.yml             data_sync_app_env / _redis_host / _log_level
roles/be-data-sync/
  defaults/main.yml   tasks/{main,install,deploy}.yml   handlers/main.yml
  templates/{data-sync.service.j2,data-sync.env.j2}     meta/main.yml
```

## Usage

Run from the `ansible/` directory — `ansible.cfg` there sets the inventory and
`roles_path`, which is also what makes `group_vars/service.yml` load.

```bash
cd ansible

ansible-playbook playbooks/playbook-data-sync.yml                  # full run
ansible-playbook playbooks/playbook-data-sync.yml --tags install   # packages, repo, venv
ansible-playbook playbooks/playbook-data-sync.yml --tags deploy    # config + service only
ansible-playbook playbooks/playbook-data-sync.yml --check --diff    # dry run
```

`--tags deploy` is the common case: it re-renders the env file and unit, then
restarts via handler, without touching packages or the git checkout.

## Variables

Full list in `defaults/main.yml`. The ones you are most likely to set:

| Variable | Default | Purpose |
|---|---|---|
| `data_sync_app_env` | `production` | `APP_ENV` |
| `data_sync_log_level` | `INFO` | `LOG_LEVEL` |
| `data_sync_redis_host` | `localhost` | `REDIS_HOST` |
| `data_sync_redis_port` | `6379` | `REDIS_PORT` |
| `data_sync_redis_password` | `""` | `REDIS_PASSWORD` — **must** come from vault |
| `data_sync_repo_url` | placeholder | Source repo to clone |
| `data_sync_repo_version` | `v1.0.0` | Tag/commit to check out |
| `data_sync_root` | `/srv/data-sync` | Checkout lives in `<root>/src` |
| `data_sync_venv` | `/srv/data-sync/venv` | Virtualenv path |
| `data_sync_workers` | `4` | `WORKERS` (uvicorn) |
| `data_sync_max_connections` | `100` | `MAX_CONNECTIONS` |

## REDIS_PASSWORD

`data_sync_redis_password` defaults to empty and `deploy.yml` asserts it is set,
so a missing credential fails loudly at deploy time rather than starting a
service that cannot authenticate.

Supply it from an encrypted file:

```bash
cd ansible
ansible-vault create group_vars/service/vault.yml
# data_sync_redis_password: <secret>

ansible-playbook playbooks/playbook-data-sync.yml --ask-vault-pass
```

Ansible loads `group_vars/service.yml` and everything under
`group_vars/service/`, merging both, so the vault file drops in alongside the
existing file with nothing to move.

The password reaches the service through an `EnvironmentFile`
(`/etc/data-sync/data-sync.env`, mode `0640 root:data-sync`) rather than an
`Environment=` line in the unit — unit files under `/etc/systemd/system` are
world-readable, so an inlined secret would be visible to every local user. The
template task also sets `no_log: true` so the rendered value stays out of logs
and `--diff` output.

## Design notes

**`be_role` gate in one place.** `tasks/main.yml` wraps both includes in a single
`when: be_role == 'service'` block instead of repeating `when:` per task. It
applies to new tasks automatically; the cost is that a skipped host reports one
skip rather than several.

**`dnf`, not `yum`.** The assignment says "via yum". On Rocky/CentOS 8 the `yum`
command is a symlink to dnf, and Ansible's `yum` module is deprecated in favour
of `ansible.builtin.dnf` — `ansible-lint` fails the `fqcn` rule on the old name.
Same package manager, current module name.

**Pinned checkout.** `data_sync_repo_version` defaults to a tag, not `main`. A
branch makes every run non-reproducible and silently ships whatever landed
upstream.

**Idempotence.** `dnf`, `git`, `pip`, `template`, and `systemd_service` are all
idempotent, so a second run reports no changes unless the pinned version or a
variable actually changed. The `git` task reports *changed* when the remote has
moved, which is accurate rather than noise.

## Additions beyond the task list

Called out for review, in the same spirit as Part 1's extras:

- **Dedicated `data-sync` user/group**, with the unit running as it rather than
  root. Running a network service as root is avoidable.
- **`EnvironmentFile` + the `assert`** for `REDIS_PASSWORD`. The task list names
  `APP_ENV`, `LOG_LEVEL`, and `REDIS_HOST`; the service also needs a Redis
  password, and it should not be readable by every local user.
- **systemd hardening** (`ProtectSystem=strict`, `NoNewPrivileges`, and similar).
  Cheap, and `ReadWritePaths` keeps the service able to write to its own tree.
- **`ansible.cfg`, `inventory/hosts.ini`, `.ansible-lint`** — needed to make the
  tree runnable and lintable at all.

## Verification

Run in WSL Ubuntu 24.04 with `ansible-lint 26.8.0` / `ansible-core 2.21.3`:

```
ansible-lint                          Passed: 0 failure(s), 0 warning(s)
                                      profile 'production' was required, and it passed
ansible-playbook --syntax-check       ok
--tags install / --tags deploy        correct task selection (verified via --list-tasks)
ansible-inventory --host              group_vars load; be_role=service resolves
```

**Not verified:** an actual run against a Rocky 8 host. That needs a real VM, so
package installation, the git clone, the venv build, and systemd behaviour are
untested end to end. The logic is idempotent by construction, but treat a first
real run as unproven.

One environment note: on a Windows checkout accessed through WSL (`/mnt/c`),
Ansible ignores `ansible.cfg` because the mount is world-writable, so role
resolution needs `ANSIBLE_ROLES_PATH=roles`. On a normal Linux checkout the
config loads and no override is needed — confirmed by copying the tree to a
native path and re-running clean.
