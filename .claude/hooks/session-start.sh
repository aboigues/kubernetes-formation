#!/bin/bash
#
# Session Start Hook for kubernetes-formation
#
# This hook runs at the start of every Claude session to:
# 1. Verify Kubernetes tooling versions and detect obsolescence
# 2. Validate all YAML manifests
# 3. Check cluster status if available
# 4. Run automated tests
# 5. Report deprecations and outdated configurations
#
# Last updated: 2025-12-15
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Working directory
PROJECT_ROOT="/home/user/kubernetes-formation"
cd "$PROJECT_ROOT"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Kubernetes Formation - Session Start Verification        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to print section headers
print_section() {
    echo -e "\n${BLUE}▶ $1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to check command availability
check_command() {
    if command -v "$1" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is installed"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} $1 is NOT installed"
        return 1
    fi
}

# Function to check Kubernetes API versions for deprecation
check_api_deprecations() {
    local file=$1
    local warnings=""

    # Check for deprecated APIs (as of Kubernetes 1.29)
    if grep -q "apiVersion: extensions/v1beta1" "$file" 2>/dev/null; then
        warnings="${warnings}\n  - extensions/v1beta1 is REMOVED (use apps/v1)"
    fi

    if grep -q "apiVersion: apps/v1beta1" "$file" 2>/dev/null; then
        warnings="${warnings}\n  - apps/v1beta1 is REMOVED (use apps/v1)"
    fi

    if grep -q "apiVersion: apps/v1beta2" "$file" 2>/dev/null; then
        warnings="${warnings}\n  - apps/v1beta2 is REMOVED (use apps/v1)"
    fi

    if grep -q "apiVersion: policy/v1beta1" "$file" 2>/dev/null; then
        warnings="${warnings}\n  - policy/v1beta1 PodDisruptionBudget is deprecated (use policy/v1)"
    fi

    if grep -q "apiVersion: autoscaling/v2beta1" "$file" 2>/dev/null; then
        warnings="${warnings}\n  - autoscaling/v2beta1 is deprecated (use autoscaling/v2)"
    fi

    if grep -q "apiVersion: autoscaling/v2beta2" "$file" 2>/dev/null; then
        warnings="${warnings}\n  - autoscaling/v2beta2 is deprecated (use autoscaling/v2)"
    fi

    if grep -q "apiVersion: batch/v1beta1" "$file" 2>/dev/null; then
        warnings="${warnings}\n  - batch/v1beta1 CronJob is deprecated (use batch/v1)"
    fi

    if grep -q "apiVersion: networking.k8s.io/v1beta1" "$file" 2>/dev/null; then
        warnings="${warnings}\n  - networking.k8s.io/v1beta1 is deprecated (use networking.k8s.io/v1)"
    fi

    if [ -n "$warnings" ]; then
        echo -e "${RED}✗${NC} $file has deprecated APIs:$warnings"
        return 1
    fi

    return 0
}

# =============================================================================
# 1. CHECK TOOLING VERSIONS
# =============================================================================
print_section "1. Kubernetes Tooling Versions"

tools_ok=true

# Check kubectl
if check_command kubectl; then
    version=$(kubectl version --client --short 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+' || kubectl version --client -o json 2>/dev/null | grep -oP '"gitVersion": "v\K[^"]+' || echo "unknown")
    echo "  Version: $version"

    # Extract major.minor version
    major_minor=$(echo "$version" | grep -oP 'v\d+\.\d+' || echo "unknown")
    if [[ "$major_minor" < "v1.29" ]] && [[ "$major_minor" != "unknown" ]]; then
        echo -e "  ${YELLOW}⚠ kubectl version is older than 1.29, consider upgrading${NC}"
    fi
else
    tools_ok=false
fi

# Check minikube
if check_command minikube; then
    version=$(minikube version --short 2>/dev/null || echo "unknown")
    echo "  Version: $version"
else
    echo -e "  ${YELLOW}⚠ minikube not installed (optional for local testing)${NC}"
fi

# Check helm
if check_command helm; then
    version=$(helm version --short 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
    echo "  Version: $version"
else
    echo -e "  ${YELLOW}⚠ helm not installed (required for TP6)${NC}"
fi

# Check yq (YAML processor)
if check_command yq; then
    version=$(yq --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
    echo "  Version: $version"
fi

# Check yamllint
if check_command yamllint; then
    version=$(yamllint --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
    echo "  Version: $version"
fi

# =============================================================================
# 2. CHECK CLUSTER STATUS
# =============================================================================
print_section "2. Kubernetes Cluster Status"

cluster_available=false
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✓${NC} Kubernetes cluster is accessible"
    cluster_available=true

    # Get cluster version
    server_version=$(kubectl version --short 2>/dev/null | grep 'Server Version' | grep -oP 'v\d+\.\d+\.\d+' || kubectl version -o json 2>/dev/null | grep -A1 '"serverVersion"' | grep 'gitVersion' | grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
    echo "  Server Version: $server_version"

    # Check for version skew
    if [[ "$server_version" != "unknown" ]] && [[ "$version" != "unknown" ]]; then
        client_minor=$(echo "$version" | grep -oP 'v\d+.\K\d+' || echo "0")
        server_minor=$(echo "$server_version" | grep -oP 'v\d+.\K\d+' || echo "0")
        skew=$((client_minor - server_minor))
        if [[ $skew -lt -1 ]] || [[ $skew -gt 1 ]]; then
            echo -e "  ${YELLOW}⚠ Version skew detected: kubectl $version vs server $server_version${NC}"
            echo -e "  ${YELLOW}  Recommended: keep kubectl within ±1 minor version of server${NC}"
        fi
    fi

    # Get node count
    node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
    echo "  Nodes: $node_count"

    # Show contexts
    current_context=$(kubectl config current-context 2>/dev/null || echo "none")
    echo "  Current Context: $current_context"
else
    echo -e "${YELLOW}⚠${NC} No Kubernetes cluster accessible (this is OK for documentation work)"
    echo "  Run 'minikube start' to start a local cluster"
fi

# =============================================================================
# 3. VALIDATE YAML MANIFESTS
# =============================================================================
print_section "3. YAML Manifest Validation"

yaml_errors=0
yaml_warnings=0
deprecated_apis=0

# Find all YAML files in tp*/ and docs/
yaml_files=$(find tp*/ docs/ -name "*.yaml" -o -name "*.yml" 2>/dev/null | grep -v node_modules || true)
total_files=$(echo "$yaml_files" | grep -c . || echo 0)

echo "Found $total_files YAML manifest files"

if [ "$total_files" -gt 0 ]; then
    echo ""

    # Check each file
    while IFS= read -r file; do
        [ -z "$file" ] && continue

        # Check YAML syntax with Python
        if python3 -c "import yaml; yaml.safe_load_all(open('$file'))" 2>/dev/null; then
            # Check for deprecated APIs
            if ! check_api_deprecations "$file"; then
                ((deprecated_apis++))
                ((yaml_warnings++))
            fi
        else
            echo -e "${RED}✗${NC} $file - YAML syntax error"
            ((yaml_errors++))
        fi
    done <<< "$yaml_files"

    echo ""
    if [ $yaml_errors -eq 0 ] && [ $deprecated_apis -eq 0 ]; then
        echo -e "${GREEN}✓${NC} All YAML files are valid and up-to-date"
    elif [ $yaml_errors -eq 0 ]; then
        echo -e "${YELLOW}⚠${NC} All YAML files are syntactically valid"
        echo -e "${YELLOW}⚠${NC} Found $deprecated_apis file(s) with deprecated APIs"
    else
        echo -e "${RED}✗${NC} Found $yaml_errors YAML syntax error(s)"
        echo -e "${YELLOW}⚠${NC} Found $deprecated_apis file(s) with deprecated APIs"
    fi
fi

# =============================================================================
# 4. CHECK FOR OUTDATED GITHUB ACTIONS
# =============================================================================
print_section "4. GitHub Actions Version Check"

if [ -f ".github/workflows/test-kubernetes-manifests.yml" ]; then
    echo "Checking GitHub Actions for outdated versions..."

    outdated_actions=0

    # Check for old action versions
    if grep -q "actions/checkout@v3" .github/workflows/*.yml 2>/dev/null; then
        echo -e "${YELLOW}⚠${NC} actions/checkout@v3 found (v4 is available)"
        ((outdated_actions++))
    fi

    if grep -q "actions/setup-python@v4" .github/workflows/*.yml 2>/dev/null; then
        echo -e "${YELLOW}⚠${NC} actions/setup-python@v4 found (v5 is available)"
        ((outdated_actions++))
    fi

    if grep -q "azure/setup-kubectl@v3" .github/workflows/*.yml 2>/dev/null; then
        echo -e "${YELLOW}⚠${NC} azure/setup-kubectl@v3 found (v4 is available)"
        ((outdated_actions++))
    fi

    if [ $outdated_actions -eq 0 ]; then
        echo -e "${GREEN}✓${NC} GitHub Actions are using current versions"
    else
        echo -e "${YELLOW}⚠${NC} Found $outdated_actions potentially outdated action version(s)"
    fi
else
    echo -e "${YELLOW}⚠${NC} GitHub Actions workflow not deployed to .github/workflows/"
    echo "  Consider deploying from github-workflows-setup/"
fi

# =============================================================================
# 5. RUN AVAILABLE TEST SCRIPTS
# =============================================================================
print_section "5. Available Test Scripts"

test_scripts=$(find tp*/ -name "test-*.sh" -o -name "*test*.sh" 2>/dev/null | grep -v node_modules || true)
test_count=$(echo "$test_scripts" | grep -c . || echo 0)

if [ "$test_count" -gt 0 ]; then
    echo "Found $test_count test script(s):"
    while IFS= read -r script; do
        [ -z "$script" ] && continue
        if [ -x "$script" ]; then
            echo -e "  ${GREEN}✓${NC} $script (executable)"
        else
            echo -e "  ${YELLOW}⚠${NC} $script (not executable - run: chmod +x $script)"
        fi
    done <<< "$test_scripts"

    if [ "$cluster_available" = true ]; then
        echo ""
        echo "Cluster is available - tests can be run with:"
        echo "  ./tp05/test-tp5.sh    # Test RBAC and security"
        echo "  ./tp08/test-tp8.sh    # Test networking"
        echo "  ./tp09/test-tp9.sh    # Test multi-node features"
    fi
else
    echo "No test scripts found"
fi

# =============================================================================
# 6. PROJECT STATISTICS
# =============================================================================
print_section "6. Project Statistics"

# Count files by type
yaml_count=$(find . -name "*.yaml" -o -name "*.yml" 2>/dev/null | grep -v node_modules | wc -l)
md_count=$(find . -name "*.md" 2>/dev/null | wc -l)
sh_count=$(find . -name "*.sh" 2>/dev/null | wc -l)

echo "  YAML manifests: $yaml_count files"
echo "  Documentation:  $md_count markdown files"
echo "  Shell scripts:  $sh_count files"

# Count TPs
tp_count=$(ls -d tp*/ 2>/dev/null | wc -l)
echo "  TPs (workshops): $tp_count"

# Git status
if git rev-parse --git-dir > /dev/null 2>&1; then
    current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    echo "  Current branch: $current_branch"

    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        echo -e "  ${YELLOW}⚠${NC} Uncommitted changes detected"
    else
        echo -e "  ${GREEN}✓${NC} Working directory clean"
    fi
fi

# =============================================================================
# 7. SUMMARY AND RECOMMENDATIONS
# =============================================================================
print_section "7. Summary & Recommendations"

issues=0
warnings=0

if [ "$tools_ok" = false ]; then
    ((issues++))
fi

if [ $yaml_errors -gt 0 ]; then
    ((issues++))
fi

if [ $deprecated_apis -gt 0 ]; then
    ((warnings++))
fi

if [ $issues -eq 0 ] && [ $warnings -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "The project is in good shape. You can:"
    echo "  • Start working on any TP"
    echo "  • Run tests if cluster is available"
    echo "  • Review documentation"
elif [ $issues -eq 0 ]; then
    echo -e "${YELLOW}⚠ All critical checks passed with $warnings warning(s)${NC}"
    echo ""
    echo "Recommended actions:"
    if [ $deprecated_apis -gt 0 ]; then
        echo "  • Update deprecated Kubernetes API versions"
    fi
else
    echo -e "${RED}✗ Found $issues issue(s) and $warnings warning(s)${NC}"
    echo ""
    echo "Required actions:"
    if [ "$tools_ok" = false ]; then
        echo "  • Install missing Kubernetes tools"
    fi
    if [ $yaml_errors -gt 0 ]; then
        echo "  • Fix YAML syntax errors"
    fi
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Session verification complete - Ready to work!            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Return appropriate exit code
if [ $issues -gt 0 ]; then
    exit 1
fi

exit 0
