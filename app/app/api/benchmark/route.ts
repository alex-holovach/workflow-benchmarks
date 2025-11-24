import { getRun, start } from 'workflow/api';
import { benchmarkChain, benchmarkFanOut } from '@/workflows/benchmark';

/**
 * Simplified synchronous benchmark endpoint.
 *
 * This endpoint starts a workflow and waits for it to complete before returning.
 * This eliminates polling jitter and provides precise latency measurements.
 */
export async function POST(req: Request) {
  const url = new URL(req.url);
  const type = url.searchParams.get('type') || 'chain';

  // Select workflow based on type
  const workflow = type === 'fanout' ? benchmarkFanOut : benchmarkChain;
  const workflowName = type === 'fanout' ? 'benchmarkFanOut' : 'benchmarkChain';

  try {
    const run = await start(workflow);

    // Wait for workflow completion synchronously
    const runHandle = getRun(run.runId);
    const returnValue = await runHandle.returnValue;

    return Response.json({
      runId: run.runId,
      result: returnValue,
      workflow: workflowName,
    });
  } catch (error) {
    console.error(`Failed to execute workflow:`, error);

    return Response.json(
      {
        error: 'Internal server error',
        message: error instanceof Error ? error.message : String(error),
      },
      { status: 500 }
    );
  }
}
