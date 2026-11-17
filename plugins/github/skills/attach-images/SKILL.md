---
name: github:attach-images
description: |
  This skill should be used when the user wants to put images (screenshots,
  mockups, diagrams) in a pull request, issue, or comment without committing
  them to the repository. Uploads them as GitHub attachments from the command
  line, the same ones drag-and-drop creates in the web UI, and returns the tags
  to paste in the body.
  Activates on: "attach screenshots", "screenshots in the PR", "upload images
  to github", "add screenshots to PR", "attach images", "image in issue",
  "user-attachments", "allega screenshot", "screenshot nella PR", "carica
  immagini su github", "aggiungi screenshot alla PR", "immagini nella issue".
---

# GitHub Attach Images Skill

Upload local images as GitHub attachments and embed them in a PR, issue, or comment body. Nothing is committed: the files live on `github.com/user-attachments`, as if dragged into the web editor.

## Tools Used

- **Bash**: `${CLAUDE_PLUGIN_ROOT}/skills/attach-images/scripts/upload-images.sh` — uploads and prints the tags. Requires `gh` (authenticated), `curl` and `jq`.
- **GitHub MCP** or `gh`: to write the tags into the PR/issue body or a comment.

## Workflow

### Step 1: Prepare the images

Supported types: PNG, JPEG, GIF, WebP. Name each file after what it shows (`light.png`, `dark.png`, `before.png`): the name becomes the `alt` text.

Before uploading, check each image shows nothing that should not leave the machine (real customer data, tokens, internal URLs). On a private repository an attachment is readable only by whoever can read the repository. On a public one it stays private until a body or comment references it, then anyone can open it, and deleting that body or comment does not take it back.

### Step 2: Upload

From inside the repository the images belong to:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/attach-images/scripts/upload-images.sh" -w 250 light.png dark.png
```

- `-R owner/repo` targets another repository; the attachment inherits that repository's visibility.
- `-w <px>` sets the display width, useful for phone screenshots. Omit it for full width.

It prints one `<img>` tag per file, in the order given.

### Step 3: Embed

Paste the tags in the body. Side by side, in a table:

```markdown
| Light | Dark |
|---|---|
| <img src="..." alt="light" width="250"> | <img src="..." alt="dark" width="250"> |
```

Update the body with the GitHub MCP (`update_pull_request`, `issue_write`) or `gh pr edit --body-file` / `gh issue edit --body-file`. Do not use `--body` with a body that contains backticks or `$`: the shell mangles it.

## Error Handling

| Situation | Action |
|-----------|--------|
| `gh` not authenticated | Stop, tell user to run `gh auth login` or `/github:setup` |
| Not in a repository and no `-R` | Rerun with `-R owner/repo` |
| `unsupported image type` | Convert to PNG (`sips -s format png` on macOS) and retry |
| `not available in Claude Code web sessions` | Their proxy only forwards `repos/{owner}/{repo}/...` paths and refuses this upload before it reaches GitHub. Tell the user to run the upload from a local session; do not commit the images instead |
| `upload failed for <file>: HTTP <status> <body>` | The endpoint is undocumented and may have changed. Stop and show the user the status and body; do not fall back to committing the images or driving a browser without asking |

## Related Skills

- **`/github:feature`** — opens the PR the images go into
- **`/github:setup`** — verifies `gh` authentication
