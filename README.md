# mango-watchdog

인천공항 제2터미널 아마노 발렛 예약 가능 여부를 서버에서 감시하는 Flutter Web PWA입니다.

Flutter Web은 GitHub Pages에 배포하고, 실제 감시는 Supabase Edge Function이 수행합니다. Supabase Cron이 5분마다 `check-watchdog`를 호출하며, 상태가 불가→가능으로 전환되면 `watch_availability_events`가 생성되고 Database Webhook이 `send-watchdog-push`를 호출합니다.

## 구성

- `adapter_key` 기반 서버 어댑터 구조: 현재 `amano_booking`
- 기본 조건: 입차 2026-11-07 13:00, 출차 2026-11-10 17:30, BASIC
- 실패한 HTTP/네트워크/JSON은 `failed` 이력으로 저장
- 동일 상태에서 중복 알림을 보내지 않도록 `transition_seq`와 delivery unique key 사용

## 배포 순서

1. Supabase에 `supabase/migrations/202610120001_watchdog.sql` 적용
2. 두 Edge Function 배포
3. Edge Function secrets 설정
4. `supabase/manual/setup_watchdog_cron.sql`의 Vault/Database Webhook 설정
5. Flutter Web을 `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, Firebase Web 값과 함께 빌드해 GitHub Pages에 배포

실제 서비스 키와 Firebase 서비스 계정 JSON은 저장소에 넣지 않습니다.
