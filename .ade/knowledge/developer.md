# Developer knowledge

- 2026-11-09: macOS `script -q /dev/null cmd` refuses a mkfifo as stdin ("tcgetattr/ioctl: Operation not supported on socket", exit 1); feed it a real pipe. `wait` on the `$!` of a background pipeline waits for the whole pipeline, so kill a never-closing writer before waiting. lib.sh's fallback `timeout` runs the command with `&`, which gives it /dev/null as stdin in a non-interactive shell: don't use it to test stdin handling.
