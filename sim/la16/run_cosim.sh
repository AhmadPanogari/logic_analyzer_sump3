#!/bin/sh
# End-to-end test: libsigrok la16 driver ( sigrok-cli ) <-> TCP <-> cocotb
# <-> la16_engine RTL in Icarus Verilog.
#   Needs: iverilog, pip install cocotb, and sigrok-cli from libsigrok git with
#   host/sigrok/libsigrok-la16-driver.patch and
#   sim/ols/libsigrok-tcpraw-testharness.patch applied ( --enable-la16 ).
#   SIGROK_CLI   default /opt/sigrok/bin/sigrok-cli
#   USE_DDR=1    ring buffer through the AXI3 DDR model ( 262144 samples )
set -u
cd "$(dirname "$0")"
CLI=${SIGROK_CLI:-/opt/sigrok/bin/sigrok-cli}
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}:$(dirname "$CLI")/../lib
PORT=${LA16_PORT:-5565}
OUT=build_cosim
mkdir -p $OUT
export LA16_PORT=$PORT LA16_STOP_FILE=$PWD/$OUT/stop
rm -f $LA16_STOP_FILE
USE_DDR=${USE_DDR:-0}
make -f Makefile.cosim USE_DDR=$USE_DDR > $OUT/sim.log 2>&1 &
SIM=$!
for i in $(seq 1 120); do grep -q LISTENING $OUT/sim.log 2>/dev/null && break; sleep 1; done
grep -q LISTENING $OUT/sim.log || { echo "FAIL: simulation did not start, see $OUT/sim.log"; exit 1; }
rm -f $OUT/cap.csv
DEV="la16:conn=tcp-raw/127.0.0.1/$PORT"
fail=0
run() { echo "\$ sigrok-cli $*"; "$CLI" "$@" 2>&1; }

# check.py <csv> <step> <samples> [ <index> <expr on prev,cur> ]
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
csv() { run -d $DEV "$@" -O csv:header=false -o $OUT/cap.csv; }

echo "=== 1. scan"
run -d $DEV --scan | tee $OUT/scan.txt
grep -q "AntMiner S9" $OUT/scan.txt || { echo "FAIL scan"; fail=1; }

echo "=== 2. show"
run -d $DEV --show | tee $OUT/show.txt | head -30

echo "=== 3. 200 MS/s, 4096 samples, no trigger"
csv --config samplerate=200m --samples 4096
python3 $OUT/check.py $OUT/cap.csv 1 4096 || fail=1

echo "=== 4. 1 MS/s ( divider 199 ), 2048 samples"
csv --config samplerate=1m --samples 2048
python3 $OUT/check.py $OUT/cap.csv 200 2048 || fail=1

echo "=== 5. level trigger 0x1234 ( 16 bits ), ratio 25 %"
TRG=$(python3 -c "print(','.join('D%d=%d'%(i,(0x1234>>i)&1) for i in range(16)))")
csv --config samplerate=200m:captureratio=25 --samples 4096 --triggers $TRG
python3 $OUT/check.py $OUT/cap.csv 1 4096 1024 "c==0x1234" || fail=1

echo "=== 6. rising edge D15, ratio 50 %, 8192 samples"
csv --config samplerate=200m:captureratio=50 --samples 8192 --triggers D15=r
python3 $OUT/check.py $OUT/cap.csv 1 8192 4096 "not p&0x8000 and c&0x8000" || fail=1

echo "=== 7. falling edge D3 at 10 MS/s, ratio 10 %"
csv --config samplerate=10m:captureratio=10 --samples 2000 --triggers D3=f
python3 $OUT/check.py $OUT/cap.csv 20 2000 200 "p&8 and not c&8" || fail=1

echo "=== 8. full depth: 65536 samples at 200 MS/s"
csv --config samplerate=200m --samples 65536
python3 $OUT/check.py $OUT/cap.csv 1 65536 || fail=1

if [ "$USE_DDR" = 1 ]; then
  echo "=== 8b. DDR: 200000 samples at 200 MS/s, rising edge D15, ratio 30 %"
  csv --config samplerate=200m:captureratio=30 --samples 200000 --triggers D15=r
  python3 $OUT/check.py $OUT/cap.csv 1 200000 60000 "not p&0x8000 and c&0x8000" || fail=1
fi

echo "=== 9. three runs on one open connection ( PulseView pressing Run again )"
PCDIR=$(dirname "$CLI")/../lib/pkgconfig
if gcc -o $OUT/multirun ../ols/ols_multirun.c $(PKG_CONFIG_PATH=$PCDIR pkg-config --cflags --libs libsigrok) 2>$OUT/multirun_cc.log; then
  SR_DRIVER=la16 $OUT/multirun tcp-raw/127.0.0.1/$PORT 3 2048 || { echo "FAIL multirun"; fail=1; }
else
  echo "SKIP multirun ( build failed, see $OUT/multirun_cc.log )"
fi

touch $LA16_STOP_FILE
wait $SIM
[ $fail -eq 0 ] && echo "COSIM PASS" || echo "COSIM FAIL"
exit $fail
