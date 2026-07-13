#!/usr/bin/env bash
# =============================================================================
# Test the custom runner image locally
# Builds the image and verifies all required tools are installed & working
# =============================================================================

set -euo pipefail

IMAGE_NAME="actions-runner-custom:test"
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Building custom runner image...${NC}"
echo -e "${CYAN}========================================${NC}"

docker build -t "${IMAGE_NAME}" -f Dockerfile .

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Running tool verification...${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

PASS=0
FAIL=0

check_tool() {
  local name="$1"
  local cmd="$2"

  echo -n "  Checking ${name}... "
  if output=$(docker run --rm --entrypoint="" "${IMAGE_NAME}" bash -c "${cmd}" 2>&1); then
    echo -e "${GREEN}✓${NC}  $(echo "${output}" | head -1)"
    (( PASS++ )) || true
  else
    echo -e "${RED}✗ FAILED${NC}"
    echo "    ${output}"
    (( FAIL++ )) || true
  fi
}

check_tool "Azure CLI"    "az version --output tsv 2>/dev/null | head -1"
check_tool "Terraform"    "terraform version | head -1"
check_tool "kubectl"      "kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1"
check_tool "Helm"         "helm version --short"
check_tool "git"          "git --version"
check_tool "jq"           "jq --version"
check_tool "curl"         "curl --version | head -1"
check_tool "Runner"       "ls /home/runner/run.sh && echo 'run.sh present'"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "  Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo -e "${CYAN}========================================${NC}"

if [ "${FAIL}" -gt 0 ]; then
  echo -e "${RED}Some checks failed!${NC}"
  exit 1
else
  echo -e "${GREEN}All checks passed! Image is ready.${NC}"
fi
