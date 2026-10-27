# cmux-berth

Open a tmux session on a remote machine as a row in the cmux sidebar on your Mac, filed under a group named for its repo, and never open the same one twice.

```
cmux-berth                     # pick a remote session with fzf
cmux-berth webapp_login-fix    # open that session by name
cmux-berth -n                  # a fresh shell on the remote, outside any group
```

## What problem does this solve?

If your agents run on a remote box in tmux, one session per worktree, and you drive them from cmux on a Mac, you want each session as its own sidebar row: cmux shows an agent's status on the row, and a row shows only its most urgent tab, so one row per session gives every agent its own status line. You also want the rows grouped by repo, and you want reopening a session to take you to its existing row rather than stacking a duplicate.

`cmux ssh` gets you a row, but it makes a new one on every call and knows nothing about groups. cmux-berth does the bookkeeping around it:

1. It asks the remote for its tmux sessions, and works out the repo each one belongs to from the git common directory under the session's working directory, so a session in a worktree still names its main repo.
2. It finds the repo's group: first by the key it gives the groups it creates (`cmux-berth:<repo>`, which survives renaming the group), then by a group named exactly `<repo>`, so a group you made by hand is adopted.
3. If that group already holds a row with this session's name, it selects that row and stops.
4. Otherwise it opens a `cmux ssh` row named for the worktree, attaches the tmux session in it, and adds it to the group, creating the group first when there is none.
5. A few seconds later it sends the row's name again, twice. The remote end can push its own placeholder name (`workspace-N`) back after cmux's rename, and a row left with the placeholder is one step 3 would never find again. This race was seen in practice; the cause is inferred from cmux's source rather than caught in the act.

## What session naming does it expect?

A worktree's session is `<repo>_<worktree>` and the main checkout's is `<repo>`. That is what [worktree-orchard](https://github.com/DivisionSt/worktree-orchard) creates, but any tool or habit that follows it works. The row gets the short name: `<worktree>`, or `main` for the main checkout. A session that does not follow the convention still opens; its row just carries the full session name, under the group for whatever repo its directory belongs to.

Session names must be letters, digits, `.`, `-` and `_`. The name is typed into the remote shell, so anything else is refused rather than quoted.

## What do I need?

| Requirement | Where | Why |
|---|---|---|
| cmux | The Mac | The sidebar this fills. It uses `cmux ssh`, `cmux rpc` and `cmux workspace-group`; it was built and tested against cmux 0.65. |
| ssh | The Mac | To list the remote's sessions. Set the host up in `~/.ssh/config` so `ssh <host>` works without prompts. |
| jq | The Mac | To read cmux's JSON. |
| fzf 0.46 or newer | The Mac | Only for the picker. Pass a session name to skip it. |
| bash, tmux, git | The remote | The session listing runs `bash -s` there. |

## How do I install it?

```bash
git clone https://github.com/DivisionSt/cmux-berth.git
cd cmux-berth
make install          # symlinks into ~/.local/bin; PREFIX=... to change
```

Give it a short name if you like: `alias cx=cmux-berth`.

Then tell it which host to use, in any one of three places:

```bash
cmux-berth -H my-dev-box                                   # per call
export CMUX_BERTH_HOST=my-dev-box                          # per shell
mkdir -p ~/.config/cmux-berth && echo 'host = my-dev-box' > ~/.config/cmux-berth/config
```

There is no default host. Without one it stops and says where to set it.

## How do I use it?

| Command | What happens |
|---|---|
| `cmux-berth` | Open the picker: every remote session, grouped and coloured by repo. |
| `cmux-berth <session>` | Open that session by its exact tmux name. |
| `cmux-berth -n [name]` | Open a plain shell in `~` on the remote, outside any group, for setting up a new worktree or session by hand. `--new` works too. Without a name, cmux picks `workspace-N`. |
| `cmux-berth -H <host> ...` | Any of the above against another host. `-H` must come first. |
| `cmux-berth -h` | The built-in help. |

In the picker, search starts off so single keys act:

| Key | Action |
|---|---|
| `enter` | Open the highlighted session. |
| `n` | Open a new plain shell. The first entry in the list does the same. |
| `j` `k` | Down, up. |
| `/` | Start filtering. |
| `esc` | In filter mode, back to the list. On the list, quit. |
| `q` | Quit. |

## How do I configure it?

Settings come from the `-H` flag, then the environment, then `~/.config/cmux-berth/config` (or `$XDG_CONFIG_HOME/cmux-berth/config`, or wherever `CMUX_BERTH_CONFIG` points). The file is `key = value` lines with `#` comments, and it is parsed, never sourced. See [`examples/config`](examples/config).

| Key | Environment | Default | What it does |
|---|---|---|---|
| `host` | `CMUX_BERTH_HOST` | none | The ssh host. Required. |
| `rename_delays` | `CMUX_BERTH_RENAME_DELAYS` | `2 4` | Seconds before each late rename (step 5 above). An empty value in the environment turns the late renames off. |
| | `CMUX_BERTH_CONFIG` | | Use another config file. |

## What should I know before it bites?

- The attach runs once. cmux types the attach command into the row's first terminal one time and never again on reconnect. cmux keeps that terminal alive on the remote across lid closes and network changes, so the attach persists, but after the remote itself restarts, the row comes back as a plain shell.
- A new group is created empty, the way the sidebar's own "new group" makes one, and the session's row is then added to it. Creating the group from the session's row instead made that row the group's header rather than a member.
- A row is matched by its title within the repo's group. A row with the same title in another group is a different row and is left alone.
- If opening the row works but filing it into a group fails, the row stays open, named, and ungrouped, and cmux's own error is printed.

## How do I work on it?

```bash
make test    # the test suite
make lint    # shellcheck at warning level
```

The tests replace ssh, cmux and fzf with stand-ins that answer in the shapes cmux really prints and record every call, so they run anywhere and assert on the exact commands cmux-berth would send.

## How are versions numbered?

With [semantic versioning](https://semver.org), released as git tags (`v0.1.0`) with notes on the [releases page](https://github.com/DivisionSt/cmux-berth/releases). Install a tag rather than `main` if you want to choose when you take changes.

The interface the version number protects is the command's flags; the config keys and what they mean; the `CMUX_BERTH_*` environment variables; the session naming it expects; and the `cmux-berth:<repo>` key it gives the groups it creates. A change that breaks any of those is a major version; a new feature is a minor version; a fix is a patch. While the major version is 0, a minor version may still break something, and its release notes say what.

## How do I report a problem or contribute?

Bugs and ideas go in [issues](https://github.com/DivisionSt/cmux-berth/issues). Security problems go through the private route in [SECURITY.md](SECURITY.md). [CONTRIBUTING.md](CONTRIBUTING.md) says what to expect from a pull request and what it has to pass.

## License

[MIT](LICENSE).
