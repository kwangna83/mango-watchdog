# mango-watchdog 전체 플로우

## 1. 프로젝트 목적

`mango-watchdog`는 인천공항 제2터미널 아마노 발렛의 예약 가능 여부를 서버에서 주기적으로 확인하는 Flutter Web PWA입니다.

- 실제 예약은 사용자가 예약 사이트에서 직접 진행합니다.
- 브라우저가 닫혀 있어도 Supabase 서버 감시는 계속됩니다.
- 예약 가능 여부가 `불가 → 가능`으로 바뀌는 순간에만 푸시 알림을 보냅니다.
- 현재 감시 어댑터는 `amano_booking`이며, 추후 다른 감시 API 어댑터를 추가할 수 있습니다.

## 2. 전체 구성

```text
사용자 브라우저
  └─ Flutter Web PWA (GitHub Pages)
       ├─ Supabase 익명 로그인
       ├─ 감시 설정 저장
       ├─ 지금 확인 요청
       └─ Firebase Web Push 토큰 등록

Supabase
  ├─ Postgres: 설정·상태·이력·이벤트·구독 저장
  ├─ pg_cron: 5분마다 check-watchdog 호출
  ├─ Edge Function: check-watchdog
  │    └─ Amano API 호출 및 상태 전환 기록
  ├─ Postgres Trigger + pg_net
  │    └─ 예약 가능 전환 이벤트를 푸시 함수로 전달
  └─ Edge Function: send-watchdog-push
       └─ Firebase FCM HTTP v1로 브라우저 푸시 발송
```

## 3. 기본 감시 조건

초기 감시 설정은 다음과 같습니다.

| 항목 | 기본값 |
|---|---|
| 입차 날짜 | `2026-11-07` |
| 입차 시간 | `13:00` |
| 출차 날짜 | `2026-11-10` |
| 출차 시간 | `17:30` |
| 예약 유형 | `BASIC` |
| 확인 간격 | 5분 |

Amano 확인 API는 입차 날짜만 사용합니다.

```text
GET https://api.amanopark.co.kr/api/web/setting/booking/check?date={entryDate}&type={bookingType}
```

응답 판정:

- `result.code === 200`이고 `data === true`: 예약 가능
- `result.code === 200`이고 `data === false`: 예약 불가
- HTTP 오류, 네트워크 오류, JSON 파싱 오류, 응답 형식 오류: 확인 실패

## 4. 앱 최초 실행

### 4.1 Flutter 초기화

`lib/main.dart`가 다음 순서로 실행됩니다.

1. Flutter 바인딩 초기화
2. 빌드 시 주입된 `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` 읽기
3. Supabase 초기화
4. Firebase Web 설정이 모두 있으면 Firebase 초기화
5. `WatchdogScreen` 표시

Firebase 설정이 없어도 감시 화면은 동작하지만, 푸시 기능은 사용할 수 없습니다.

### 4.2 익명 사용자 및 감시 대상 생성

화면 진입 시 현재 Supabase 세션을 확인합니다.

- 세션이 있으면 기존 사용자 사용
- 세션이 없으면 `signInAnonymously()` 호출
- 해당 사용자의 `watch_monitors`가 없으면 기본 설정으로 1개 생성
- 이미 있으면 기존 설정을 화면에 표시

따라서 브라우저 저장소가 초기화되거나 다른 브라우저를 사용하면 익명 사용자가 달라지고 감시 대상이 새로 생성될 수 있습니다.

## 5. 화면에서 설정 저장

사용자가 입차 날짜, 시간, 출차 날짜, 시간, 활성화 상태, 확인 간격을 변경하고 저장하면 Flutter가 `watch_monitors`를 업데이트합니다.

저장되는 `config` 예시:

```json
{
  "entryDate": "2026-11-07",
  "entryTime": "13:00",
  "exitDate": "2026-11-10",
  "exitTime": "17:30",
  "bookingType": "BASIC"
}
```

`entryDate`는 다음 Amano API 요청의 `date` 파라미터가 됩니다. 출차 정보는 현재 화면과 설정에는 저장되지만, Amano 확인 API 자체가 입차 날짜만 받으므로 API 요청에는 포함되지 않습니다.

