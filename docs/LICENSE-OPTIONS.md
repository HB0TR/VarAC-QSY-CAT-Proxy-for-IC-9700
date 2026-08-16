# License options

This file is a practical decision guide, not legal advice.

## Recommended default: MIT

**Best fit if your goal is wide amateur-radio adoption with minimal friction.**

- Permissive: others may use, modify, redistribute, and include the code in other projects.
- Simple and widely understood.
- Requires preservation of the copyright and license notice.
- Does **not** require modified versions to remain open source.

For this small standalone utility, MIT is the recommended default. The prepared repository therefore contains an MIT `LICENSE` file.

## Alternative: Apache License 2.0

**Best fit if you want a permissive license with an explicit patent grant and a more formal notice structure.**

- Permissive, like MIT.
- Includes an explicit patent licence from contributors.
- Supports a `NOTICE` file mechanism.
- Longer and more complex than MIT.

Choose Apache-2.0 if patent language and formal contribution terms matter to you.

## Alternative: GNU GPL v3

**Best fit if you want derivatives that are distributed to remain under the same open-source licence.**

- Strong copyleft.
- Modified/distributed versions must generally provide corresponding source under GPLv3 terms.
- Good if keeping improvements open is more important than maximum reuse flexibility.
- Can be less convenient for integration into projects using incompatible licensing models.

## What if you want "free for radio amateurs, no commercial use"?

That is a **source-available** model, not a standard open-source model, because an open-source licence cannot prohibit commercial use. A custom non-commercial licence also creates compatibility and interpretation problems. For this project, a standard OSI-approved licence is preferable unless you have a specific commercial restriction goal and are willing to get legal advice.

## Attribution

If keeping the author's identity visible is important, use standard licensing plus project metadata rather than inventing a custom licence clause:

- `NOTICE`
- `CITATION.cff`
- the program title line
- the README author section
- source-file copyright headers

The prepared V5.00 repository includes these attribution mechanisms.
