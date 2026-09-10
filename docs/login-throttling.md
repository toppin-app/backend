# Password-login throttling

Implemented 2026-09-10. Applies to `Users::SessionsController#create`, including HTML and JSON aliases; not social login, registration, logout or session restoration.

## Policy

- 30 requests per IP per 60 seconds.
- 10 requests per normalized email + IP per 300 seconds.
- 100 requests per normalized email per 900 seconds, including changing IPs.
- Counts all attempts before password verification. Blocked requests do not extend existing expiry windows. Fixed windows can allow a burst across a boundary.
- Returns HTTP 429, `Retry-After` and `login_rate_limited`. Does not expose whether an account exists. Does not set `User.blocked` or revoke existing sessions.
- Counters are HMAC identifiers using existing Rails secret material, not plaintext emails or IPs. Atomic Lua counters share the existing `REDIS_URL` across workers. No new production variables, gems or migrations.
- Redis connection/read/write timeouts are each 300 ms, no retries. On Redis failure, log a non-sensitive warning and allow login. This explicitly prioritizes availability: throttling is unavailable during that outage. Monitor `[LoginAttemptLimiter] Redis unavailable`.

## Release checks

Not deployed or tested against production infrastructure. Verify Redis EVAL permission, connectivity and Rails `request.remote_ip` behind the actual trusted proxy chain before release. Do not trust arbitrary forwarded headers or add broad trusted proxy ranges. Observe 429 volume on shared networks and adjust budgets if necessary. Account-wide throttling can still temporarily inconvenience a targeted account; no permanent lockout is introduced.

Mobile displays a translated temporary-wait message in ES/EN/IT/FR. Older clients still receive a safe HTTP error, but may display generic invalid-login feedback. It does not implement a local countdown; the server remains authoritative.

## Validation

`test/services/login_attempt_limiter_test.rb`: real dedicated Redis, limits, email normalization, TTL, independent identities, concurrency and outage behavior. Set `LOGIN_LIMITER_TEST_REDIS_URL` to a disposable test Redis, never production.

`test/controllers/users/login_throttling_test.rb`: HTML/JSON 429, metadata, no user lookup or JWT, malformed envelope, unchanged below-limit contract. Existing email-login and session-restoration tests pass.

References: [OWASP authentication](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html), [Redis atomic counter pattern](https://redis.io/docs/latest/commands/incr/).
