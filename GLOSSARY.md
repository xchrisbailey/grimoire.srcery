# Grimoire

Grimoire is a Markdown writing app. This glossary records its agreed domain language, including concepts for planned features.

## Language

**Content template**:
Reusable initial content for a newly created document, optionally containing placeholders.
_Avoid_: Filename template, frontmatter rule

**Filename pattern**:
A pattern for a new document's name, distinct from its initial content.
_Avoid_: Content template

**Folder template assignment**:
A project's choice of content template for a folder, inherited by descendants unless a nearer folder overrides it or opts out.
_Avoid_: Folder automation rule

**Template opt-out**:
An explicit folder choice to use no content template, inherited by descendants unless a nearer folder overrides it.
_Avoid_: Missing assignment
