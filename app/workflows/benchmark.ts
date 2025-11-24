/**
 * Benchmark: Sequential Chain
 *
 * Measures latency - the time it takes for the queue/storage system
 * to transition between steps. A chain of 50 steps will stress-test
 * the overhead of step completion -> event creation -> next step queuing.
 */

async function increment(v: number) {
  'use step';
  return v + 1;
}

export async function benchmarkChain() {
  'use workflow';

  let value = 0;
  for (let i = 0; i < 50; i++) {
    value = await increment(value);
  }

  return value;
}

/**
 * Benchmark: Parallel Fan-Out
 *
 * Measures throughput - how many events/steps the system can process
 * concurrently. A fan-out of 100 parallel steps will stress-test
 * event ingestion rate and concurrent step execution.
 */

async function ping(i: number) {
  'use step';
  return `pong-${i}`;
}

export async function benchmarkFanOut() {
  'use workflow';

  const tasks = Array.from({ length: 100 }).map((_, i) => ping(i));

  const results = await Promise.all(tasks);
  return results.length;
}
