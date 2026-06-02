# git/

Skills and agents that act on the working repo's version control surface: commits, branches, pushes, rebases, conflict resolution. These produce git state changes and may interact with the remote. Provider scripts are not used here. `git` itself is the contract.

The canonical worktree procedure (enter, native-git fallback, teardown) lives in `@~/.autocode/autocode/_config/guides/worktree.md`. Skills that isolate repo changes import it rather than restating the steps.
