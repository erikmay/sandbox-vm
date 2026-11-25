#!/bin/bash
# Incus sandbox lifecycle benchmark. Needs a stopped container "base".
# Creates and deletes only instances named bench-*. Run as a user in incus-admin.
set -u
IMAGE=${IMAGE:-images:ubuntu/24.04}   # same image as base, so the launch test uses the cache
ms() { date +%s%N; }
d() { echo $(( ($2-$1)/1000000 )); }
wait_exec() { until incus exec "$1" -- true 2>/dev/null; do sleep 0.05; done; }
wait_net()  { until incus exec "$1" -- getent hosts archive.ubuntu.com >/dev/null 2>&1; do sleep 0.1; done; }
incus list -c n --format csv | grep -q '^bench-' && { echo "bench-* exist, abort"; exit 1; }

echo "== single sandbox, 5 rounds (ms)"
printf "%-6s %6s %6s %6s %6s %8s | %6s %6s %8s\n" run copy start exec net CREATE stop delete DESTROY
for i in 1 2 3 4 5; do n=bench-s$i
  t0=$(ms); incus copy base $n; t1=$(ms); incus start $n; t2=$(ms); wait_exec $n; t3=$(ms); wait_net $n; t4=$(ms)
  incus stop $n; t5=$(ms); incus delete $n; t6=$(ms)
  printf "%-6s %6s %6s %6s %6s %8s | %6s %6s %8s\n" $i $(d $t0 $t1) $(d $t1 $t2) $(d $t2 $t3) $(d $t3 $t4) $(d $t0 $t4) $(d $t4 $t5) $(d $t5 $t6) $(d $t4 $t6)
done

echo "== delete --force on a running sandbox, 3 rounds (ms)"
for i in 1 2 3; do n=bench-f$i; incus copy base $n; incus start $n; wait_exec $n
  t0=$(ms); incus delete --force $n; t1=$(ms); echo "delete --force: $(d $t0 $t1)"; done

echo "== launch from the cached image instead of copying base, 3 rounds (ms)"
for i in 1 2 3; do n=bench-i$i; t0=$(ms); incus launch "$IMAGE" $n >/dev/null; wait_exec $n; t1=$(ms); wait_net $n; t2=$(ms)
  echo "launch->exec: $(d $t0 $t1)  ->net: $(d $t0 $t2)"; incus delete --force $n; done

for N in 4 8; do
  echo "== $N sandboxes in parallel (wall clock ms)"
  t0=$(ms)
  for i in $(seq 1 $N); do ( incus copy base bench-p$i && incus start bench-p$i && wait_exec bench-p$i && wait_net bench-p$i ) & done; wait
  t1=$(ms); echo "create+start+network all $N: $(d $t0 $t1)"
  free -m | awk '/Mem:/{print "host RAM used MB: "$3"  available MB: "$7}'
  t0=$(ms); for i in $(seq 1 $N); do incus delete --force bench-p$i & done; wait; t1=$(ms)
  echo "delete --force all $N: $(d $t0 $t1)"
done

echo "== snapshot + restore of a running sandbox, 3 rounds (ms)"
incus copy base bench-r; incus start bench-r; wait_exec bench-r
for i in 1 2 3; do t0=$(ms); incus snapshot create bench-r clean$i; t1=$(ms)
  incus exec bench-r -- sh -c 'dd if=/dev/urandom of=/root/junk bs=1M count=200 status=none'
  t2=$(ms); incus snapshot restore bench-r clean$i; t3=$(ms); wait_exec bench-r; t4=$(ms)
  incus exec bench-r -- test -e /root/junk && echo "junk still there!"
  echo "snapshot: $(d $t0 $t1)  restore: $(d $t2 $t3)  ->exec: $(d $t2 $t4)"; done
incus delete --force bench-r
incus list -c n --format csv | grep '^bench-' || echo "cleanup ok: no bench-* left"
