import { createClient } from 'npm:@supabase/supabase-js@2'

type ServiceAccount = {
  project_id: string
  client_email: string
  private_key: string
}

type MessageRecord = {
  id: string
  room_id: string
  sender_id: string
  body: string
  message_type: string
}

type WebhookPayload = {
  type: 'INSERT'
  table: 'messages'
  schema: 'public'
  record: MessageRecord
}

const jsonHeaders = { 'Content-Type': 'application/json' }

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 })
  }

  const legacyServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const secretKeys = readSecretKeys()
  const apiKey = request.headers.get('apikey') ?? ''
  const usesSecretKey = Object.values(secretKeys).includes(apiKey)
  const usesLegacyKey =
    request.headers.get('authorization') === `Bearer ${legacyServiceRoleKey}`
  if (!usesSecretKey && !usesLegacyKey) {
    return Response.json({ error: 'unauthorized' }, { status: 401 })
  }
  const adminKey = usesSecretKey ? apiKey : legacyServiceRoleKey

  let payload: WebhookPayload
  try {
    payload = await request.json()
  } catch {
    return Response.json({ error: 'invalid_json' }, { status: 400 })
  }
  if (!isValidPayload(payload)) {
    return Response.json({ error: 'invalid_payload' }, { status: 400 })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceAccount = readServiceAccount()
  const supabase = createClient(supabaseUrl, adminKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const message = payload.record
  const [{ data: sender }, { data: members, error: membersError }] =
    await Promise.all([
      supabase.from('profiles').select('nickname').eq('id', message.sender_id).single(),
      supabase
        .from('room_members')
        .select('user_id')
        .eq('room_id', message.room_id)
        .neq('user_id', message.sender_id),
    ])
  if (membersError) throw membersError

  const recipientIds = [...new Set((members ?? []).map((member) => member.user_id))]
  if (recipientIds.length === 0) return Response.json({ sent: 0, skipped: 0 })

  const { data: subscriptions, error: subscriptionsError } = await supabase
    .from('push_subscriptions')
    .select('id, token, user_id')
    .in('user_id', recipientIds)
    .eq('enabled', true)
  if (subscriptionsError) throw subscriptionsError
  if (!subscriptions?.length) return Response.json({ sent: 0, skipped: 0 })

  const accessToken = await firebaseAccessToken(serviceAccount)
  const preview = message.message_type === 'image'
    ? '이미지를 보냈어요.'
    : message.body.trim().slice(0, 120)
  const title = sender?.nickname ? `${sender.nickname} · MangoTalk` : 'MangoTalk'
  const appUrl = Deno.env.get('APP_PUBLIC_URL') ?? 'https://kwangna83.github.io/mangotalk/'
  let sent = 0
  let skipped = 0
  const unreadCounts = new Map<string, number>()

  for (const recipientId of recipientIds) {
    const { data: position } = await supabase
      .from('message_read_positions')
      .select('last_read_created_at')
      .eq('room_id', message.room_id)
      .eq('user_id', recipientId)
      .maybeSingle()
    let countQuery = supabase
      .from('messages')
      .select('id', { count: 'exact', head: true })
      .eq('room_id', message.room_id)
      .neq('sender_id', recipientId)
    if (position?.last_read_created_at) {
      countQuery = countQuery.gt('created_at', position.last_read_created_at)
    }
    const { count } = await countQuery
    unreadCounts.set(recipientId, count ?? 0)
  }

  for (const subscription of subscriptions) {
    const { error: claimError } = await supabase.from('push_deliveries').insert({
      message_id: message.id,
      subscription_id: subscription.id,
    })
    if (claimError?.code === '23505') {
      skipped += 1
      continue
    }
    if (claimError) throw claimError

    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          ...jsonHeaders,
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token: subscription.token,
            notification: { title, body: preview },
            data: {
              title,
              body: preview,
              roomId: message.room_id,
              messageId: message.id,
              unreadCount: String(unreadCounts.get(subscription.user_id) ?? 0),
            },
            webpush: {
              fcm_options: {
                link: `${appUrl}?room=${encodeURIComponent(message.room_id)}`,
              },
            },
          },
        }),
      },
    )
    const result = await response.json()
    const invalidToken = isInvalidToken(response.status, result)
    await supabase
      .from('push_deliveries')
      .update({
        status: response.ok ? 'sent' : invalidToken ? 'invalid_token' : 'failed',
        provider_message_id: response.ok ? result.name ?? null : null,
        error_code: response.ok ? null : result.error?.status ?? `http_${response.status}`,
        attempted_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('message_id', message.id)
      .eq('subscription_id', subscription.id)

    if (invalidToken) {
      await supabase
        .from('push_subscriptions')
        .update({ enabled: false, updated_at: new Date().toISOString() })
        .eq('id', subscription.id)
    }
    if (response.ok) sent += 1
  }

  return Response.json({ sent, skipped })
})

function isValidPayload(value: unknown): value is WebhookPayload {
  if (!value || typeof value !== 'object') return false
  const payload = value as Partial<WebhookPayload>
  const record = payload.record as Partial<MessageRecord> | undefined
  return payload.type === 'INSERT' &&
    payload.table === 'messages' &&
    payload.schema === 'public' &&
    typeof record?.id === 'string' &&
    typeof record.room_id === 'string' &&
    typeof record.sender_id === 'string' &&
    typeof record.body === 'string' &&
    typeof record.message_type === 'string'
}

function readServiceAccount(): ServiceAccount {
  const encoded = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON_BASE64')
  if (!encoded) throw new Error('Missing Firebase service account secret')
  const parsed = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0))))
  if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
    throw new Error('Invalid Firebase service account secret')
  }
  return parsed as ServiceAccount
}

function readSecretKeys(): Record<string, string> {
  const encoded = Deno.env.get('SUPABASE_SECRET_KEYS')
  if (!encoded) return {}
  try {
    return JSON.parse(encoded)
  } catch {
    return {}
  }
}

async function firebaseAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const claims = base64Url(JSON.stringify({
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }))
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemBytes(account.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  )
  const assertion = `${header}.${claims}.${base64UrlBytes(new Uint8Array(signature))}`
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  })
  const result = await response.json()
  if (!response.ok || !result.access_token) throw new Error('Firebase OAuth failed')
  return result.access_token
}

function pemBytes(pem: string): Uint8Array {
  const base64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s/g, '')
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0))
}

function base64Url(value: string): string {
  return base64UrlBytes(new TextEncoder().encode(value))
}

function base64UrlBytes(value: Uint8Array): string {
  let binary = ''
  for (const byte of value) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
}

function isInvalidToken(status: number, result: any): boolean {
  if (status !== 400 && status !== 404) return false
  const code = result?.error?.details?.find(
    (detail: any) => detail['@type']?.includes('FcmError'),
  )?.errorCode
  return code === 'UNREGISTERED' || code === 'INVALID_ARGUMENT'
}
