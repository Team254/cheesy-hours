# In parentdir mode, Pathological will not add the individual specified paths to $LOAD_PATH, but will instead
# add the unique parents of the specified paths. This is to enable compatibility with legacy code where
# require paths are all written relative to a common repository root.

require "pathological/base"

Pathological.parentdir_mode
Pathological.add_paths!
