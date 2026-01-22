#!/bin/bash
#
# Pipeline Performance Analyzer
# Analyzes GitHub Actions workflow performance and suggests optimizations
#
# Usage: ./pipeline-analyzer.sh <workflow-name>
#

set -euo pipefail

WORKFLOW_NAME="${1:-ci.yml}"
RUNS_TO_ANALYZE=20

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[ANALYZE]${NC} $1"
}

log "Analyzing workflow: $WORKFLOW_NAME"

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "GitHub CLI (gh) is not installed. Please install it first."
    exit 1
fi

# Fetch recent workflow runs
log "Fetching last $RUNS_TO_ANALYZE workflow runs..."

RUNS=$(gh run list --workflow="$WORKFLOW_NAME" --limit=$RUNS_TO_ANALYZE --json databaseId,conclusion,createdAt,updatedAt,headBranch)

if [ -z "$RUNS" ] || [ "$RUNS" = "[]" ]; then
    echo "No workflow runs found for $WORKFLOW_NAME"
    exit 1
fi

# Calculate statistics
info "Calculating performance metrics..."

# Average duration
TOTAL_DURATION=0
SUCCESS_COUNT=0
FAILURE_COUNT=0
DURATIONS=()

echo "$RUNS" | jq -r '.[] | "\(.databaseId) \(.conclusion) \(.createdAt) \(.updatedAt)"' | while read -r id conclusion created updated; do
    if [ "$conclusion" = "success" ]; then
        ((SUCCESS_COUNT++))
    else
        ((FAILURE_COUNT++))
    fi
    
    # Calculate duration in seconds
    CREATED_TS=$(date -d "$created" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$created" +%s)
    UPDATED_TS=$(date -d "$updated" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$updated" +%s)
    DURATION=$((UPDATED_TS - CREATED_TS))
    
    DURATIONS+=($DURATION)
    TOTAL_DURATION=$((TOTAL_DURATION + DURATION))
done

AVG_DURATION=$((TOTAL_DURATION / RUNS_TO_ANALYZE))
AVG_MINUTES=$((AVG_DURATION / 60))

# Job-level analysis
log "Analyzing job performance..."

LATEST_RUN=$(echo "$RUNS" | jq -r '.[0].databaseId')
JOBS=$(gh run view "$LATEST_RUN" --json jobs --jq '.jobs[] | "\(.name) \(.conclusion) \(.startedAt) \(.completedAt)"')

echo ""
echo "============================================"
echo "Pipeline Performance Report"
echo "============================================"
echo ""
echo "Workflow: $WORKFLOW_NAME"
echo "Runs Analyzed: $RUNS_TO_ANALYZE"
echo ""
echo "Success Rate: $SUCCESS_COUNT/$RUNS_TO_ANALYZE ($((SUCCESS_COUNT * 100 / RUNS_TO_ANALYZE))%)"
echo "Failure Rate: $FAILURE_COUNT/$RUNS_TO_ANALYZE ($((FAILURE_COUNT * 100 / RUNS_TO_ANALYZE))%)"
echo "Average Duration: $AVG_MINUTES minutes"
echo ""
echo "Job Performance (Latest Run #$LATEST_RUN):"
echo "-------------------------------------------"

echo "$JOBS" | while read -r name conclusion started completed; do
    if [ -n "$started" ] && [ -n "$completed" ] && [ "$started" != "null" ] && [ "$completed" != "null" ]; then
        STARTED_TS=$(date -d "$started" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started" +%s)
        COMPLETED_TS=$(date -d "$completed" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$completed" +%s)
        JOB_DURATION=$((COMPLETED_TS - STARTED_TS))
        JOB_MINUTES=$((JOB_DURATION / 60))
        
        echo "  $name: $JOB_MINUTES min ($conclusion)"
    fi
done

echo ""
echo "Optimization Recommendations:"
echo "-------------------------------------------"

# Recommendations based on analysis
if [ $AVG_MINUTES -gt 15 ]; then
    warning "Pipeline is taking $AVG_MINUTES minutes on average"
    echo "  ✓ Consider enabling dependency caching"
    echo "  ✓ Use matrix builds for parallel testing"
    echo "  ✓ Implement Docker layer caching"
    echo "  ✓ Split large jobs into smaller parallel jobs"
fi

if [ $((FAILURE_COUNT * 100 / RUNS_TO_ANALYZE)) -gt 10 ]; then
    warning "Failure rate is high ($((FAILURE_COUNT * 100 / RUNS_TO_ANALYZE))%)"
    echo "  ✓ Review flaky tests"
    echo "  ✓ Add retry logic for network operations"
    echo "  ✓ Improve error handling"
fi

echo ""
echo "Cache Effectiveness:"
echo "-------------------------------------------"

# Check if actions/cache is being used
if gh run view "$LATEST_RUN" --log | grep -q "actions/cache"; then
    info "✓ Caching is enabled"
    
    CACHE_HITS=$(gh run view "$LATEST_RUN" --log | grep -c "Cache hit" || echo "0")
    CACHE_MISSES=$(gh run view "$LATEST_RUN" --log | grep -c "Cache miss" || echo "0")
    
    echo "  Cache Hits: $CACHE_HITS"
    echo "  Cache Misses: $CACHE_MISSES"
    
    if [ $CACHE_MISSES -gt $CACHE_HITS ]; then
        warning "High cache miss rate detected"
        echo "  ✓ Review cache key patterns"
        echo "  ✓ Ensure cache keys are stable"
    fi
else
    warning "Caching not detected"
    echo "  ✓ Add actions/cache to your workflow"
    echo "  ✓ Cache dependencies (npm, pip, etc.)"
    echo "  ✓ Cache build outputs"
fi

echo ""
echo "============================================"
