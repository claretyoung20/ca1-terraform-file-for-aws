// =====================================================================
// CA1 workload for the Product Service - ONE script, several profiles.
// Open-model load (fixed arrival rate): the request rate stays the same no
// matter how slow the server gets, so slow servers show up as higher latency
// and errors instead of silently receiving less load. That is what makes runs
// comparable across 1, 2 and 3 instances.
//
//   k6 run -e BASE_URL=http://<alb-dns> -e PROFILE=step workload.js
//
// Profiles (all rates are requests per second):
//   smoke  : 2 rps for 1 min - checks everything works
//   step   : STEPS (default 10,25,50,75,100) each held STEP_DURATION (default 3m)
//   surge  : LOW_RATE 5m -> HIGH_RATE for HIGH_DURATION (15m) -> LOW_RATE for COOL (20m)
//   steady : RATE (default 30) for DURATION (default 10m) - used for the failure test
// Mix: every Nth request is a POST (WRITE_RATIO, default 0.1 = 1 in 10), the rest GET.
// The mix is deterministic (based on iteration number), not random, so every run
// sends exactly the same sequence of requests.
// =====================================================================
import http from 'k6/http';
import { check } from 'k6';
import exec from 'k6/execution';
import { Counter } from 'k6/metrics';

const BASE_URL = (__ENV.BASE_URL || '').replace(/\/$/, '');
if (!BASE_URL) throw new Error('Set -e BASE_URL=http://<your-alb-dns-name>');

const PROFILE = __ENV.PROFILE || 'smoke';
const WRITE_RATIO = Number(__ENV.WRITE_RATIO || 0.1);
const WRITE_EVERY = WRITE_RATIO > 0 ? Math.round(1 / WRITE_RATIO) : 0;
const COUPONS = ['SAVE5', 'SAVE10', 'SAVE15', 'SAVE20', 'SAVE25',
                 'SAVE30', 'SAVE35', 'SAVE40', 'SAVE45', 'SAVE50'];

function stepStages() {
  const levels = (__ENV.STEPS || '10,25,50,75,100').split(',').map(Number);
  const hold = __ENV.STEP_DURATION || '3m';
  const stages = [];
  for (const rate of levels) {
    stages.push({ target: rate, duration: '15s' });   // short ramp to the next level
    stages.push({ target: rate, duration: hold });    // hold the level
  }
  return stages;
}

const LOW = Number(__ENV.LOW_RATE || 10);
const HIGH = Number(__ENV.HIGH_RATE || 60);

const profiles = {
  smoke: { executor: 'constant-arrival-rate', rate: 2, timeUnit: '1s', duration: '1m',
           preAllocatedVUs: 5, maxVUs: 20 },
  step: { executor: 'ramping-arrival-rate', startRate: 1, timeUnit: '1s',
          preAllocatedVUs: 50, maxVUs: 1000, stages: stepStages() },
  surge: { executor: 'ramping-arrival-rate', startRate: LOW, timeUnit: '1s',
           preAllocatedVUs: 50, maxVUs: 1000, stages: [
             { target: LOW, duration: __ENV.WARM || '5m' },
             { target: HIGH, duration: '30s' },
             { target: HIGH, duration: __ENV.HIGH_DURATION || '15m' },
             { target: LOW, duration: '30s' },
             { target: LOW, duration: __ENV.COOL || '20m' },
           ] },
  steady: { executor: 'constant-arrival-rate', rate: Number(__ENV.RATE || 30), timeUnit: '1s',
            duration: __ENV.DURATION || '10m', preAllocatedVUs: 50, maxVUs: 500 },
};
if (!profiles[PROFILE]) throw new Error(`Unknown PROFILE ${PROFILE}. Use smoke|step|surge|steady`);

export const options = {
  scenarios: { [PROFILE]: profiles[PROFILE] },
  discardResponseBodies: true,
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  tags: { run: __ENV.RUN_ID || 'unnamed' },
};

const servedBy = new Counter('served_by');

function params(name) {
  return {
    tags: { name },
    timeout: __ENV.REQ_TIMEOUT || '10s',   // a request slower than this counts as a failure
    headers: { 'Content-Type': 'application/json' },
  };
}

export default function () {
  const i = exec.scenario.iterationInTest;
  let res;
  if (WRITE_EVERY > 0 && i % WRITE_EVERY === 0) {
    const body = JSON.stringify({
      name: `k6-item-${i}`,
      description: 'created by the CA1 load test',
      price: 199.99,
      couponCode: COUPONS[Math.floor(i / WRITE_EVERY) % COUPONS.length],
    });
    res = http.post(`${BASE_URL}/productapi/products`, body, params('POST /products'));
  } else {
    res = http.get(`${BASE_URL}/productapi/products`, params('GET /products'));
  }
  check(res, { 'status is 200': (r) => r.status === 200 });
  servedBy.add(1, { instance: res.headers['X-Served-By'] || 'none' });
}
