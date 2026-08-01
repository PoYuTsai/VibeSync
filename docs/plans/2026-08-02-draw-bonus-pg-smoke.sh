#!/bin/bash
# 批 3 贈抽原子化 PG 併發 smoke（Codex 二輪 P3 回應）。scratch PG16、真交易屏障。
set -u
SP=/tmp/claude-1000/-mnt-c-Users-eric1-OneDrive-Desktop-VibeSync/13030f9f-d8bd-47ea-9984-eeb1a4b42ab6/scratchpad
PGSOCK=$(cat $SP/pgsock_path)
P="psql -U postgres -h $PGSOCK -p 54329 -d postgres -qtA"
W1='2026-08-01T04:00:00Z'; W2='2026-08-02T04:00:00Z'
PASS=0; FAIL=0
ok(){ echo "PASS: $1"; PASS=$((PASS+1)); }
bad(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

seed(){ # $1=uuid $2=tier
  $P -c "insert into auth.users values ('$1'); insert into public.subscriptions (user_id,tier) values ('$1','$2');"
}
grantb(){ $P -c "insert into public.practice_draw_bonuses (user_id) values ('$1');"; }
claim(){ # user req profile window tier allowance allow_paid daily monthly
  $P -c "select public.claim_practice_profile_draw('$1','$2','$3','$4','$5',$6,5,$7,$8,$9,true);" 2>&1
}

U1=11111111-1111-1111-1111-111111111111
U3=33333333-3333-3333-3333-333333333333
U2=22222222-2222-2222-2222-222222222222
U4=44444444-4444-4444-4444-444444444444
U5=55555555-5555-5555-5555-555555555555
seed $U1 free >/dev/null; grantb $U1 >/dev/null
seed $U3 free >/dev/null; grantb $U3 >/dev/null
seed $U2 starter >/dev/null; grantb $U2 >/dev/null
seed $U4 free >/dev/null
seed $U5 starter >/dev/null

# ── S1：跨窗不同 requestId 併發——同顆贈抽絕不雙花 ─────────────────────────
(
  psql -U postgres -h $PGSOCK -p 54329 -d postgres -qtA <<EOF > $SP/s1a.out 2>&1
begin;
select public.claim_practice_profile_draw('$U1','r1','g1','$W1','free',0,5,false,15,30,true);
select pg_sleep(2);
commit;
EOF
) &
A=$!
sleep 0.6
claim $U1 r2 g2 "$W2" free 0 false 15 30 > $SP/s1b.out 2>&1
wait $A
grep -q '"cost_messages": 0' $SP/s1a.out && grep -q 'PRACTICE_DRAW_UPGRADE_REQUIRED' $SP/s1b.out \
  && ok "S1 跨窗併發：先到 cost0、後到 402（不雙花）" || { bad "S1"; cat $SP/s1a.out $SP/s1b.out; }
C=$($P -c "select count(*) from practice_profile_draw_events where user_id='$U1' and cost_messages=0")
[ "$C" = "1" ] && ok "S1 帳本恰一筆 cost0" || bad "S1 帳本 cost0=$C"
CONS=$($P -c "select consumed_at is not null from practice_draw_bonuses where user_id='$U1'")
[ "$CONS" = "t" ] && ok "S1 贈抽已消耗" || bad "S1 贈抽未消耗"

# ── S2：同 requestId 併發——後到者必回 replay，不 402 ──────────────────────
(
  psql -U postgres -h $PGSOCK -p 54329 -d postgres -qtA <<EOF > $SP/s2a.out 2>&1
begin;
select public.claim_practice_profile_draw('$U3','rX','g1','$W1','free',0,5,false,15,30,true);
select pg_sleep(2);
commit;
EOF
) &
A=$!
sleep 0.6
claim $U3 rX g9 "$W1" free 0 false 15 30 > $SP/s2b.out 2>&1
wait $A
grep -q '"idempotent_replay": true' $SP/s2b.out && grep -q '"profile_id": "g1"' $SP/s2b.out \
  && ok "S2 同 requestId 併發：後到 replay 原 profile（冪等保住）" || { bad "S2"; cat $SP/s2b.out; }
C=$($P -c "select count(*) from practice_profile_draw_events where user_id='$U3'")
[ "$C" = "1" ] && ok "S2 帳本恰一筆" || bad "S2 帳本=$C"
CONS=$($P -c "select count(*) from practice_draw_bonuses where user_id='$U3' and consumed_at is not null")
[ "$CONS" = "1" ] && ok "S2 贈抽恰消耗一次" || bad "S2 消耗=$CONS"

# ── S3：starter 邊界——前 3 抽不動贈抽、第 4 抽消耗、第 5 抽付費扣 5 ────────
for i in 1 2 3; do claim $U2 s$i gs$i "$W1" starter 3 true 50 300 > $SP/s3_$i.out 2>&1; done
CONS=$($P -c "select consumed_at is null from practice_draw_bonuses where user_id='$U2'")
[ "$CONS" = "t" ] && ok "S3 tier 額度內三抽不消耗贈抽" || bad "S3 提前消耗"
claim $U2 s4 gs4 "$W1" starter 3 true 50 300 > $SP/s3_4.out 2>&1
grep -q '"cost_messages": 0' $SP/s3_4.out && ok "S3 第 4 抽 cost0（贈抽生效）" || { bad "S3 第4抽"; cat $SP/s3_4.out; }
CONS=$($P -c "select consumed_at is not null from practice_draw_bonuses where user_id='$U2'")
[ "$CONS" = "t" ] && ok "S3 第 4 抽後贈抽消耗" || bad "S3 第4抽未消耗"
claim $U2 s5 gs5 "$W1" starter 3 true 50 300 > $SP/s3_5.out 2>&1
grep -q '"cost_messages": 5' $SP/s3_5.out && ok "S3 第 5 抽付費扣 5" || { bad "S3 第5抽"; cat $SP/s3_5.out; }
MU=$($P -c "select monthly_messages_used from subscriptions where user_id='$U2'")
[ "$MU" = "5" ] && ok "S3 月計數恰 +5" || bad "S3 月計數=$MU"

# ── S4：舊 event replay 不消耗後來才 grant 的贈抽 ──────────────────────────
$P -c "insert into practice_profile_draw_events (user_id,request_id,profile_id,tier_at_draw,reset_window_start_at,cost_messages) values ('$U4','r_old','gOld','$W1','free','$W1',0)" >/dev/null
grantb $U4 >/dev/null
claim $U4 r_old gNew "$W1" free 0 false 15 30 > $SP/s4.out 2>&1
grep -q '"idempotent_replay": true' $SP/s4.out && grep -q '"profile_id": "gOld"' $SP/s4.out \
  && ok "S4 舊 requestId replay 回原 profile" || { bad "S4 replay"; cat $SP/s4.out; }
CONS=$($P -c "select consumed_at is null from practice_draw_bonuses where user_id='$U4'")
[ "$CONS" = "t" ] && ok "S4 replay 不消耗贈抽" || bad "S4 贈抽被誤消耗"

# ── S5：同窗同 profile 撞號 → PROFILE_CONFLICT rollback 後換張成功 ─────────
claim $U5 c1 gC "$W1" starter 3 true 50 300 >/dev/null 2>&1
claim $U5 c2 gC "$W1" starter 3 true 50 300 > $SP/s5a.out 2>&1
grep -q 'PRACTICE_DRAW_PROFILE_CONFLICT' $SP/s5a.out && ok "S5 撞號回 CONFLICT" || { bad "S5 撞號"; cat $SP/s5a.out; }
claim $U5 c2 gD "$W1" starter 3 true 50 300 > $SP/s5b.out 2>&1
grep -q '"cost_messages": 0' $SP/s5b.out && ok "S5 rollback 後換張重呼成功" || { bad "S5 重呼"; cat $SP/s5b.out; }
C=$($P -c "select count(*) from practice_profile_draw_events where user_id='$U5'")
[ "$C" = "2" ] && ok "S5 帳本兩筆（無殘留半交易）" || bad "S5 帳本=$C"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ]
