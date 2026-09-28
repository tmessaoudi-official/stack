#!/bin/bash
set -euo pipefail

GLOBAL_STACK_DOCKER_USER_CONFIG="${GLOBAL_STACK_DOCKER_USER_CONFIG:-"/home/${GLOBAL_STACK_DOCKER_USER_ID:-}:${GLOBAL_STACK_DOCKER_GROUP_ID:-}"}"

echo -e "\nGLOBAL_STACK_DOCKER_USER_CONFIG : '${GLOBAL_STACK_DOCKER_USER_CONFIG}' \n"

if [[ "${GLOBAL_STACK_DOCKER_USER_CONFIG:-}" != ":" && "${GLOBAL_STACK_DOCKER_USER_CONFIG:-}" != "" ]]; then
    IFS=',' read -ra GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIRS <<< "${GLOBAL_STACK_DOCKER_USER_CONFIG}"

    for GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIR in "${GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIRS[@]}"; do

        echo -e "\nGLOBAL_STACK_BASE_USER_HOME_GROUP_PAIR : '${GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIR}' \n"

        IFS=':' read -r GLOBAL_STACK_BASE_USER_HOME GLOBAL_STACK_BASE_GROUP <<< "${GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIR}"

        echo -e "\nGLOBAL_STACK_BASE_USER_HOME : '${GLOBAL_STACK_BASE_USER_HOME}' \n"
        echo -e "\nGLOBAL_STACK_BASE_GROUP : '${GLOBAL_STACK_BASE_GROUP}' \n"
        
        GLOBAL_STACK_BASE_USERNAME=$(basename "${GLOBAL_STACK_BASE_USER_HOME}")

        echo -e "\nGLOBAL_STACK_BASE_USERNAME : '${GLOBAL_STACK_BASE_USERNAME}' \n"

        if [[ -d "${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/home/user" && -d "${GLOBAL_STACK_BASE_USER_HOME}" ]]; then
            echo -e "\nrsynching ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/home/user/ into ${GLOBAL_STACK_BASE_USER_HOME} \n"
            # --exclude the two shell history files. docker/config/root is bind-mounted
            # BOTH as this rsync's SOURCE (/stack/dist/home/user) and as the destination
            # files themselves (/home/developer/.bash_history, .zsh_history) -- same inode
            # on both sides. So rsync copied each onto itself and could not rename over its
            # own bind mount ("Device or resource busy"), producing a code-23 error on every
            # boot in 28 of 45 containers. Shared history comes from the BIND MOUNT, not
            # from here: this copy has never once succeeded, and sharing works anyway.
            # Removing it also restores meaning to exit 23, which the guard below would
            # otherwise swallow on every boot, hiding a genuine copy failure.
            # The literals are pinned to GLOBAL_STACK_SHELL_*_TARGET by startup-prologue §38c.
            sudo rsync -raz --ignore-times \
                --exclude=.bash_history \
                --exclude=.zsh_history \
                ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/home/user/ \
                ${GLOBAL_STACK_BASE_USER_HOME} \
                || { _rsync_exit=$?; [ $_rsync_exit -eq 23 ] && echo "rsync exit 23: some files busy/locked (e.g. .bash_history), continuing" || exit $_rsync_exit; }
        fi

        if [[ -d "${GLOBAL_STACK_BASE_USER_HOME}" ]]; then
            echo -e "\nSetting permissions ${GLOBAL_STACK_BASE_USERNAME}:${GLOBAL_STACK_BASE_GROUP} to ${GLOBAL_STACK_BASE_USER_HOME}/ \n"
            # Set ownership for the user's home directory
            sudo chown -R "${GLOBAL_STACK_BASE_USERNAME}:${GLOBAL_STACK_BASE_GROUP}" "${GLOBAL_STACK_BASE_USER_HOME}/"

            # Set permissions for files and directories.
            #
            # The file arm SUBTRACTS, it does not assign. A numeric `chmod 600` also
            # removes the OWNER's execute bit, and this script runs from the entrypoint
            # of every container -- so any executable a tool caches under $HOME is
            # disarmed on the next boot. Measured [2026-09-11]: the `android` launcher
            # downloads the real 87 MB CLI to ~/.android/bin/android-cli at 0755 and
            # execs it; after one restart it is -rw------- and the reinstall dies with
            # `Failed to exec android binary: Permission denied (os error 13)`. Same
            # class, same day, second container: serverless v4 caches sf-core.js,
            # esbuild and invoke.py under ~/.serverless/releases/<ver>/ at 0755.
            #
            # It hid because it is ARMED, not always-firing: a normal boot never runs
            # `android` (gs_version_gate returns skip, and avdmanager is a shell script
            # calling java directly), so only a reinstall boot -- an .env bump of any of
            # the 12 pinned SDK inputs, RELOAD_ANDROID=true, make soft-restart -- meets
            # a cache that the previous boot already stripped.
            #
            # `ug-s,go-rwx` expresses what was actually wanted: every group and other
            # bit gone, setuid/setgid gone, the owner's bits untouched. It can only
            # PRESERVE an x that was already there, never add one, so no file that is
            # non-executable today becomes executable. Measured, all modes:
            #   4755 -> -rwx------   0755 -> -rwx------   0777 -> -rwx------
            #   2644 -> -rw-------   0644 -> -rw-------   0600 -> -rw-------
            # ssh is the constraint that motivated 600 and it is satisfied: OpenSSH
            # rejects a private key only on a group/other bit (`mode & 077`), so 0700
            # is accepted exactly like 0600 [measured against a real sshd: 600 and 700
            # accepted, 640/660/604 rejected "UNPROTECTED PRIVATE KEY FILE"].
            #
            # `ug-s` is not redundant belt-and-braces: `chmod 600` cleared setuid
            # unconditionally, and while the `chown -R` above happens to clear it too
            # (the kernel drops setuid on chown(2) of a regular file), relying on that
            # would make an unconditional guarantee depend on statement order.
            #
            # A `.docker/cli-plugins` arm used to follow, re-adding `a+x` to one
            # directory -- the same class, noticed once and patched in one place. It is
            # deleted rather than joined by a second special case: it never fired (no
            # container has that directory; docker's plugins live in
            # /usr/libexec/docker/cli-plugins), and under the rule above a plugin
            # arriving at 0755 keeps owner-execute with no exception needed.
            find "${GLOBAL_STACK_BASE_USER_HOME}/" -type f -exec sudo chmod ug-s,go-rwx {} +
            find "${GLOBAL_STACK_BASE_USER_HOME}/" -type d -exec sudo chmod 700 {} +

            eval "$(ssh-agent -s)" 1> /dev/null 2> /dev/null
        fi
    done
fi
