import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Counter, Rate } from 'k6/metrics';

// Custom metrics
const workflowDuration = new Trend('workflow_duration', true);
const workflowErrors = new Counter('workflow_errors');
const workflowSuccessRate = new Rate('workflow_success');

// Configuration from environment or defaults
const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const WORKFLOW_TYPE = __ENV.WORKFLOW_TYPE || 'chain'; // 'chain' or 'fanout'
const SCENARIO = __ENV.SCENARIO || 'latency'; // 'latency' or 'throughput'

// Scenario configurations
const scenarios = {
  latency: {
    executor: 'ramping-vus',
    startVUs: 1,
    stages: [
      { duration: '30s', target: 5 }, // Warm-up
      { duration: '1m', target: 10 }, // Ramp up
      { duration: '2m', target: 10 }, // Sustained load
      { duration: '30s', target: 0 }, // Ramp down
    ],
    gracefulRampDown: '10s',
  },
  throughput: {
    executor: 'constant-vus',
    vus: 20,
    duration: '2m',
  },
};

export const options = {
  scenarios: {
    benchmark: scenarios[SCENARIO] || scenarios.latency,
  },
  thresholds: {
    http_req_duration: ['p(95)<5000', 'p(99)<10000'], // 95% under 5s, 99% under 10s
    workflow_duration: ['p(95)<5000', 'p(99)<10000'],
    workflow_success: ['rate>0.95'], // 95% success rate
    http_req_failed: ['rate<0.05'], // Less than 5% HTTP errors
  },
};

export default function () {
  const url = `${BASE_URL}/api/benchmark?type=${WORKFLOW_TYPE}`;

  const startTime = Date.now();

  const res = http.post(url, null, {
    tags: { workflow: WORKFLOW_TYPE },
  });

  const duration = Date.now() - startTime;

  // Check if request was successful
  const success = check(res, {
    'status is 200': (r) => r.status === 200,
    'has result': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.result !== undefined;
      } catch {
        return false;
      }
    },
  });

  if (success) {
    workflowSuccessRate.add(1);
    workflowDuration.add(duration);
  } else {
    workflowErrors.add(1);
    workflowSuccessRate.add(0);
    console.error(`Request failed: ${res.status} - ${res.body}`);
  }

  // Small sleep to avoid hammering the server
  sleep(0.1);
}

export function handleSummary(data) {
  return {
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
    'benchmarks/summary.json': JSON.stringify(data, null, 2),
  };
}

function textSummary(data, options) {
  const indent = options.indent || '';
  const enableColors = options.enableColors || false;

  let summary = '\n';
  summary += `${indent}Benchmark Results\n`;
  summary += `${indent}=================\n\n`;

  // HTTP Metrics
  if (data.metrics.http_req_duration) {
    const httpDur = data.metrics.http_req_duration;
    summary += `${indent}HTTP Request Duration:\n`;
    summary += `${indent}  avg: ${httpDur.values.avg.toFixed(2)}ms\n`;
    summary += `${indent}  min: ${httpDur.values.min.toFixed(2)}ms\n`;
    summary += `${indent}  max: ${httpDur.values.max.toFixed(2)}ms\n`;
    summary += `${indent}  p95: ${httpDur.values['p(95)'].toFixed(2)}ms\n`;
    summary += `${indent}  p99: ${httpDur.values['p(99)'].toFixed(2)}ms\n\n`;
  }

  // Workflow Duration
  if (data.metrics.workflow_duration) {
    const wfDur = data.metrics.workflow_duration;
    summary += `${indent}Workflow Duration:\n`;
    summary += `${indent}  avg: ${wfDur.values.avg.toFixed(2)}ms\n`;
    summary += `${indent}  min: ${wfDur.values.min.toFixed(2)}ms\n`;
    summary += `${indent}  max: ${wfDur.values.max.toFixed(2)}ms\n`;
    summary += `${indent}  p95: ${wfDur.values['p(95)'].toFixed(2)}ms\n`;
    summary += `${indent}  p99: ${wfDur.values['p(99)'].toFixed(2)}ms\n\n`;
  }

  // Throughput
  if (data.metrics.http_reqs) {
    const reqs = data.metrics.http_reqs;
    summary += `${indent}Throughput:\n`;
    summary += `${indent}  total requests: ${reqs.values.count}\n`;
    summary += `${indent}  rate: ${reqs.values.rate.toFixed(2)} req/s\n\n`;
  }

  // Success Rate
  if (data.metrics.workflow_success) {
    const success = data.metrics.workflow_success;
    summary += `${indent}Success Rate: ${(success.values.rate * 100).toFixed(2)}%\n\n`;
  }

  return summary;
}