## 6. 서버 감시 플로우

### 6.1 Supabase Cron

`pg_cron`이 다음 스케줄로 실행됩니다.

```text
*/5 * * * *
```

Cron은 `net.http_post`로 다음 Edge Function을 호출합니다.

```text
POST https://dlvskrosvqnfzppgntgt.supabase.co/functions/v1/check-watchdog
```

Cron 요청은 `WATCHDOG_CRON_SECRET`을 Bearer 토큰으로 사용합니다.

### 6.2 check-watchdog 인증

`check-watchdog`는 두 종류의 요청을 허용합니다.

1. Cron/서비스 요청
   - `Authorization: Bearer WATCHDOG_CRON_SECRET`
   - 활성화된 모든 감시 대상 확인
2. 웹앱 요청
   - Supabase 세션의 Bearer JWT 사용
   - `admin.auth.getUser(token)`으로 사용자 확인
   - 해당 사용자 소유 감시 대상만 확인

브라우저의 `지금 확인` 버튼은 웹앱 요청으로 동작하며 `force: true`를 전달해 간격 제한을 건너뜁니다.

### 6.3 간격 제한

Cron 요청은 각 감시 대상의 `last_checked_at`과 `interval_minutes`를 비교합니다.

- 마지막 확인 후 설정된 간격이 지나지 않았으면 건너뜀
- `force: true`이면 즉시 확인

## 7. Amano 어댑터 플로우

현재 `adapter_key`가 `amano_booking`인 경우:

1. `config.entryDate`, `config.bookingType` 읽기
2. 입차 날짜 형식 검증
3. Amano API에 최대 15초 timeout으로 요청
4. HTTP 상태 확인
5. JSON 파싱
6. `result.code === 200` 및 `data`가 boolean인지 검증
7. `matched`, `summary`, `httpStatus`, 응답 일부를 결과로 반환

어댑터를 확장할 때는 `adapter_key`별 API 호출·응답 판정 로직을 추가하면 됩니다. 데이터베이스 스키마와 상태 전환 로직은 공통으로 재사용합니다.

## 8. 성공 결과 저장과 상태 전환

성공한 확인은 RPC `record_watchdog_check`를 통해 트랜잭션으로 처리합니다.

### 8.1 `watch_monitors` 업데이트

- `data: true` → `status = available`
- `data: false` → `status = unavailable`
- `last_checked_at` 갱신
- `last_success_at` 갱신
- `last_successful_match` 갱신
- 오류 필드 초기화

### 8.2 `watch_check_runs` 기록

모든 성공 확인은 `watch_check_runs`에 기록됩니다.

주요 필드:

- 확인 시각
- 성공/실패 결과
- 예약 가능 여부
- HTTP 상태
- 응답 시간
- 요약 문구
- 응답 일부

### 8.3 중복 알림 방지

알림 전환은 다음 조건에서만 발생합니다.

```text
현재 결과가 available이고
직전 성공 결과가 available이 아님
```

전환이 발생하면 `transition_seq`를 1 증가시키고 `watch_availability_events`를 생성합니다.

따라서 예약 가능 상태가 5분마다 계속 확인되어도 첫 번째 전환에서만 이벤트가 생성됩니다.

## 9. 실패 결과 저장

다음 상황은 확인 실패로 처리됩니다.

- 네트워크 연결 실패
- timeout
- HTTP 오류
- 잘못된 JSON
- 응답 필드 누락 또는 타입 오류
- 알 수 없는 `adapter_key`

실패 시:

- `watch_monitors.status = failed`
- `last_checked_at` 갱신
- `last_error` 저장
- `watch_check_runs.outcome = failed` 기록
- 기존의 `last_successful_match`는 유지

실패는 예약 불가와 다릅니다. 마지막 정상 판정은 보존되므로 네트워크 장애가 발생했다고 해서 예약 가능 상태가 자동으로 예약 불가로 바뀌지는 않습니다.

## 10. 이벤트에서 푸시까지

