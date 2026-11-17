# Patches

`third_party/libdivecomputer/` is always the pinned upstream commit plus the
*.patch files in this directory, applied in name order with `git apply`.
`tool/update_upstream.sh` is the only thing that changes the tree.

Every patch goes upstream to Jef Driesen first; there is no private fork. Each
patch has a `patch <file name> <upstream status>` line in `../UPSTREAM`. When
upstream has merged one, delete it in the PR that moves the pin.

Current patches: none.

When you add one, list it here with its file name in backticks, with what it fixes
and a link to the upstream submission.
