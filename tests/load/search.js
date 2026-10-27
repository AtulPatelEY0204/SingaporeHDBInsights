// k6 load test for the price search (HDBResale_Core SearchAPI -> the same Search_Run the
// PriceCheck screen calls). Run against Test with Site.SearchApiEnabled = True:
//
//   k6 run -e CORE_BASE_URL=https://test.hdb.example.com/HDBResale_Core tests/load/search.js
//
// Thresholds are the README performance targets; k6 exits non-zero when one is missed.
import http from 'k6/http';
import { check, fail } from 'k6';

const BASE = (__ENV.CORE_BASE_URL || '').replace(/\/$/, '');

export const options = {
  scenarios: {
    // Realistic browsing: ramp to 50 concurrent users (README assumption: < 100).
    browse: {
      executor: 'ramping-vus',
      stages: [
        { duration: '2m', target: 50 },
        { duration: '5m', target: 50 },
        { duration: '1m', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    'http_req_failed{name:search}': ['rate<0.01'],
    // Cold = a filter combination not seen before in the run (cache miss on SnapshotId+filters).
    'http_req_duration{name:search,cache:cold}': ['p(95)<800'],
    'http_req_duration{name:search,cache:warm}': ['p(95)<100'],
    checks: ['rate>0.99'],
  },
};

export function setup() {
  if (!BASE) fail('Set CORE_BASE_URL, e.g. https://test.hdb.example.com/HDBResale_Core');
  const health = http.get(`${BASE}/rest/HealthAPI/Health`);
  if (health.status !== 200 || health.json('Status') !== 'OK') {
    fail(`Refusing to load-test an unhealthy environment: ${health.status} ${health.body}`);
  }
  const probe = http.get(`${BASE}/rest/SearchAPI/search?townId=23&flatTypeId=4`);
  if (probe.status !== 200) fail(`SearchAPI not reachable (is Site.SearchApiEnabled = True?): ${probe.status}`);
}

const seen = {};
function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

export default function () {
  const q = {
    townId: Math.floor(Math.random() * 27),            // 0 = all towns, 1..26 = a town
    flatTypeId: pick([0, 3, 4, 5, 6]),                  // all, 3/4/5-room, executive
    monthsBack: pick([12, 24, 60]),
    minStorey: pick([0, 0, 10]),
    startIndex: pick([0, 0, 0, 20, 40]),
    maxRecords: 20,
  };
  const qs = Object.entries(q).map(([k, v]) => `${k}=${v}`).join('&');
  const cache = seen[qs] ? 'warm' : 'cold';
  seen[qs] = true;

  const res = http.get(`${BASE}/rest/SearchAPI/search?${qs}`, { tags: { name: 'search', cache } });
  check(res, {
    'status 200': (r) => r.status === 200,
    'has summary': (r) => r.status === 200 && r.json('Summary') !== undefined,
    'page size respected': (r) => r.status === 200 && (r.json('Rows') || []).length <= 20,
  });
}
