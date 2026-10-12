# MangoTalk 시스템 구성도

현재 구현을 기준으로 한 시스템 구성입니다. 다이어그램은 GitHub에서 바로 렌더링되는 Mermaid 형식으로 관리합니다.

```mermaid
flowchart LR
    subgraph Client["클라이언트 · Flutter 3.29.3"]
        UI["화면\n닉네임 입력 · 공개 채팅"]
        State["Riverpod\nAuthController · ChatController"]
        Repo["Repository 계층\nSupabase Auth/Chat Repository"]
        Session["로컬 세션 저장소\n익명 로그인 토큰"]

        UI --> State --> Repo
        Session <--> Repo
    end

    subgraph Hosting["정적 웹 호스팅"]
        Pages["GitHub Pages\nkwangna83.github.io/mangotalk"]
    end

    subgraph Supabase["Supabase Backend"]
        Auth["Auth\n익명 사용자 UUID · JWT"]
        API["PostgREST / RPC"]
        Realtime["Realtime\nmessages INSERT 구독"]

        subgraph DB["PostgreSQL + RLS"]
            Profiles[("profiles\n닉네임")]
            Rooms[("chat_rooms\n공개 채팅방")]
            Members[("room_members\n참여 관계")]
            Messages[("messages\n영구 메시지")]
            Functions["RPC\n커서 기반 조회 · 누락분 조회"]
        end

        Auth --> API
        API --> Profiles
        API --> Rooms
        API --> Members
        API --> Messages
        API --> Functions
        Functions --> Messages
        Messages --> Realtime
    end

    Pages -. "앱 파일 제공" .-> Client
    Repo -- "HTTPS + JWT" --> Auth
    Repo -- "조회 · 저장" --> API
    Realtime -- "새 메시지 전달\nWebSocket" --> Repo

    subgraph Delivery["CI/CD"]
        GitHub["GitHub main 브랜치"]
        Actions["GitHub Actions\n분석 → 테스트 → Web 빌드"]
        GitHub --> Actions --> Pages
    end
```

## 핵심 동작 흐름

```mermaid
sequenceDiagram
    actor User as 사용자
    participant App as Flutter 앱
    participant Auth as Supabase Auth
    participant DB as PostgreSQL/RPC
    participant RT as Supabase Realtime

    User->>App: 닉네임으로 입장
    App->>Auth: 익명 로그인
    Auth-->>App: 사용자 UUID + 세션
    App->>DB: 프로필 저장, 공개방 참여
    App->>DB: 최근 메시지 조회
    App->>RT: 공개방 메시지 구독

    User->>App: 메시지 전송
    App-->>User: 낙관적 메시지 즉시 표시
    App->>DB: 메시지 INSERT
    DB-->>RT: INSERT 이벤트
    RT-->>App: 새 메시지 전달
    App-->>User: 서버 저장 결과로 병합
```

## 익명 사용자 식별

- 사용자 식별자는 닉네임이 아니라 Supabase Auth의 `auth.users.id` UUID입니다.
- 브라우저에 보존된 세션으로 새로고침 후에도 같은 UUID를 사용합니다.
- 저장소 삭제, 시크릿 모드, 다른 브라우저·기기에서는 새 익명 사용자가 생성됩니다.
- 메시지는 `messages.sender_id`로 프로필과 연결되며, 삭제하기 전까지 PostgreSQL에 남습니다.

## 데이터 관계

```mermaid
erDiagram
    AUTH_USERS ||--|| PROFILES : "id"
    AUTH_USERS ||--o{ ROOM_MEMBERS : "user_id"
    CHAT_ROOMS ||--o{ ROOM_MEMBERS : "room_id"
    CHAT_ROOMS ||--o{ MESSAGES : "room_id"
    PROFILES ||--o{ MESSAGES : "sender_id"

    PROFILES {
        uuid id PK
        text nickname
        timestamptz created_at
    }
    CHAT_ROOMS {
        uuid id PK
        enum type
        text name
    }
    ROOM_MEMBERS {
        uuid room_id PK
        uuid user_id PK
        enum role
    }
    MESSAGES {
        uuid id PK
        uuid room_id FK
        uuid sender_id FK
        uuid client_message_id UK
        text body
        timestamptz created_at
    }
```

RLS(Row Level Security)는 인증 사용자만 데이터에 접근하게 하고, 공개방에 참여한 사용자만 메시지를 읽고 자신의 UUID로만 메시지를 보낼 수 있게 제한합니다.
