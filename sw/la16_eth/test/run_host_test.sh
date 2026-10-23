#!/bin/sh
# Host test of the ARM la16 server ( la16_server.c ) with the real libsigrok
# la16 driver over a real TCP connection ( tcp-raw, no test harness patches ).
#   SIGROK_CLI  sigrok-cli built with host/sigrok/libsigrok-la16-driver.patch
set -u
cd "$(dirname "$0")"
CLI=${SIGROK_CLI:-/opt/sigrok/bin/sigrok-cli}
OUT=build
mkdir -p $OUT
gcc -O2 -Wall -Wextra -Ishim -o $OUT/host_test host_test.c ../la16_server.c || exit 1
$OUT/host_test > $OUT/server.log 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null' EXIT
for i in $(seq 1 50); do grep -q LISTENING $OUT/server.log && break; sleep 0.1; done
DEV="la16:conn=tcp-raw/127.0.0.1/5555"
fail=0
run() { echo "\$ sigrok-cli $*"; "$CLI" "$@" 2>&1; }
cat > $OUT/check.py <<'P'
import sys
rows=[l.strip().split(',') for l in open(sys.argv[1]) if l.strip() and l[0] in '01']
v=[sum(int(b)<<i for i,b in enumerate(r[:16])) for r in rows]
step=int(sys.argv[2]); n=int(sys.argv[3])
bad=[i for i in range(1,len(v)) if (v[i]-v[i-1])&0xFFFF != step]
msg="samples=%d step_errors=%d"%(len(v),len(bad))
ok=len(v)==n and not bad
if len(sys.argv)>4:
  i=int(sys.argv[4]); p,c=v[i-1],v[i]
  t=eval(sys.argv[5])
  msg+=" at %d: 0x%04x -> 0x%04x %s"%(i,p,c,"ok" if t else "WRONG")
  ok=ok and t
print(msg); sys.exit(0 if ok else 1)
P
csv() { rm -f $OUT/cap.csv; run -d $DEV "$@" -O csv:header=false -o $OUT/cap.csv; }

echo "=== 1. scan"
run -d $DEV --scan | tee $OUT/scan.txt
grep -q "AntMiner S9 Ethernet" $OUT/scan.txt || { echo "FAIL scan"; fail=1; }
echo "=== 2. 200 MS/s, 100000 samples ( ring rotated )"
csv --config samplerate=200m --samples 100000
python3 $OUT/check.py $OUT/cap.csv 1 100000 || fail=1
echo "=== 3. 1 MS/s, 5000 samples"
csv --config samplerate=1m --samples 5000
python3 $OUT/check.py $OUT/cap.csv 200 5000 || fail=1
echo "=== 4. level trigger 0x1234, ratio 25 %"
TRG=$(python3 -c "print(','.join('D%d=%d'%(i,(0x1234>>i)&1) for i in range(16)))")
csv --config samplerate=200m:captureratio=25 --samples 4096 --triggers $TRG
python3 $OUT/check.py $OUT/cap.csv 1 4096 1024 "c==0x1234" || fail=1
echo "=== 5. rising edge D15, ratio 50 %"
csv --config samplerate=200m:captureratio=50 --samples 8192 --triggers D15=r
python3 $OUT/check.py $OUT/cap.csv 1 8192 4096 "not p&0x8000 and c&0x8000" || fail=1
echo "=== 6. falling edge D3 at 10 MS/s, ratio 10 %"
csv --config samplerate=10m:captureratio=10 --samples 2000 --triggers D3=f
python3 $OUT/check.py $OUT/cap.csv 20 2000 200 "p&8 and not c&8" || fail=1
echo "=== 7. 2M samples at 200 MS/s"
T0=$(date +%s.%N)
csv --config samplerate=200m --samples 2000000
T1=$(date +%s.%N)
python3 $OUT/check.py $OUT/cap.csv 1 2000000 || fail=1
python3 -c "print('2M samples ( 4 MB ) in %.1f s incl. CSV output' % ($T1 - $T0))"
echo "=== 8. three runs on one connection"
PCDIR=$(dirname "$CLI")/../lib/pkgconfig
if gcc -o $OUT/multirun ../../../sim/ols/ols_multirun.c $(PKG_CONFIG_PATH=$PCDIR pkg-config --cflags --libs libsigrok) 2>$OUT/multirun_cc.log; then
  SR_DRIVER=la16 LD_LIBRARY_PATH=$(dirname "$CLI")/../lib $OUT/multirun tcp-raw/127.0.0.1/5555 3 4096 || { echo "FAIL multirun"; fail=1; }
else
  echo "SKIP multirun"
fi
[ $fail -eq 0 ] && echo "HOST TEST PASS" || echo "HOST TEST FAIL"
exit $fail
