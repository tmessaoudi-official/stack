#!/bin/bash

set -euo pipefail

dig +short "${1}" || echo ""