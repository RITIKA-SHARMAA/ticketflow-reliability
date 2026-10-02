import http from 'k6/http';
import { check, sleep } from 'k6';

const origin = __ENV.BASE_URL || 'http://localhost:8080';
const browsePath = __ENV.BROWSE_PATH || '/api/events';
const bookingPath = __ENV.BOOKING_PATH || '/api/bookings';

export const options = {
  stages: [
    { duration: '2m', target: 5 },
    { duration: '3m', target: 15 },
    { duration: '3m', target: 30 },
    { duration: '2m', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.02'],
    http_req_duration: ['p(95)<800'],
  },
};

export default function () {
  const listing = http.get(`${origin}${browsePath}`);
  check(listing, { 'browse status is successful': r => r.status >= 200 && r.status < 400 });

  if (Math.random() < 0.35) {
    const key = `load-${__VU}-${__ITER}-${Date.now()}`;
    const body = JSON.stringify({
      eventId: __ENV.EVENT_ID || 'REPLACE_WITH_VALID_EVENT_ID',
      ticketTierId: __ENV.TIER_ID || 'REPLACE_WITH_VALID_TIER_ID',
      quantity: 1,
    });
    const response = http.post(`${origin}${bookingPath}`, body, {
      headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key },
    });
    check(response, { 'booking response matches expected API contract': r => [200, 201, 202, 400, 409].includes(r.status) });
  }
  sleep(1);
}
