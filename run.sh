#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$SCRIPT_DIR/app"
BENCHMARKS_DIR="$SCRIPT_DIR"

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v k6 &> /dev/null; then
  echo -e "${RED}Error: k6 is not installed.${NC}"
  echo "Install it with: brew install k6 (macOS) or visit https://k6.io/docs/getting-started/installation/"
  exit 1
fi

if ! command -v pnpm &> /dev/null; then
  echo -e "${RED}Error: pnpm is not installed.${NC}"
  exit 1
fi

# Check if app directory exists
if [ ! -d "$APP_DIR" ]; then
  echo -e "${RED}Error: App directory not found: $APP_DIR${NC}"
  echo "Please ensure benchmarks/app exists (copied from workbench/nextjs-turbopack)"
  exit 1
fi

# Cleanup function
cleanup() {
  echo -e "\n${YELLOW}Cleaning up...${NC}"
  
  # Kill background processes
  if [ ! -z "$APP_PID" ]; then
    echo "Stopping Next.js app (PID: $APP_PID)..."
    kill $APP_PID 2>/dev/null || true
    wait $APP_PID 2>/dev/null || true
  fi
  
  echo -e "${GREEN}Cleanup complete.${NC}"
}

# Set trap to cleanup on exit
trap cleanup EXIT INT TERM

# Step 1: Ensure benchmark files are in place
echo -e "\n${YELLOW}Step 1: Verifying benchmark files...${NC}"

if [ ! -f "$APP_DIR/workflows/benchmark.ts" ]; then
  echo -e "${YELLOW}Copying benchmark workflows...${NC}"
  cp "$BENCHMARKS_DIR/workflows.ts" "$APP_DIR/workflows/benchmark.ts"
fi
echo -e "${GREEN}✓${NC} Benchmark workflows ready"

if [ ! -f "$APP_DIR/app/api/benchmark/route.ts" ]; then
  echo -e "${YELLOW}Copying benchmark API route...${NC}"
  mkdir -p "$APP_DIR/app/api/benchmark"
  cp "$BENCHMARKS_DIR/route.ts" "$APP_DIR/app/api/benchmark/route.ts"
fi
echo -e "${GREEN}✓${NC} Benchmark API route ready"

# Step 1.5: Install dependencies and build essential packages
echo -e "\n${YELLOW}Step 1.5: Checking dependencies and building essential packages...${NC}"
# Install from workspace root to ensure all workspace dependencies are available
cd "$PROJECT_ROOT"
if [ ! -d "node_modules" ]; then
  echo -e "${YELLOW}Installing workspace dependencies...${NC}"
  pnpm install
fi

# Check if essential packages are already built
echo -e "${YELLOW}Checking if packages need building...${NC}"
NEEDS_BUILD=false
if [ ! -f "packages/workflow/dist/next.cjs" ]; then
  echo "  - workflow package needs building"
  NEEDS_BUILD=true
fi
if [ ! -f "packages/core/dist/index.js" ]; then
  echo "  - core package needs building"
  NEEDS_BUILD=true
fi
if [ ! -f "packages/next/dist/index.js" ]; then
  echo "  - @workflow/next package needs building"
  NEEDS_BUILD=true
fi
if [ ! -f "packages/utils/dist/index.js" ]; then
  echo "  - utils package needs building"
  NEEDS_BUILD=true
fi
if [ ! -f "packages/errors/dist/index.js" ]; then
  echo "  - errors package needs building"
  NEEDS_BUILD=true
fi
if [ ! -f "packages/world/dist/index.js" ]; then
  echo "  - world package needs building"
  NEEDS_BUILD=true
fi
if [ ! -f "packages/world-local/dist/index.js" ]; then
  echo "  - world-local package needs building"
  NEEDS_BUILD=true
fi
if [ ! -f "packages/world-vercel/dist/index.js" ]; then
  echo "  - world-vercel package needs building"
  NEEDS_BUILD=true
fi

if [ "$NEEDS_BUILD" = true ]; then
  echo -e "${YELLOW}Building essential workflow packages (this may take a moment)...${NC}"
  # Build packages individually in dependency order, skipping swc-plugin
  cd "$PROJECT_ROOT"
  
  # Build in dependency order (workflow package depends on many others)
  for pkg in errors utils world world-local world-vercel builders core typescript-plugin cli next nitro nuxt sveltekit workflow; do
    echo -e "${YELLOW}Building $pkg...${NC}"
    cd "packages/$pkg"
    if ! pnpm build 2>&1 | grep -v "^$"; then
      echo -e "${RED}Error building $pkg${NC}"
      exit 1
    fi
    cd "$PROJECT_ROOT"
  done
  
  echo -e "${GREEN}✓${NC} Essential packages built"
else
  echo -e "${GREEN}✓${NC} All essential packages are already built"
fi
echo -e "${GREEN}✓${NC} Dependencies ready"

# Step 2: Build Next.js app
echo -e "\n${YELLOW}Step 2: Building Next.js app...${NC}"
cd "$APP_DIR"
# Run build script which will use pnpm exec internally via the script
pnpm run build
echo -e "${GREEN}✓${NC} Build complete"

# Step 3: Start the app
echo -e "\n${YELLOW}Step 3: Starting Next.js app...${NC}"
cd "$APP_DIR"
# Run start script
pnpm run start > /tmp/workflow-benchmark-app.log 2>&1 &
APP_PID=$!
echo "App started with PID: $APP_PID"

# Step 4: Wait for app to be ready
echo -e "\n${YELLOW}Step 4: Waiting for app to be ready...${NC}"
MAX_WAIT=60
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
  if curl -s http://localhost:3000 > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} App is ready"
    break
  fi
  echo -n "."
  sleep 1
  WAITED=$((WAITED + 1))
done

if [ $WAITED -ge $MAX_WAIT ]; then
  echo -e "\n${RED}Error: App did not start within ${MAX_WAIT}s${NC}"
  echo "Check logs: tail -f /tmp/workflow-benchmark-app.log"
  exit 1
fi

# Give it a moment to fully initialize
sleep 2

# Step 3: Run benchmark
echo -e "\n${YELLOW}Step 3: Running benchmark...${NC}"
echo ""

cd "$BENCHMARKS_DIR"

# Allow user to override scenario via environment variable
SCENARIO=${SCENARIO:-latency}
WORKFLOW_TYPE=${WORKFLOW_TYPE:-chain}

if [ "$SCENARIO" = "throughput" ]; then
  WORKFLOW_TYPE=${WORKFLOW_TYPE:-fanout}
fi

echo "Scenario: $SCENARIO"
echo "Workflow Type: $WORKFLOW_TYPE"
echo ""

k6 run \
  --env BASE_URL=http://localhost:3000 \
  --env WORKFLOW_TYPE="$WORKFLOW_TYPE" \
  --env SCENARIO="$SCENARIO" \
  k6.js

echo -e "\n${GREEN}Benchmark complete!${NC}"