### 10.1 DB Trigger

`watch_availability_events`에 INSERT가 발생하면 PostgreSQL Trigger `watchdog_event_push_trigger`가 실행됩니다.

Trigger 함수 `notify_watchdog_event`는 `pg_net`의 `net.http_post`를 사용해 다음 함수에 비동기 요청을 보냅니다.

```text
POST https://dlvskrosvqnfzppgntgt.supabase.co/functions/v1/send-watchdog-push
```

헤더에는 Vault의 `watchdog_webhook_secret` 값이 들어갑니다.

### 10.2 send-watchdog-push

푸시 함수는 다음 순서로 동작합니다.

1. Webhook secret 확인
2. 이벤트의 `owner_id`로 활성화된 푸시 구독 조회
3. Firebase 서비스 계정으로 Google OAuth access token 발급
4. 각 FCM 토큰에 Firebase HTTP v1 메시지 전송
5. 성공/실패 결과를 `watch_notification_deliveries`에 기록

FCM 메시지에는 다음 정보가 포함됩니다.

- 제목
- 본문
- 예약 사이트 URL
- 이벤트 ID

## 11. 푸시 구독 등록

화면에서 **스마트폰 푸시 등록**을 누르면:

1. Firebase 초기화 여부 확인
2. 브라우저 알림 권한 요청
3. FCM Web VAPID 키로 토큰 발급
4. 설치 식별자 생성 또는 재사용
5. `watch_push_subscriptions`에 upsert

브라우저마다 익명 사용자와 설치 식별자가 다를 수 있습니다. 같은 설치에서 토큰이 바뀌면 동일 `owner_id + installation_id` 행을 갱신합니다.

## 12. Firebase 설정 구성

### 12.1 GitHub Repository secrets

Flutter Web 빌드에는 다음 9개 Secret이 사용됩니다.

```text
SUPABASE_URL
SUPABASE_PUBLISHABLE_KEY
FIREBASE_WEB_API_KEY
FIREBASE_WEB_AUTH_DOMAIN
FIREBASE_PROJECT_ID
FIREBASE_STORAGE_BUCKET
FIREBASE_MESSAGING_SENDER_ID
FIREBASE_WEB_APP_ID
FIREBASE_WEB_VAPID_KEY
```

### 12.2 Edge Function secret

서버 푸시 발송에는 다음 Secret이 필요합니다.

```text
FIREBASE_SERVICE_ACCOUNT_JSON_BASE64
```

이 값은 새 Firebase 프로젝트에서 다운로드한 서비스 계정 JSON 전체를 UTF-8 Base64로 변환한 값입니다. Web 앱의 `projectId`와 서비스 계정 JSON의 `project_id`가 같아야 합니다.

추가 서버 Secret:

```text
WATCHDOG_CRON_SECRET
WATCHDOG_WEBHOOK_SECRET
```

### 12.3 Service Worker

GitHub Actions는 빌드 전에 Repository secrets를 사용해 `web/firebase-messaging-sw.js`를 생성합니다. Firebase 서비스 계정 Secret은 브라우저 파일에 넣지 않고 서버 Edge Function에서만 사용합니다.

## 13. 데이터 테이블 관계

```text
watch_monitors
  ├─ watch_check_runs
  └─ watch_availability_events
       └─ watch_notification_deliveries

watch_push_subscriptions
  └─ watch_notification_deliveries
```

주요 테이블:

- `watch_monitors`: 감시 설정과 현재 상태
- `watch_check_runs`: API 확인 이력
- `watch_availability_events`: 예약 가능 전환 이벤트
- `watch_push_subscriptions`: 브라우저 FCM 구독
- `watch_notification_deliveries`: 이벤트별 발송 결과

## 14. 확인 이력 조회

한국 시간으로 확인 이력을 조회합니다.

```sql
select
  r.checked_at at time zone 'Asia/Seoul' as checked_at_kst,
  m.name,
  r.outcome,
  r.matched,
  r.http_status,
  r.duration_ms,
  r.summary,
  r.error
from public.watch_check_runs r
join public.watch_monitors m
  on m.id = r.monitor_id
order by r.checked_at desc;
```

