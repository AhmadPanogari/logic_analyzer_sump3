#!/usr/bin/env python3
"""
sump3_vcd2sr.py : Convert a SUMP3 ( sump3.py save_vcd ) VCD file into a
sigrok session file ( *.sr ) and optionally open it in PulseView.

Why not let PulseView import the VCD directly?
  * sump3.py writes VCD with "$timescale 1ps". PulseView's VCD importer turns
    every timescale unit into a sample, i.e. 1 THz, which explodes memory.
  * SUMP3 RLE pods compress, so a capture can span seconds with only a few
    thousand edges. PulseView needs uniformly sampled data at a sane rate.
  * Vectors ( "b0101 code" ) are split into one PulseView channel per bit.

Output is a standard sigrok "srzip" v2 session ( metadata + logic-1-N ),
readable by PulseView and sigrok-cli.

Usage:
  sump3_vcd2sr.py capture.vcd                       -> capture.sr
  sump3_vcd2sr.py capture.vcd -o out.sr --samplerate 100M
  sump3_vcd2sr.py capture.vcd --open                -> also launch PulseView
  sump3_vcd2sr.py capture.vcd --include "D[0-9]+" --exclude "demo_cnt.*"

Only the Python 3 standard library is required.
"""

import argparse
import math
import os
import re
import shutil
import subprocess
import sys
import zipfile

CHUNK_BYTES = 4 * 1024 * 1024   # Size of each logic-1-N member in the zip

TIMESCALE_UNITS = {
  "s": 1.0, "ms": 1e-3, "us": 1e-6, "ns": 1e-9, "ps": 1e-12, "fs": 1e-15,
}


class VcdSignal:
  def __init__(self, code, width, name, scope):
    self.code  = code
    self.width = width
    self.name  = name
    self.scope = scope
    self.changes = []   # [ (time, int_value) ]


def parse_value(txt):
  """Binary string -> int. All x/z -> None ( hold last value ), mixed -> 0."""
  txt = txt.lower()
  if txt and all(c in "xzu-" for c in txt):
    return None
  txt = txt.replace("x", "0").replace("z", "0").replace("u", "0")
  txt = txt.replace("-", "0").replace("w", "0").replace("l", "0").replace("h", "1")
  return int(txt, 2) if txt else 0


def parse_vcd(filename):
  """Returns ( timescale_seconds, [VcdSignal], end_time )."""
  timescale = 1e-12
  signals_by_code = {}
  signals = []
  scope = []
  t_now = 0
  t_end = 0

  with open(filename, "r", errors="replace") as f:
    data = f.read()
  tokens = data.split()
  i = 0
  n = len(tokens)
  in_defs = True
  while i < n:
    tok = tokens[i]
    if tok in ("$dumpvars", "$dumpall", "$dumpon", "$dumpoff", "$end"):
      # Values inside these blocks are ordinary value changes. sump3.py
      # writes "$dumpvars" without a closing "$end".
      i += 1
      continue
    if tok.startswith("$"):
      kw = tok
      # Collect everything until $end
      j = i + 1
      body = []
      while j < n and tokens[j] != "$end":
        body.append(tokens[j])
        j += 1
      i = j + 1
      if kw == "$timescale":
        m = re.match(r"^(\d+)\s*([a-z]+)$", "".join(body).lower())
        if m:
          timescale = int(m.group(1)) * TIMESCALE_UNITS[m.group(2)]
      elif kw == "$scope":
        scope.append(body[1] if len(body) > 1 else "")
      elif kw == "$upscope":
        if scope:
          scope.pop()
      elif kw == "$var":
        # $var type width code name [range] $end
        width = int(body[1])
        code  = body[2]
        name  = body[3]
        if len(body) > 4 and body[4].startswith("["):
          name += body[4]
        if code in signals_by_code:
          continue   # Alias of an existing signal
        sig = VcdSignal(code, width, name, ".".join(scope))
        signals_by_code[code] = sig
        signals.append(sig)
      elif kw == "$enddefinitions":
        in_defs = False
      continue
    if in_defs:
      i += 1
      continue
    if tok[0] == "#":
      t_now = int(tok[1:])
      t_end = max(t_end, t_now)
      i += 1
      continue
    i = handle_value(tokens, i, signals_by_code, t_now)
  return timescale, signals, t_end


def handle_value(tokens, i, signals_by_code, t_now):
  tok = tokens[i]
  c = tok[0]
  if c in "bB":
    val  = tok[1:]
    code = tokens[i + 1]
    sig = signals_by_code.get(code)
    if sig is not None:
      add_change(sig, t_now, parse_value(val))
    return i + 2
  if c in "rR":
    return i + 2   # Real values are not supported, skip
  if c in "01xXzZuU":
    code = tok[1:]
    sig = signals_by_code.get(code)
    if sig is not None:
      add_change(sig, t_now, parse_value(c))
    return i + 1
  return i + 1


