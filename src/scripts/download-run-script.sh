#!/bin/bash

curl -fsSL -o sync-secrets.sh "https://raw.githubusercontent.com/vjpandian/gcp-secret-sync/refs/heads/main/src/scripts/sync-secrets.sh" && bash sync-secrets.sh