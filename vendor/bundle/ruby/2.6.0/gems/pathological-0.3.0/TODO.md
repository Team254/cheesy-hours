TODO
====

Tasks
-----

  * Get all loaded files that come from Pathological directories (probably only in 1.9)

Design decisions
----------------

  * Should we allow for including other Pathfiles? Proposed syntaxes:

        include path/to/other/Pathfile
        import path/to/other/Pathfile   # Rakefile
        i path/to/other/Pathfile
        source path/to/other/Pathfile   # Bash
        . path/to/other/Pathfile        # Bash
        path/to/other/Pathfile          # Distinguishable from regular path if Pathfile is not a directory

    **Not needed now --Caleb**

  * Do we like `>` to signify directives? Alternatives:

        > exclude-root # Current syntax
        exclude-root  # Only problem is if you want to include a directory with the same name as a directive

    We could also prefix each type of line to make things unambiguous:

        p path/to/lib/
        d exclude-root

    **Fine for now --Caleb**

  * Right now there's a small problem with comments: if your path includes the character `#`, then the rest
    will be chopped off (interpreted as a comment). We could remedy this by only allowing for comments to
    start at the beginning of lines:

        # Yes
        ../lib/ # No

    **Let's leave this alone for now; probably a non-issue --Caleb**

  * Right our require paths tend to look like this (using `shared_lib/` as an example):

    ``` ruby
    require "shared_lib/utils/foo_util"
    ```

    To support this, you would need your `Pathfile` to include the directory *above* `shared_lib/`. The
    downside of this is that it doesn't play well with the idea of using our `Pathfile`s to tell our deploy
    scripts what to include. We could potentially add a new construct to allow the user to specify which
    subdirectories they would be using. Example (just off the top of my head):

        path/to/repo/dir/{shared_lib, common, vendor}

    However, we'd still have to add `path/to/repo/dir` to the `$LOAD_PATH`, so the only way to enforce this at
    require time would be to use a custom `require`. This is all quite a high cost to pay in terms of design
    simplicity, but yet being able to use Pathfiles as a single place to document what dependencies to pull in
    seems very appealing. Any ideas?

    **After chatting with some people, we're going to leave this as is and truncate the `shared_lib` from our
    paths. --Caleb**

    **Actually, I think I'm going to add an optional mode to add one directory _above_ to the load path
    instead of the given path, in order to accomomdate this use case. --Caleb**
