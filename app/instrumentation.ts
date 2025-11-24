import { registerOTel } from '@vercel/otel';

registerOTel({ serviceName: 'benchmark-workflow' });
