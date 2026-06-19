#!/bin/bash
# Sync the agent-telemetry subdirectory to its standalone GitHub repository.
# Run this from the moonbit-agent-observability repository root.
set -e

git subtree push --prefix=agent-telemetry agent-telemetry main
