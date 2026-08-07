---
name: github:setup
description: |
  This skill should be used when the user wants to configure the GitHub MCP
  server, verify gh CLI installation, check authentication, or troubleshoot
  GitHub plugin connectivity. Checks gh CLI availability, authentication status,
  GITHUB_MCP_TOKEN configuration, tests MCP tool availability, configures
  project permissions, and writes project defaults to .claude/github.json.
  Activates on: "setup github", "configure github", "github setup",
  "install github plugin", "connect to github", "github mcp",
  "github token", "test github connection", "verify github",
  "gh cli setup", "configurare github", "configurazione github".
---

# GitHub Setup Skill

Interactive setup wizard for the GitHub plugin. Verifies `gh` CLI installation, authentication status, GitHub MCP token configuration, MCP server connectivity, project permissions, and project defaults.

## Tools Used

- **Bash**: Check `gh` CLI version and authentication status; parse remote URL
- **GitHub MCP** (`mcp__plugin_github_github__*` when this plugin's bundled GitHub MCP server is active): `get_me`, `projects_list`
- **ToolSearch**: Discover GitHub MCP tools and verify connectivity
- **Bash**: `${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh` to detect existing config and its location; `migrate-config.sh` when it is in the deprecated one
- **Write / Edit**: Write project defaults to `.claude/github.json`
- **AskUserQuestion**: Guide user through fixing issues and collecting config values

> **MCP server name may differ.** The prefix `mcp__plugin_github_github__` is used when this plugin's bundled GitHub MCP server is active. If the host project ships its own GitHub MCP server (often `mcp__github__*`), the bundled one may be disabled to avoid conflicts — discover the actual prefix from the available tool list and substitute it (in tool calls **and** in the permissions block recommended in Step 5). Verb names are unchanged.

## Workflow

### Step 1: Check `gh` CLI

Run `gh --version` to check if the GitHub CLI is installed.

- **If missing**: Tell the user to install it:
  - macOS: `brew install gh`
  - Linux: see [GitHub CLI install docs](https://github.com/cli/cli#installation)
  - Stop here — `gh` is required for release publishing
- **If present**: Confirm the version and proceed

### Step 2: Check `gh` Authentication

Run `gh auth status` to verify the user is authenticated.

- **If not authenticated**: Guide the user through `gh auth login`
  - Recommend the browser-based flow: `gh auth login --web`
  - Ensure the token has `repo` scope at minimum
- **If authenticated**: Confirm the account and proceed

### Step 3: Check `GITHUB_MCP_TOKEN`

Use `ToolSearch("github")` to discover GitHub MCP tools.

- **If tools are found**: Token is configured and working, proceed to Step 4
- **If no tools found**: The `GITHUB_MCP_TOKEN` environment variable is missing or invalid. Explain how to set it:

  1. Generate a token following the [GitHub MCP Server documentation](https://github.com/github/github-mcp-server?tab=readme-ov-file#default-toolset)
  2. Make the token available to Claude's environment. Any of these methods work:
     - Shell environment: `export GITHUB_MCP_TOKEN=your-token` in `.bashrc`/`.zshrc`
     - Global Claude settings: Add to `~/.claude/settings.local.json`:
       ```json
       {
         "env": {
           "GITHUB_MCP_TOKEN": "your-token-here"
         }
       }
       ```
     - Project Claude settings: Add to `.claude/settings.local.json` in the project root
  3. After setting the token, restart Claude Code for it to take effect

  > **Note:** OAuth flow support may remove the token requirement in the future.

### Step 4: Verify MCP Connectivity

Attempt a lightweight MCP call to confirm the token works:

```
mcp__plugin_github_github__get_me()
```

- **If successful**: Report the authenticated GitHub user and proceed
- **If failed**: Diagnose the issue:
  - Authentication error → Token is invalid or expired, regenerate it
  - Connection error → Network issues, check proxy/firewall settings
  - Toolset error → The `X-MCP-Toolsets` header may need adjustment

### Step 5: Configure Permissions

Show the user the recommended three-tier permission model for this plugin and ask if they want to add it to their project settings.

Explain the three tiers:

- **`allow`** — auto-approved without prompting: git read-only operations plus staging and branch creation (low risk, high frequency)
- **`ask`** — prompts before executing: commit, checkout, reset, and all `git` Bash commands that modify history or sync with remote
- **`deny`** — blocked entirely: Bash versions of `git add`, `git commit`, `git checkout`, and `git reset` are denied because MCP tools exist for all of them — this forces Claude to use the MCP tool consistently. The user may also add `mcp__plugin_github_github__push_files` here to prevent accidental use; the `github:feature` skill always uses `git push` via Bash instead since `push_files` does not update the local working copy.

Recommended `.claude/settings.json` (or `.claude/settings.local.json` for personal-only overrides):

```json
{
  "enableAllProjectMcpServers": true,
  "permissions": {
    "allow": [
      "mcp__git__git_status",
      "mcp__git__git_diff",
      "mcp__git__git_diff_unstaged",
      "mcp__git__git_diff_staged",
      "mcp__git__git_log",
      "mcp__git__git_show",
      "mcp__git__git_branch",
      "mcp__git__git_add",
      "mcp__git__git_create_branch"
    ],
    "ask": [
      "mcp__git__git_commit",
      "mcp__git__git_checkout",
      "mcp__git__git_reset",
      "Bash(git push:*)",
      "Bash(git pull:*)",
      "Bash(git rebase:*)",
      "Bash(git merge:*)"
    ],
    "deny": [
      "Bash(git commit:*)",
      "Bash(git add:*)",
      "Bash(git checkout:*)",
      "Bash(git reset:*)"
    ]
  }
}
```

> **Note:** `enableAllProjectMcpServers: true` ensures the plugin's `git` and `filesystem` MCP servers start automatically when you open the project.

Tell the user: "Add this to `.claude/settings.json` (or `.claude/settings.local.json` for personal overrides not committed to version control) in your project root."

Ask via AskUserQuestion: "Would you like to write this permissions config to `.claude/settings.json` now?" If yes, write or merge it. If a settings file already exists, merge rather than overwrite.

### Step 6: Configure Project Defaults

Ask for two project-level defaults via AskUserQuestion:

1. **Main branch name** — the branch PRs merge into (default: `main`)
2. **Default branch prefix** — used when suggesting branch names in `github:feature` (default: `feature`)

Write the values to `.claude/github.json`:

```json
{
  "mainBranch": "main",
  "branchPrefix": "feature"
}
```

Rules:
- Merge into the existing file rather than overwriting it — Step 7 writes `project` into the same file, and a later run must not drop it
- Create `.claude/` if it does not exist
- Only write keys the user explicitly provided; omitting a key is what selects the default, so writing defaults out freezes them
- Validate the result parses (`jq . .claude/github.json`) before reporting success

**If the project still carries the deprecated `<!-- github-plugin-config -->` block in `CLAUDE.md`**, migrate it first rather than writing a second source of truth:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/migrate-config.sh"          # --dry-run to preview
```

Then apply this step's values on top of the migrated file. Two live config locations is the one outcome to avoid — `read-config.sh` prefers the JSON, so a stale markdown block would sit there looking authoritative and being ignored.

### Step 7: Configure GitHub Project (optional)

Ask via AskUserQuestion: "Do you use a GitHub project board to track issues for this project?"

Options:
- **Yes, I have an existing project** — proceed to collect project details
- **No, but I want to create one** — give instructions and exit
- **Skip — I don't use a project board** — note and move on

**If "Yes, I have an existing project":**

1. Ask for the project number. Accept either a plain number (`2`) or a full URL (`https://github.com/users/<owner>/projects/<N>`) — parse the number from the URL if provided.
2. Ask for the project owner (default: owner extracted from `git remote get-url origin`).
3. Validate by calling `mcp__plugin_github_github__projects_list` with `list_project_fields` for the given project — confirm that Status, Priority, and Size fields exist.
4. Merge into `.claude/github.json`:

```json
{
  "project": { "number": 2, "owner": "acme" }
}
```

**If "No, but I want to create one":**

Explain: "Project creation isn't available via the MCP tools. Create a project from the GitHub kanban template at https://github.com/new/project, then come back and re-run `/github:setup` to register it."

Do not write any project config.

**If "Skip":**

Note: "`/github:pm` will create issues without adding them to a project board." Do not write project config.

### Step 8: Summary

Print a configuration summary:

```
GitHub Plugin Configuration
-----------------------------
gh CLI:              v2.x.x (installed)
gh auth:             authenticated as @username
GITHUB_MCP_TOKEN:    configured
MCP Connection:      verified (@username)
Permissions:         written to .claude/settings.json
Main branch:         main
Branch prefix:       feature
Project board:       #2 (fabn)

Next steps:
- Start a feature: /github:feature
- Manage issues: /github:pm
- Publish a release: /github:release
- Set up release-drafter: /github:release-drafter
- Run setup again if anything changes: /github:setup
```

Adjust the summary based on what was actually found. Show `Project board: not configured` if the user skipped or declined. For failing items, show the status and the recommended fix.

## Error Handling

| Situation | Action |
|-----------|--------|
| `gh` CLI not installed | Provide install instructions for the user's platform |
| `gh` not authenticated | Guide through `gh auth login --web` |
| `GITHUB_MCP_TOKEN` not set | Show how to generate and configure the token |
| MCP tools not found after token set | Suggest restarting Claude Code, check plugin is installed |
| `get_me` call fails | Check token validity, suggest regenerating |
| Network connectivity issues | Suggest checking proxy/firewall, try `gh api user` as fallback |
| `.claude/github.json` is read-only | Ask user to check file permissions, offer to print the JSON for manual paste |
| Config found in the deprecated CLAUDE.md block | Run `migrate-config.sh` before writing, so only one source of truth exists |
| `jq` not installed | Required by the config scripts — tell user to install it (`brew install jq`) |
| `uvx` not installed (git MCP) | Tell user to install `uv`: `brew install uv` or `pip install uv` |
| Project number invalid | `list_project_fields` call fails — show error, ask user to verify the project number |
| Project fields missing (no Priority/Size) | Warn user the project may not use the standard kanban template; list available fields |

## Related Skills

- **`/github:feature`** — Create branch, commit, push, and open a PR
- **`/github:release`** — Publish draft releases created by Release Drafter
- **`/github:release-drafter`** — Configure release-drafter on a repository (fresh setup or v6→v7 migration)
- **`/github:pm`** — Create and manage issues; requires `project` in config for board integration