푸시 발송 이력 조회:

```sql
select
  d.status,
  d.error_code,
  d.provider_message_id,
  d.attempted_at at time zone 'Asia/Seoul' as attempted_at_kst,
  e.title,
  e.body,
  s.platform,
  s.enabled
from public.watch_notification_deliveries d
join public.watch_availability_events e on e.id = d.event_id
join public.watch_push_subscriptions s on s.id = d.subscription_id
order by d.created_at desc;
```

## 15. 테스트 이벤트

실제 예약 가능 전환을 기다리지 않고 테스트할 때는 테스트 이벤트를 직접 INSERT합니다. 이 작업은 실제 푸시를 발송하고 이력을 남깁니다.

```sql
insert into public.watch_availability_events (
  monitor_id,
  owner_id,
  transition_seq,
  adapter_key,
  title,
  body,
  url
)
values (
  'MONITOR_ID',
  'OWNER_ID',
  1,
  'amano_booking',
  'mango-watchdog 테스트',
  '푸시 알림 테스트입니다.',
  'https://valet.amanopark.co.kr/booking'
);
```

같은 감시 대상에서 이미 사용한 `transition_seq`는 다시 사용할 수 없습니다.

## 16. 이력 초기화

감시 설정과 푸시 구독을 유지하면서 이력만 초기화할 때 사용합니다.

```sql
begin;

delete from public.watch_notification_deliveries;
delete from public.watch_availability_events;
delete from public.watch_check_runs;

commit;
```

## 17. 주요 장애 확인 순서

### 웹앱에서 `invalid API key`

- GitHub Repository secrets의 `SUPABASE_URL` 확인
- `SUPABASE_PUBLISHABLE_KEY`가 같은 Supabase 프로젝트의 값인지 확인
- Secret 변경 후 GitHub Actions 재배포

### CORS 오류

- `check-watchdog`에 CORS 및 `OPTIONS` 처리가 배포됐는지 확인
- 브라우저 캐시가 아닌 최신 Pages 배포인지 확인

### `check-watchdog` 401

- Edge Function의 JWT Gateway 검증이 꺼져 있는지 확인
- 웹 요청에는 Supabase 세션 Bearer 토큰이 있는지 확인
- 함수 로그와 응답 본문이 `Unauthorized`인지 확인

### `send-watchdog-push` 500

- `FIREBASE_SERVICE_ACCOUNT_JSON_BASE64`가 새 Firebase 프로젝트의 JSON인지 확인
- JSON을 Base64로 변환했는지 확인
- 서비스 계정 `project_id`와 Web 앱 `projectId`가 같은지 확인
- `WATCHDOG_WEBHOOK_SECRET`과 Vault의 `watchdog_webhook_secret` 값이 같은지 확인

### 푸시가 오지 않음

1. `watch_push_subscriptions.enabled = true` 확인
2. `watch_notification_deliveries.status` 확인
3. `net._http_response`의 Webhook HTTP 상태 확인
4. 브라우저 알림 권한과 Service Worker 확인
5. Firebase 프로젝트의 Web Push VAPID 키 확인

## 18. 배포 구성

### Flutter Web

GitHub Actions가 `main` 브랜치 push 시 실행됩니다.

1. Flutter 의존성 설치
2. `flutter analyze`
3. Firebase Service Worker 생성
4. Flutter Web release build
5. GitHub Pages 배포

배포 주소:

```text
https://kwangna83.github.io/mango-watchdog/
```

### Supabase

Edge Function은 Supabase CLI로 배포합니다.

```powershell
npx supabase functions deploy check-watchdog --no-verify-jwt
npx supabase functions deploy send-watchdog-push --no-verify-jwt
```

DB migration, `pg_cron`, `pg_net`, Cron, Trigger는 Supabase 프로젝트에서 별도로 적용합니다.

## 19. 예약 사이트

예약 가능 알림을 받은 뒤 사용자가 직접 예약을 진행합니다.

```text
https://valet.amanopark.co.kr/booking
```