def add_change(sig, t, val):
  if val is None:
    return   # sump3.py ends every signal with "x" : keep the last value
  if sig.changes and sig.changes[-1][0] == t:
    sig.changes[-1] = (t, val)
  elif not sig.changes or sig.changes[-1][1] != val:
    sig.changes.append((t, val))


def parse_rate(txt):
  m = re.match(r"^\s*([0-9.]+)\s*([kKmMgG]?)\s*(hz|Hz|HZ)?\s*$", txt)
  if not m:
    raise ValueError("Bad samplerate '%s' ( use e.g. 100M, 12.5MHz, 1000000 )" % txt)
  mult = {"": 1, "k": 1e3, "m": 1e6, "g": 1e9}[m.group(2).lower()]
  return int(round(float(m.group(1)) * mult))


def rate_string(rate):
  for div, unit in ((1000000000, "GHz"), (1000000, "MHz"), (1000, "kHz")):
    if rate % div == 0:
      return "%d %s" % (rate // div, unit)
  return "%d Hz" % rate


def auto_samplerate(signals, timescale):
  """Guess the capture clock from the edge times: GCD of all deltas."""
  times = sorted({t for s in signals for (t, _) in s.changes})
  if len(times) < 2:
    return 1000000
  g = 0
  for a, b in zip(times, times[1:]):
    g = math.gcd(g, b - a)
  rate = int(round(1.0 / (g * timescale)))
  if rate > 1000000000:
    # Rounding noise in the timestamps. Fall back to the smallest delta.
    d_min = min(b - a for a, b in zip(times, times[1:]))
    rate = int(round(1.0 / (d_min * timescale)))
  return max(1, min(rate, 1000000000))


class ChunkWriter:
  """Streams raw logic samples into logic-1-1, logic-1-2, ... zip members."""

  def __init__(self, zf, unitsize):
    self.zf = zf
    self.unitsize = unitsize
    self.chunk_num = 0
    self.buf = bytearray()
    self.total = 0

  def write_run(self, value, count):
    raw = value.to_bytes(self.unitsize, "little")
    while count > 0:
      room = (CHUNK_BYTES - len(self.buf)) // self.unitsize
      n = min(room, count)
      self.buf += raw * n
      count -= n
      self.total += n
      if len(self.buf) >= CHUNK_BYTES:
        self.flush()

  def flush(self):
    if self.buf:
      self.chunk_num += 1
      self.zf.writestr("logic-1-%d" % self.chunk_num, bytes(self.buf))
      self.buf = bytearray()


def build_channels(signals, args):
  """Expand vectors into bits and apply include / exclude filters."""
  inc = re.compile(args.include) if args.include else None
  exc = re.compile(args.exclude) if args.exclude else None
  channels = []   # [ (name, signal, bit) ]
  for sig in signals:
    if not sig.changes:
      continue
    base = sig.name
    if args.hier and sig.scope:
      base = sig.scope + "." + base
    m = re.match(r"^(.*)\[(\d+):(\d+)\]$", base)
    if sig.width == 1:
      names = [base]
    else:
      if m:
        stem, msb, lsb = m.group(1), int(m.group(2)), int(m.group(3))
      else:
        stem, msb, lsb = base, sig.width - 1, 0
      step = 1 if lsb <= msb else -1
      names = ["%s[%d]" % (stem, lsb + k * step) for k in range(sig.width)]
    for bit, name in enumerate(names):
      if inc and not inc.search(name):
        continue
      if exc and exc.search(name):
        continue
      channels.append((name, sig, bit))
  # Make names unique for PulseView
  seen = {}
  out = []
  for name, sig, bit in channels:
    if name in seen:
      seen[name] += 1
      name = "%s_%d" % (name, seen[name])
    else:
      seen[name] = 0
    out.append((name, sig, bit))
  return out


def convert(args):
  timescale, signals, t_end = parse_vcd(args.vcd)
  channels = build_channels(signals, args)
  if not channels:
    sys.exit("ERROR: no signals with value changes found in %s" % args.vcd)

  if args.samplerate.lower() == "auto":
    rate = auto_samplerate([c[1] for c in channels], timescale)
  else:
    rate = parse_rate(args.samplerate)

  all_times = [t for (_, s, _) in channels for (t, _) in s.changes]
  t0 = min(all_times)
  t_last = max(max(all_times), t_end)

  def to_index(t):
    return int(round((t - t0) * timescale * rate))

  start_idx = 0
  if args.start is not None:
    start_idx = max(0, int(round(args.start * rate)))
  end_idx = to_index(t_last) + 1
  if args.end is not None:
    end_idx = min(end_idx, int(round(args.end * rate)) + 1)

  total = end_idx - start_idx
  decim = 1
  if total > args.max_samples:
    decim = int(math.ceil(total / float(args.max_samples)))
    print("WARNING: %d samples at %s exceeds --max-samples %d." %
          (total, rate_string(rate), args.max_samples))
    print("         Decimating by %d. Pulses shorter than %.3g s may be lost." %
          (decim, decim / float(rate)))
    print("         Use --start/--end to zoom instead of decimating.")
    rate_out = max(1, int(round(rate / float(decim))))
  else:
    rate_out = rate

  # Merge every channel change into one time ordered event list
  events = {}   # sample_index -> [ (channel_i, bit_value) ]
  for ch_i, (name, sig, bit) in enumerate(channels):
    for (t, val) in sig.changes:
      idx = to_index(t) // decim
      events.setdefault(idx, []).append((ch_i, (val >> bit) & 1))

  first = start_idx // decim
  last  = (end_idx - 1) // decim
  nch = len(channels)
  unitsize = max(1, (nch + 7) // 8)

  out = args.output or os.path.splitext(args.vcd)[0] + ".sr"
  with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    zf.writestr("version", "2")
    meta  = "[global]\n"
    meta += "sigrok version=0.5.2\n\n"
    meta += "[device 1]\n"
    meta += "capturefile=logic-1\n"
    meta += "total probes=%d\n" % nch
    meta += "samplerate=%s\n" % rate_string(rate_out)
    meta += "total analog=0\n"
    for k, (name, _, _) in enumerate(channels):
      meta += "probe%d=%s\n" % (k + 1, name)
    meta += "unitsize=%d\n" % unitsize
    zf.writestr("metadata", meta)

    cw = ChunkWriter(zf, unitsize)
    word = 0
    pos = first
    for idx in sorted(events):
      if idx > last:
        break
      if idx > pos:
        cw.write_run(word, idx - pos)
        pos = idx
      for ch_i, b in events[idx]:
        if b:
          word |= (1 << ch_i)
        else:
          word &= ~(1 << ch_i)
    if last + 1 > pos:
      cw.write_run(word, last + 1 - pos)
    cw.flush()

  print("Wrote %s : %d channels, %d samples @ %s ( %.6g s )" %
        (out, nch, cw.total, rate_string(rate_out), cw.total / float(rate_out)))
  return out


def find_pulseview(user_path):
  cands = []
  if user_path:
    cands.append(user_path)
  env = os.environ.get("PULSEVIEW")
  if env:
    cands.append(env)
  which = shutil.which("pulseview")
  if which:
    cands.append(which)
  cands += [
    r"C:\Program Files\sigrok\PulseView\pulseview.exe",
    r"C:\Program Files (x86)\sigrok\PulseView\pulseview.exe",
    "/Applications/PulseView.app/Contents/MacOS/pulseview",
    "/usr/bin/pulseview",
    "/usr/local/bin/pulseview",
  ]
  for c in cands:
    if c and os.path.isfile(c):
      return c
  return None


def launch_pulseview(sr_file, user_path):
  pv = find_pulseview(user_path)
  if pv is None:
    print("ERROR: PulseView not found. Install it or pass --pulseview PATH")
    return False
  cmd = [pv, "-i", os.path.abspath(sr_file)]
  print("Launching: %s" % " ".join(cmd))
  kw = {}
  if os.name == "nt":
    kw["creationflags"] = 0x00000008 | 0x00000200  # DETACHED | NEW_GROUP
  else:
    kw["start_new_session"] = True
  # Detach so sump3.py ( which calls us via os.system ) does not block
  subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, close_fds=True, **kw)
  return True


def main():
  p = argparse.ArgumentParser(description="SUMP3 VCD -> sigrok .sr for PulseView")
  p.add_argument("vcd", help="VCD file written by sump3.py save_vcd")
  p.add_argument("-o", "--output", help="Output .sr ( default: same name as VCD )")
  p.add_argument("-r", "--samplerate", default=os.environ.get("SUMP3_SAMPLERATE", "auto"),
                 help="Sample rate, e.g. 100M ( = SUMP3 clk_cap ). Default auto")
  p.add_argument("--max-samples", type=int,
                 default=int(os.environ.get("SUMP3_MAX_SAMPLES", "200000000")),
                 help="Decimate above this many samples ( default 200M )")
  p.add_argument("--start", type=float, help="Crop start, seconds from capture start")
  p.add_argument("--end", type=float, help="Crop end, seconds from capture start")
  p.add_argument("--include", help="Regex, keep only matching channel names")
  p.add_argument("--exclude", help="Regex, drop matching channel names")
  p.add_argument("--hier", action="store_true", help="Prefix names with VCD scope")
  p.add_argument("--open", action="store_true", help="Open the result in PulseView")
  p.add_argument("--pulseview", help="Path to pulseview executable")
  args = p.parse_args()

  sr = convert(args)
  if args.open:
    if not launch_pulseview(sr, args.pulseview):
      sys.exit(1)


if __name__ == "__main__":
  main()
