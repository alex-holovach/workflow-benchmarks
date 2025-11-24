# Performance Benchmark Suite

This directory contains a comprehensive benchmarking suite to compare the performance of different Workflow "World" backends (Local, Postgres, JetStream, etc.).

## Prerequisites

- **k6**: Load testing tool. Install with:
  ```bash
  brew install k6  # macOS
  # or visit https://k6.io/docs/getting-started/installation/
  ```
- **pnpm**: Package manager (already required for this project)
- **Node.js**: Version 18+ (already required for this project)

## Quick Start

```bash
cd benchmarks
./run.sh
```

## Benchmark Scenarios

### 1. Latency Test (`benchmarkChain`)
- **What it measures**: Time per step transition (queue overhead)
- **How**: Sequential chain of 50 steps
- **Use case**: Compare how fast different backends can process step completions

### 2. Throughput Test (`benchmarkFanOut`)
- **What it measures**: Events/second the system can ingest
- **How**: Parallel fan-out of 100 steps
- **Use case**: Compare maximum concurrent processing capacity

## Running Different Scenarios

### Default (Latency)
```bash
./run.sh
```

### Throughput Test
```bash
SCENARIO=throughput WORKFLOW_TYPE=fanout ./run.sh
```

### Custom Configuration
```bash
SCENARIO=latency \
WORKFLOW_TYPE=chain \
BASE_URL=http://localhost:3000 \
./run.sh
```

## Testing Different Backends

### Local World (Default)
```bash
# No env var needed - uses default
./run.sh
```

### Postgres World
```bash
export WORKFLOW_TARGET_WORLD="@workflow/world-postgres"
export WORKFLOW_POSTGRES_URL="postgres://user:pass@localhost:5432/db"
./run.sh
```

### Custom World
```bash
export WORKFLOW_TARGET_WORLD="@your/custom-world"
./run.sh
```

## Understanding Results

The benchmark outputs:

1. **HTTP Request Duration**: Time from request start to response (includes workflow execution)
2. **Workflow Duration**: Custom metric tracking end-to-end workflow time
3. **Throughput**: Requests per second
4. **Success Rate**: Percentage of successful workflow executions
5. **Percentiles**: p95, p99 latency metrics

### Key Metrics to Compare

- **p95 Latency**: 95% of workflows complete within this time
- **p99 Latency**: 99% of workflows complete within this time
- **Throughput**: Maximum workflows/second the system can handle
- **Success Rate**: Should be >95% for valid benchmarks

## How It Works

1. **Setup**: Ensures benchmark workflow file is in place
2. **Build**: Builds the Next.js app in production mode with the simplified benchmark route
3. **Start**: Starts the app in the background
4. **Benchmark**: Runs k6 load tests against the simplified `/api/benchmark` endpoint
5. **Cleanup**: Automatically stops the app

The benchmark app is a minimal Next.js application with:
- A single API route (`/api/benchmark`) that directly imports and executes workflows
- Two benchmark workflows: `benchmarkChain` (latency test) and `benchmarkFanOut` (throughput test)
- No dynamic workflow loading or complex hydration - just direct function calls

## Troubleshooting

### App doesn't start
- Check logs: `tail -f /tmp/workflow-benchmark-app.log`
- Ensure port 3000 is available
- Verify dependencies are installed: `cd benchmarks/app && pnpm install`

### k6 not found
- Install k6: `brew install k6` (macOS) or follow [k6 installation guide](https://k6.io/docs/getting-started/installation/)

### Benchmark fails
- Ensure the app is running: `curl http://localhost:3000`
- Check that workflows are registered: The build process should show workflow generation
- Verify environment variables are set correctly for your target World

## Files

- `workflows.ts`: Benchmark workflow definitions (copied to `app/workflows/benchmark.ts`)
- `route.ts`: Template for the simplified API endpoint (not used - actual route is in `app/app/api/benchmark/route.ts`)
- `k6.js`: k6 load testing script with scenarios and metrics
- `run.sh`: Automation script that orchestrates the entire benchmark
- `app/`: Minimal Next.js application for running benchmarks

