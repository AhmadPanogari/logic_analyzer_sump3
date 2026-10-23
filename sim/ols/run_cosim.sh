#!/bin/sh
# End-to-end test: real libsigrok OLS driver ( sigrok-cli ) <-> TCP <->
# cocotb <-> ols_engine RTL in Icarus Verilog.
#   Needs: iverilog, pip install cocotb, and sigrok-cli built from libsigrok git
#   ( serial over TCP, "tcp-raw" ) with libsigrok-tcpraw-testharness.patch
#   applied: the stock tcp-raw transport has no drain / rx-available hooks,
#   which the OLS driver needs ( a real COM port has them ).
#   SIGROK_CLI   default /opt/sigrok/bin/sigrok-cli
set -u
cd "$(dirname "$0")"
CLI=${SIGROK_CLI:-/opt/sigrok/bin/sigrok-cli}
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}:/opt/sigrok/lib
PORT=${OLS_PORT:-5555}
OUT=build_cosim
mkdir -p $OUT
export OLS_PORT=$PORT OLS_STOP_FILE=$PWD/$OUT/stop
rm -f $OLS_STOP_FILE
make > $OUT/sim.log 2>&1 &
SIM=$!
for i in $(seq 1 120); do grep -q LISTENING $OUT/sim.log 2>/dev/null && break; sleep 1; done
DEV="ols:conn=tcp-raw/127.0.0.1/$PORT"
fail=0
run() { echo "\$ sigrok-cli $*"; "$CLI" "$@" 2>&1; }

echo "=== 1. scan"
run -d $DEV --scan | tee $OUT/scan.txt
grep -q "AntMiner S9 LA" $OUT/scan.txt || { echo "FAIL scan"; fail=1; }

echo "=== 2. show"
run -d $DEV --show | tee $OUT/show.txt | head -20

echo "=== 3. counter, 100 MHz, 4096 samples, no trigger"
run -d $DEV --config samplerate=100m --samples 4096 -O csv:header=false -o $OUT/cnt100.csv
python3 - $OUT/cnt100.csv 1 <<'P' || fail=1
import sys
rows=[l.strip().split(',') for l in open(sys.argv[1]) if l.strip() and l[0] in '01']
vals=[sum(int(b)<<i for i,b in enumerate(r[:16])) for r in rows]
step=int(sys.argv[2])
bad=[i for i in range(1,len(vals)) if (vals[i]-vals[i-1])&0xFFFF != step]
print("samples=%d first=%04x last=%04x step_errors=%d"%(len(vals),vals[0],vals[-1],len(bad)))
sys.exit(1 if (len(vals)!=4096 or bad) else 0)
P

echo "=== 4. counter, 1 MHz ( divider 99 ), 2048 samples"
run -d $DEV --config samplerate=1m --samples 2048 -O csv:header=false -o $OUT/cnt1m.csv
python3 - $OUT/cnt1m.csv 100 <<'P' || fail=1
import sys
rows=[l.strip().split(',') for l in open(sys.argv[1]) if l.strip() and l[0] in '01']
vals=[sum(int(b)<<i for i,b in enumerate(r[:16])) for r in rows]
step=int(sys.argv[2])
bad=[i for i in range(1,len(vals)) if (vals[i]-vals[i-1])&0xFFFF != step]
print("samples=%d step_errors=%d"%(len(vals),len(bad)))
sys.exit(1 if (len(vals)!=2048 or bad) else 0)
P

echo "=== 5. trigger: counter value 0x1234 ( mask all 16 bits ), ratio 25 %"
TRG=$(python3 -c "print(','.join('%d=%d'%(i,(0x1234>>i)&1) for i in range(16)))")
run -d $DEV --config samplerate=100m:captureratio=25 --samples 4096 --triggers $TRG -O csv:header=false -o $OUT/trig.csv
python3 - $OUT/trig.csv <<'P' || fail=1
import sys
rows=[l.strip().split(',') for l in open(sys.argv[1]) if l.strip() and l[0] in '01']
vals=[sum(int(b)<<i for i,b in enumerate(r[:16])) for r in rows]
i=vals.index(0x1234) if 0x1234 in vals else -1
print("samples=%d index_of_0x1234=%d ( expect ~%d )"%(len(vals),i,4096*25//100))
sys.exit(0 if 900 <= i <= 1150 else 1)
P

echo "=== 6. internal pattern, 1 MHz, 65536 samples -> UART / SPI decoders"
run -d $DEV --config samplerate=1m:pattern=Internal --samples 65536 -o $OUT/pattern.sr
"$CLI" -i $OUT/pattern.sr -P uart:rx=0:baudrate=115200:format=ascii -A uart=rx-data 2>&1 | sed 's/uart-1: //' | tr -d '\n' | tee $OUT/uart.txt; echo
grep -q "Hello SUMP3 PulseView" $OUT/uart.txt || { echo "FAIL uart decode"; fail=1; }
echo "=== 7. internal pattern, 100 MHz, 65536 samples -> SPI decoder ( 1 MHz SPI )"
run -d $DEV --config samplerate=100m:pattern=Internal --samples 65536 -o $OUT/spi.sr
"$CLI" -i $OUT/spi.sr -P spi:clk=1:mosi=2:miso=3:cs=4 -A spi=mosi-data 2>&1 | sed 's/spi-1: //' | tr '\n' ' ' | tee $OUT/spi.txt; echo
python3 - $OUT/spi.txt <<'P' || fail=1
import sys
v=[int(x,16) for x in open(sys.argv[1]).read().split()]
bad=[i for i in range(1,len(v)) if (v[i]-v[i-1])&0xFF != 1]
print("spi bytes=%d sequence_errors=%d"%(len(v),len(bad)))
sys.exit(1 if len(v) < 20 or bad else 0)
P

echo "=== 8. three runs on one open connection ( PulseView pressing Run again )"
PCDIR=$(dirname "$CLI")/../lib/pkgconfig
if gcc -o $OUT/ols_multirun ols_multirun.c $(PKG_CONFIG_PATH=$PCDIR pkg-config --cflags --libs libsigrok) 2>$OUT/multirun_cc.log; then
  $OUT/ols_multirun tcp-raw/127.0.0.1/$PORT 3 2048 || { echo "FAIL multirun"; fail=1; }
else
  echo "SKIP multirun ( build failed, see $OUT/multirun_cc.log )"
fi

touch $OLS_STOP_FILE
wait $SIM
[ $fail -eq 0 ] && echo "COSIM PASS" || echo "COSIM FAIL"
exit $fail
