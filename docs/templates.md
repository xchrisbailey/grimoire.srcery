# Content templates

A content template gives new pages in a folder their starting text: frontmatter, headings, whatever you'd otherwise type each time. A template is an ordinary Markdown file that you write and edit like any other page. You assign it to a folder, and every new page in that folder, or in any folder inside it, starts from that file.

## Set up a template

1. In the sidebar, right-click a folder and choose **Content Template…**.
2. Choose **Use a template**, then one of:
   - **Choose Existing File…** to use a Markdown file you already have.
   - **Create Template…** to make a new, empty template file and open it for editing.
3. Write the template's contents and save.

The template file has to be inside a folder bound to the current project. A `templates` folder in a bound root works well, or bind a separate folder just for templates. Several folders can share one template file.

To change a template later, open **Content Template…** on any folder that uses it and choose **Edit Template**, or open the file from the sidebar. Saved changes apply to pages you create from then on. Pages you already created keep their text, and unsaved edits to a template are not used.

## Creating a page from a template

When the destination folder has a template, **New File** asks for the page's name first. The sheet shows where the page will go and which template it uses, and suggests a name from your filename pattern in **Settings > General**. The name you type is used exactly as typed, and `.md` is added for you. Cancel and nothing is created.

The new page opens with the cursor at the end of its text, so end a template with an empty line where you want to start writing.

Every way of making a page (the File menu, its shortcut, Incantations, or right-clicking a folder) uses the template of the folder the page is created in, not of the page you happen to have open.

## Placeholders

Placeholders in a template are replaced when the page is created:

| Placeholder | Becomes | Example |
| --- | --- | --- |
| `{title}` | The page's filename without `.md` | `Episode #4` |
| `{filename}` | The page's filename | `Episode #4.md` |
| `{date}` | Today's date, `YYYY-MM-DD` | `2026-11-02` |
| `{time}` | The time, 24-hour `HH:mm:ss` | `14:05:09` |

Date and time are local, and all placeholders in a page share the same moment. If the name you chose is taken, Grimoire adds a number (`Episode #4 2.md`), and `{title}` and `{filename}` use the name the file actually got.

Placeholders are case-sensitive and filled in once. Renaming or moving the page later doesn't change its text.

### In frontmatter: add `:yaml`

A plain placeholder inserts the text as it is, which can break frontmatter. In YAML, `title: Episode #4` reads as the title `Episode`, because ` #` starts a comment. Add `:yaml` to get a quoted, escaped string instead, and leave out your own quotes:

```markdown
---
title: {title:yaml}
date: {date}
draft: true
---

# {title}

```

creates

```markdown
---
title: "Episode #4"
date: 2026-11-02
draft: true
---

# Episode #4

```

Every placeholder has a `:yaml` form: `{title:yaml}`, `{filename:yaml}`, `{date:yaml}` and `{time:yaml}`. `{date:yaml}` gives the quoted string `"2026-11-02"`. Plain `{date}` gives an unquoted value that most YAML readers treat as a date. Use whichever your site generator expects.

### Writing braces literally

Double the braces to keep a placeholder as text: `{{title}}` becomes `{title}`, and `{{date:yaml}}` becomes `{date:yaml}`.

Anything that isn't one of the placeholders above is left alone, including `{author}`, `{Title}`, `{title:upper}` and an unclosed `{title`. There are no other placeholders, no custom date formats and no expressions.

## Inheritance and opting out

**Content Template…** offers three choices for a folder:

- **Use a template**: this folder and the folders inside it use the chosen file.
- **No template**: this folder and the folders inside it create plain, empty pages.
- **Inherit**: removes this folder's own choice, so it follows the nearest folder above it that has one.

The nearest folder with a choice wins, so a subfolder can use a different template, or switch templates back on under a **No template** folder. Templates don't combine; the nearer one replaces the outer one. The sheet shows the folder a choice comes from and the template file it uses.

A choice stays inside its bound root and its project. A folder bound on its own starts with no choice even if it sits inside another bound folder, and the same folder in another project has its own setting. Choices are saved in the project, not as files in your folders.

## When something goes wrong

If a template file has gone missing, moved outside the project's folders, or can't be read as text, **New File** stops and tells you which template is broken and which folder it belongs to. It never quietly uses another template or an empty page. From there you can:

- **Retry** after fixing the file. The name you typed is kept.
- **Choose Replacement…** to point the folder at a different template file. The sheet shows which folders the change covers before you confirm.
- **Create Empty Once** to make this one page without a template, leaving the setting as it is.

Renaming or moving folders and template files inside Grimoire keeps their choices attached. If a folder with a choice disappears from outside Grimoire, the choice shows under **Content Templates** in the sidebar, with **Locate Folder…** and **Remove Assignment**.
