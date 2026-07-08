#!/bin/sh
# GitHub MCP server launcher — fetches the token from gh's keychain at runtime
# so no credential is ever written to a config file.
export GITHUB_PERSONAL_ACCESS_TOKEN="$(/opt/homebrew/bin/gh auth token)"
exec /opt/homebrew/bin/github-mcp-server stdio
