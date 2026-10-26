# cmux-berth

One bash script, `bin/cmux-berth`, that opens remote tmux sessions as cmux sidebar rows. The README is the user documentation and must stay true to the code.

## Checks

```bash
make test
make lint
```


## Rules

- Behaviour is pinned by `tests/`; change a behaviour and its test together. Never weaken a test to make it pass.
- Keep it bash 3.2 compatible: no associative arrays, `mapfile`, `${var,,}` or `local -n`. CI runs the suite under macOS's `/bin/bash`.
- The comments record why each odd-looking choice was made, usually a bug the obvious version had. Keep that density when you change code.
- The config file is parsed, never sourced. Keep it that way.
