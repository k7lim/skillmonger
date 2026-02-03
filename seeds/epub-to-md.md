# seed precursor
the skill development starts with gh cli to clone uxiew/epub2MD and understand how it works

key question: how does it handle images?

# prerequisite
the skill when deployed will first make sure that epub2md is installed on CLI (follow system guidance for dependency hygiene, falling back to known best practices if needed), offering to install if needed

# skill
the skill UX is dead simple, provide a pointer to an epub ebook (or a dirname/wildcard that indicates a group of epubs), and the agent will use epub2md to generate an organized set of md files that mirror the epub's content and structure, making sure to name it uniquely (to avoid mistaken overwrite) and obviously (minimize cognitive load to know what ebook led to which md)

# feedback loop:
qualitative md: asking for immediate qualitative feedback, inviting the user to /resume the chat anytime to give delayed feedback.

objective script: runs to make sure 1) size sanity check passes - the disk usage total is a healthy an expected ratio of compression from the epub original. flag if it's actually somehow LARGER, and 2) tree-shape sanity check passes - the internal epub's document tree should look like the file tree containing the md. 