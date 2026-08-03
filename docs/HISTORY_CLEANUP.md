# History cleanup

Removing a file from the current tree does not remove it from earlier commits. Before publishing a remediated history:

1. Make a fresh mirror clone.
2. Create a protected backup of the existing repository.
3. Use `git filter-repo` to remove prohibited paths and rewrite prohibited text.
4. Run the provenance audit against every reachable revision.
5. Review tags and release assets separately.
6. Force-push only after the owner approves the rewritten history.
7. Ask collaborators to clone the rewritten repository again.

GitHub may retain unreachable objects temporarily. Sensitive material must be considered compromised and rotated; repository owners can contact GitHub Support for server-side removal.
