#!/bin/bash
# SR 限定翻牌券 PG 併發 smoke（2026-08-09，批 2 Task 12）。scratch PG16、真交易屏障。
set -u
SP=/tmp/claude-1000/-mnt-c-Users-eric1-OneDrive-Desktop-VibeSync/062fdd54-b6c1-49ac-9ba4-bb04d219619f/scratchpad
PGSOCK=/tmp/claude-1000/pgsock
P="psql -U postgres -h $PGSOCK -p 54329 -d postgres -qtA"
W1='2026-08-08T04:00:00Z'
PASS=0; FAIL=0
ok(){ echo "PASS: $1"; PASS=$((PASS+1)); }
bad(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

seed(){ $P -c "insert into auth.users values ('$1'); insert into public.subscriptions (user_id,tier) values ('$1','$2');"; }
ticket(){ $P -c "insert into public.practice_sr_draw_tickets (user_id,tier_at_grant) values ('$1','starter');"; }
srclaim(){ $P -c "select public.claim_practice_sr_ticket_draw('$1','$2','$3','$W1','starter');" 2>&1; }
claim(){ $P -c "select public.claim_practice_profile_draw('$1','$2','$3','$W1','starter',3,5,true,50,300,true);" 2>&1; }

U1=aaaaaaaa-1111-1111-1111-111111111111
U2=aaaaaaaa-2222-2222-2222-222222222222
U3=aaaaaaaa-3333-3333-3333-333333333333
U4=aaaaaaaa-4444-4444-4444-444444444444
U5=aaaaaaaa-5555-5555-5555-555555555555
seed $U1 starter >/dev/null; ticket $U1 >/dev/null
seed $U2 starter >/dev/null; ticket $U2 >/dev/null
seed $U3 starter >/dev/null; ticket $U3 >/dev/null
seed $U4 starter >/dev/null
seed $U5 free >/dev/null; ticket $U5 >/dev/null

# ── T1：不同 requestId 併發券抽——恰一次成功、後到 NOT_AVAILABLE、券恰消耗一次 ──
(
  psql -U postgres -h $PGSOCK -p 54329 -d postgres -qtA <<EOF > $SP/t1a.out 2>&1
begin;
select public.claim_practice_sr_ticket_draw('$U1','t1a','sr_g1','$W1','starter');
select pg_sleep(2);
commit;
EOF
) &
A=$!
sleep 0.6
srclaim $U1 t1b sr_g2 > $SP/t1b.out 2>&1
wait $A
grep -q '"idempotent_replay": false' $SP/t1a.out && grep -q 'PRACTICE_SR_TICKET_NOT_AVAILABLE' $SP/t1b.out \
  && ok "T1 不同 requestId 併發：先到成功、後到 NOT_AVAILABLE" || { bad "T1"; cat $SP/t1a.out $SP/t1b.out; }
C=$($P -c "select count(*) from practice_profile_draw_events where user_id='$U1'")
[ "$C" = "1" ] && ok "T1 帳本恰一筆券抽事件" || bad "T1 帳本=$C"
CONS=$($P -c "select consumed_at is not null from practice_sr_draw_tickets where user_id='$U1'")
[ "$CONS" = "t" ] && ok "T1 券恰消耗" || bad "T1 券未消耗"

# ── T2：同 requestId 併發——後到 replay 原 profile、券恰消耗一次 ─────────────
(
  psql -U postgres -h $PGSOCK -p 54329 -d postgres -qtA <<EOF > $SP/t2a.out 2>&1
begin;
select public.claim_practice_sr_ticket_draw('$U2','t2','sr_g1','$W1','starter');
select pg_sleep(2);
commit;
EOF
) &
A=$!
sleep 0.6
srclaim $U2 t2 sr_g9 > $SP/t2b.out 2>&1
wait $A
grep -q '"idempotent_replay": true' $SP/t2b.out && grep -q '"profile_id": "sr_g1"' $SP/t2b.out \
  && ok "T2 同 requestId 併發：後到 replay 原 profile" || { bad "T2"; cat $SP/t2b.out; }
C=$($P -c "select count(*) from practice_profile_draw_events where user_id='$U2'")
[ "$C" = "1" ] && ok "T2 帳本恰一筆" || bad "T2 帳本=$C"

# ── T3：券抽不佔每日免費額度——券抽後 starter 仍有 3 次 cost0，第 4 次付費 5 ──
srclaim $U3 t3sr sr_g1 > $SP/t3sr.out 2>&1
grep -q '"idempotent_replay": false' $SP/t3sr.out && ok "T3 券抽成功" || { bad "T3 券抽"; cat $SP/t3sr.out; }
for i in 1 2 3; do claim $U3 t3n$i g$i > $SP/t3n$i.out 2>&1; done
grep -q '"cost_messages": 0' $SP/t3n3.out && ok "T3 券抽後第 3 次一般抽仍 cost0（券不偷額度）" || { bad "T3 第3抽"; cat $SP/t3n3.out; }
claim $U3 t3n4 g4 > $SP/t3n4.out 2>&1
grep -q '"cost_messages": 5' $SP/t3n4.out && ok "T3 第 4 次一般抽付費 5" || { bad "T3 第4抽"; cat $SP/t3n4.out; }
BS=$($P -c "select bonus_source from practice_profile_draw_events where user_id='$U3' and request_id='t3sr'")
[ "$BS" = "subscription_sr" ] && ok "T3 券抽事件帶 bonus_source" || bad "T3 bonus_source=$BS"

# ── T4：無券 → NOT_AVAILABLE；已用重抽（新 requestId）→ NOT_AVAILABLE ────────
srclaim $U4 t4 sr_g1 > $SP/t4.out 2>&1
grep -q 'PRACTICE_SR_TICKET_NOT_AVAILABLE' $SP/t4.out && ok "T4 無券 NOT_AVAILABLE" || { bad "T4"; cat $SP/t4.out; }
srclaim $U1 t4b sr_g3 > $SP/t4b.out 2>&1
grep -q 'PRACTICE_SR_TICKET_NOT_AVAILABLE' $SP/t4b.out && ok "T4 已用新 requestId 重抽 NOT_AVAILABLE" || { bad "T4b"; cat $SP/t4b.out; }

# ── T5：同窗同 profile 撞號 → PROFILE_CONFLICT（券不消耗、可換張重試）────────
claim $U5 t5n g_dup > $SP/t5n.out 2>&1
srclaim $U5 t5sr g_dup > $SP/t5sr.out 2>&1
grep -q 'PRACTICE_DRAW_PROFILE_CONFLICT' $SP/t5sr.out && ok "T5 撞號 PROFILE_CONFLICT" || { bad "T5"; cat $SP/t5sr.out; }
CONS=$($P -c "select consumed_at is null from practice_sr_draw_tickets where user_id='$U5'")
[ "$CONS" = "t" ] && ok "T5 撞號後券未消耗（rollback 完整）" || bad "T5 券被誤消耗"
srclaim $U5 t5sr2 sr_g8 > $SP/t5sr2.out 2>&1
grep -q '"idempotent_replay": false' $SP/t5sr2.out && ok "T5 換張重抽成功" || { bad "T5 重抽"; cat $SP/t5sr2.out; }

echo "----"; echo "PASS=$PASS FAIL=$FAIL"
