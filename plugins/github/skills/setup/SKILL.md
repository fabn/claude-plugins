---
name: github:setup
description: |
  This skill should be used when the user wants to configure the GitHub MCP
  server, verify gh CLI installation, check authentication, or troubleshoot
  GitHub plugin connectivity. Checks gh CLI availability, authentication status,
  GITHUB_MCP_TOKEN configuration, and tests MCP tool availability.
  Activates on: "setup github", "configure github", "github setup",
  "install github plugin", "connect to github", "github mcp",
  "github token", "test github connection", "verify github",
  "gh cli setup", "configurare github", "configurazione github".
---

# GitHub Setup Skill

Interactive setup wizard for the GitHub plugin. Verifies `gh` CLI installation, authentication status, GitHub MCP token configuration, and MCP server connectivity.

## Tools Used

- **Bash**: Check `gh` CLI version and authentication status
- **ToolSearch**: Discover GitHub MCP tools and verify connectivity
- **AskUserQuestion**: Guide user through fixing issues

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

### Step 5: Summary

Print a configuration summary:

```
GitHub Plugin Configuration
-----------------------------
gh CLI:           v2.x.x (installed)
gh auth:          authenticated as @username
GITHUB_MCP_TOKEN: configured
MCP Connection:   verified (@username)

Next steps:
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

## Related Skills

- **`/github:release`** — Publish draft releases created by Release Drafter
