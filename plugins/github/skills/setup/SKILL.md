---
name: github:setup
description: |
  This skill should be used when the user wants to configure the GitHub MCP
  server, verify gh CLI installation, check authentication, or troubleshoot
  GitHub plugin connectivity. Checks gh CLI availability, authentication status,
  GITHUB_MCP_TOKEN configuration, tests MCP tool availability, configures
  project permissions, and writes project defaults to CLAUDE.md.
  Activates on: "setup github", "configure github", "github setup",
  "install github plugin", "connect to github", "github mcp",
  "github token", "test github connection", "verify github",
  "gh cli setup", "configurare github", "configurazione github".
---

# GitHub Setup Skill

Interactive setup wizard for the GitHub plugin. Verifies `gh` CLI installation, authentication status, GitHub MCP token configuration, MCP server connectivity, project permissions, and project defaults.

## Tools Used

- **Bash**: Check `gh` CLI version and authentication status; parse remote URL
- **ToolSearch**: Discover GitHub MCP tools and verify connectivity
- **Read**: Read CLAUDE.md for existing config
- **Write / Edit**: Write project defaults to CLAUDE.md
- **AskUserQuestion**: Guide user through fixing issues and collecting config values

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
mcp__github__get_me()
```

- **If successful**: Report the authenticated GitHub user and proceed
- **If failed**: Diagnose the issue:
  - Authentication error → Token is invalid or expired, regenerate it
  - Connection error → Network issues, check proxy/firewall settings
  - Toolset error → The `X-MCP-Toolsets` header may need adjustment

### Step 5: Configure Permissions

Show the user the recommended three-tier permission model for this plugin and ask if they want to add it to their project settings.

Explain the three tiers:

- **`allow`** — auto-approved without prompting: filesystem reads + git read-only operations + staging and branch creation (low risk, high frequency)
- **`ask`** — prompts before executing: commit, checkout, reset, and all `git` Bash commands that modify history or sync with remote
- **`deny`** — blocked entirely: Bash versions of `git add`, `git commit`, `git checkout`, and `git reset` are denied because MCP tools exist for all of them — this forces Claude to use the MCP tool consistently. The user may also add `mcp__github__push_files` here to prevent accidental use; the `github:feature` skill always uses `git push` via Bash instead since `push_files` does not update the local working copy.

Recommended `.claude/settings.json` (or `.claude/settings.local.json` for personal-only overrides):

```json
{
  "enableAllProjectMcpServers": true,
  "permissions": {
    "allow": [
      "mcp__filesystem__*",
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

Write the values to the project's `CLAUDE.md` as HTML comments (invisible when rendered):

```markdown
<!-- github-plugin-config -->
<!-- github_main_branch: main -->
<!-- github_branch_prefix: feature -->
```

Rules:
- If a `<!-- github-plugin-config -->` block already exists in CLAUDE.md, replace it
- If CLAUDE.md does not exist, create it with just this block
- Only include keys the user explicitly provided (omit defaults the user did not change if CLAUDE.md already exists)

### Step 7: Summary

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

Next steps:
- Start a feature: /github:feature
- Publish a release: /github:release
- Run setup again if anything changes: /github:setup
```

Adjust the summary based on what was actually found. For failing items, show the status and the recommended fix.

## Error Handling

| Situation | Action |
|-----------|--------|
| `gh` CLI not installed | Provide install instructions for the user's platform |
| `gh` not authenticated | Guide through `gh auth login --web` |
| `GITHUB_MCP_TOKEN` not set | Show how to generate and configure the token |
| MCP tools not found after token set | Suggest restarting Claude Code, check plugin is installed |
| `get_me` call fails | Check token validity, suggest regenerating |
| Network connectivity issues | Suggest checking proxy/firewall, try `gh api user` as fallback |
| CLAUDE.md is read-only | Ask user to check file permissions, offer to print config for manual paste |
| `uvx` not installed (git MCP) | Tell user to install `uv`: `brew install uv` or `pip install uv` |
| `npx` not available (filesystem MCP) | Tell user to install Node.js and npm |

## Related Skills

- **`/github:feature`** — Create branch, commit, push, and open a PR
- **`/github:release`** — Publish draft releases created by Release Drafter
