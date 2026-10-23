"""
la16_engine unit tests ( cocotb + Icarus ), host side model of
docs/PROTOCOL_LA16.md. Samples are a 16 bit counter at the 200 MS/s base
rate ( +1 per base sample ), so every capture can be checked exactly.
DEPTH_BITS = 12 ( 4096 samples ), CLK_HZ = 1 MHz in tb_la16.v.
"""
import struct

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, ReadOnly, Timer

DEPTH = 4096


def crc8(data):
  c = 0
  for d in data:
    c ^= d
    for _ in range(8):
      c = ((c << 1) ^ 0x07) & 0xFF if c & 0x80 else (c << 1) & 0xFF
  return c


def frame(ftype, payload=b""):
  body = bytes([ftype]) + struct.pack("<H", len(payload)) + payload
  return b"\xA5" + body + bytes([crc8(body)])


def config(total, pre=0, div=0, tlm=0, tlv=0, trm=0, tfm=0, tmo=0, mode=0, fmt=0):
  return struct.pack("<BBHIIIHHHHII", mode, fmt, 0xFFFF, div, total, pre,
                     tlm, tlv, trm, tfm, tmo, 0)


class Host:
  def __init__(self, dut):
    self.dut = dut
    self.rx = bytearray()
    cocotb.start_soon(self._monitor())

  async def _monitor(self):
    # tx_take pulses one clock after each accepted byte, tx_last holds it
    while True:
      await RisingEdge(self.dut.tx_take)
      await ReadOnly()                       # tx_last updates in the same clock
      self.rx.append(int(self.dut.tx_last.value))

  async def reset(self):
    self.dut.reset.value = 1
    await ClockCycles(self.dut.clk, 5)
    self.dut.reset.value = 0
    await ClockCycles(self.dut.clk, 5)
    self.rx.clear()

  async def send_raw(self, data):
    for b in data:
      await FallingEdge(self.dut.clk)
      self.dut.rx_byte.value = b
      self.dut.rx_valid.value = 1
      await FallingEdge(self.dut.clk)
      self.dut.rx_valid.value = 0
      await ClockCycles(self.dut.clk, 2)

  async def send(self, ftype, payload=b""):
    await self.send_raw(frame(ftype, payload))

  def _parse_one(self):
    """Return ( type, payload ) or None. Checks sync and CRC strictly."""
    if len(self.rx) < 5:
      return None
    assert self.rx[0] == 0xA5, "bad sync 0x%02X" % self.rx[0]
    n = self.rx[2] | (self.rx[3] << 8)
    if len(self.rx) < n + 5:
      return None
    body = bytes(self.rx[1:4 + n])
    assert self.rx[4 + n] == crc8(body), "bad crc on frame type 0x%02X" % body[0]
    del self.rx[:n + 5]
    return body[0], body[3:]

  async def recv(self, timeout_clk=300_000):
    for _ in range(timeout_clk // 50):
      f = self._parse_one()
      if f is not None:
        return f
      await Timer(500, unit="ns")            # 50 clocks, one callback
    raise AssertionError("timeout waiting for a frame")

  async def expect(self, ftype):
    # STATUS frames can arrive at any time ( state changes ), skip them
    while True:
      t, p = await self.recv()
      if t != 0x83 or ftype == 0x83:
        break
    assert t == ftype, "expected 0x%02X got 0x%02X %s" % (ftype, t, p.hex())
    return p

  async def capture(self, cfg):
    """CONFIG + ARM, collect until END. Returns dict."""
    await self.send(0x02, cfg)
    p = await self.expect(0x82)
    assert p == b"\x02"
    await self.send(0x03)
    p = await self.expect(0x82)
    assert p == b"\x03"
    res = {"status": [], "trigger": None, "data": [], "end": None}
    while True:
      t, p = await self.recv()
      if t == 0x83:
        st, cap, tot = struct.unpack("<BII", p)
        res["status"].append(st)
      elif t == 0x85:
        assert not res["data"], "TRIGGER after DATA"
        res["trigger"] = struct.unpack("<I", p)[0]
      elif t == 0x84:
        first = struct.unpack("<I", p[:4])[0]
        assert first == len(res["data"]), "DATA index %d, have %d" % (first, len(res["data"]))
        res["data"] += list(struct.unpack("<%dH" % ((len(p) - 4) // 2), p[4:]))
      elif t == 0x86:
        res["end"] = struct.unpack("<IB", p)
        break
      else:
        raise AssertionError("unexpected frame 0x%02X" % t)
    # Trailing STATUS(5)
    t, p = await self.recv()
    assert t == 0x83 and p[0] == 5, "expected STATUS(5) after END"
    return res


def check_steps(data, step):
  bad = [i for i in range(1, len(data)) if (data[i] - data[i - 1]) & 0xFFFF != step]
  assert not bad, "step errors at %s ( %s )" % (bad[:5], [hex(data[i]) for i in bad[:5]])


async def setup(dut):
  h = Host(dut)
  await h.reset()
  return h


@cocotb.test()
async def test_ident_and_errors(dut):
  h = await setup(dut)
  await h.send(0x01)
  p = await h.expect(0x81)
  ver, ch, base, maxs, feat = struct.unpack("<BBIIH", p[:12])
  strings = p[12:].split(b"\x00")
  dut._log.info("IDENT v%d ch%d base %d max %d feat %d %s", ver, ch, base, maxs, feat, strings)
  assert (ver, ch, base, maxs, feat) == (1, 16, 200_000_000, DEPTH, 1)
  assert strings[:3] == [b"la16", b"AntMiner S9", b"0.1"]
  # Bad CRC
  f = bytearray(frame(0x01)); f[-1] ^= 0xFF
  await h.send_raw(f)
  assert await h.expect(0x8F) == b"\x01"
  # Unknown type
  await h.send(0x42)
  assert await h.expect(0x8F) == b"\x02"
  # Invalid configs: pre >= total, total > depth, RLE format, streaming mode
  for cfg in (config(100, pre=100), config(DEPTH + 1), config(100, fmt=1), config(100, mode=1)):
    await h.send(0x02, cfg)
    assert await h.expect(0x8F) == b"\x03"
  # Garbage before a frame is skipped ( resync on 0xA5 )
  await h.send_raw(b"\x00\x13\x37" + frame(0x05))
  p = await h.expect(0x83)
  assert p[0] in (0, 5)
  # STATUS? while idle
  await h.send(0x05)
  await h.expect(0x83)


@cocotb.test()
async def test_divider(dut):
  h = await setup(dut)
  for div in (0, 1, 2, 4, 99):
    r = await h.capture(config(1000, div=div))
    assert r["end"] == (1000, 0), r["end"]
    assert r["trigger"] is None
    assert len(r["data"]) == 1000
    check_steps(r["data"], div + 1)
    dut._log.info("div %d: %d samples, step %d, status %s", div, len(r["data"]), div + 1, r["status"])


@cocotb.test()
async def test_level_trigger_and_repeat(dut):
  h = await setup(dut)
  for run in range(3):
    pre = (100, 0, 777)[run]
    r = await h.capture(config(1500, pre=pre, tlm=0xFFFF, tlv=0x1234))
    assert r["trigger"] == pre, r["trigger"]
    assert r["end"] == (1500, 0)
    d = r["data"]
    check_steps(d, 1)
    assert d[pre] == 0x1234, hex(d[pre])
    for s in (1, 2, 3, 4):
      assert s in r["status"] or (s == 1 and pre == 0), "state %d not reported: %s" % (s, r["status"])
    dut._log.info("run %d pre %d: trigger ok, status %s", run, pre, r["status"])


@cocotb.test()
async def test_trigger_edges(dut):
  h = await setup(dut)
  cases = [
    # name, trm, tfm, tlm, tlv, check( prev, cur )
    ("rise b15", 0x8000, 0, 0, 0, lambda p, c: not p & 0x8000 and c & 0x8000),
    ("fall b0",  0, 0x0001, 0, 0, lambda p, c: p & 1 and not c & 1),
    ("rise b0",  0x0001, 0, 0, 0, lambda p, c: not p & 1 and c & 1),
    ("any b9",   0x0200, 0x0200, 0, 0, lambda p, c: (p ^ c) & 0x200),
    ("rise b4 & b5=1", 0x0010, 0, 0x0020, 0x0020,
     lambda p, c: not p & 0x10 and c & 0x10 and c & 0x20),
  ]
  for div in (0, 2):
    for name, trm, tfm, tlm, tlv, ok in cases:
      pre = 300
      dut._log.info("case %s div %d", name, div)
      r = await h.capture(config(800, pre=pre, div=div, trm=trm, tfm=tfm, tlm=tlm, tlv=tlv))
      d = r["data"]
      assert r["trigger"] == pre and len(d) == 800
      check_steps(d, div + 1)
      assert ok(d[pre - 1], d[pre]), "%s div %d: 0x%04X -> 0x%04X" % (name, div, d[pre - 1], d[pre])
    dut._log.info("edge triggers ok at div %d", div)


@cocotb.test()
async def test_full_depth(dut):
  h = await setup(dut)
  for pre in (0, 2048, DEPTH - 1):
    r = await h.capture(config(DEPTH, pre=pre, tlm=0xFFFF, tlv=0xBEEF))
    d = r["data"]
    assert len(d) == DEPTH and r["trigger"] == pre
    check_steps(d, 1)
    assert d[pre] == 0xBEEF
  dut._log.info("full depth ok ( ring wrap, pre 0 .. depth-1 )")


@cocotb.test()
async def test_abort_and_timeout(dut):
  h = await setup(dut)
  never = config(500, pre=10, tlm=0x0001, tlv=0x0001, tfm=0x0001)   # bit0 = 1 and falling
  # ABORT while waiting
  await h.send(0x02, never)
  await h.expect(0x82)
  await h.send(0x03)
  await h.expect(0x82)
  seen = []
  for _ in range(3):
    t, p = await h.recv()
    assert t == 0x83
    seen.append(p[0])
  assert 2 in seen, seen
  assert dut.armed.value == 1
  await h.send(0x04)
  got = {}
  while 0x86 not in got:
    t, p = await h.recv()
    got[t] = p
  assert got[0x82] == b"\x04"
  assert struct.unpack("<IB", got[0x86]) == (0, 0x02)
  assert dut.busy.value == 0
  # Periodic STATUS: 50 ms at CLK_HZ 1 MHz = 50k clocks, so a 120 ms wait gives >= 2
  # Timeout 120 ms
  await h.send(0x02, config(500, pre=10, tlm=0x0001, tlv=0x0001, tfm=0x0001, tmo=120))
  await h.expect(0x82)
  await h.send(0x03)
  await h.expect(0x82)
  n_status = 0
  while True:
    t, p = await h.recv(timeout_clk=400_000)
    if t == 0x83:
      n_status += 1
    elif t == 0x86:
      assert struct.unpack("<IB", p) == (0, 0x04), p.hex()
      break
  assert n_status >= 3, n_status
  dut._log.info("abort ok, timeout ok, %d STATUS frames during a 120 ms wait", n_status)
  # Busy: CONFIG / ARM during a capture
  await h.send(0x02, never)
  await h.expect(0x82)
  await h.send(0x03)
  await h.expect(0x82)
  await h.send(0x03)
  while True:
    t, p = await h.recv()
    if t == 0x8F:
      assert p == b"\x04"
      break
  await h.send(0x04)
  while (await h.recv())[0] != 0x86:
    pass
  # A normal capture still works afterwards
  r = await h.capture(config(600, pre=50, tlm=0xFFFF, tlv=0x4321))
  assert r["data"][50] == 0x4321
  check_steps(r["data"], 1)


@cocotb.test()
async def test_abort_during_upload(dut):
  h = await setup(dut)
  await h.send(0x02, config(DEPTH))
  await h.expect(0x82)
  await h.send(0x03)
  await h.expect(0x82)
  n = 0
  while True:
    t, p = await h.recv()
    if t == 0x84:
      n += (len(p) - 4) // 2
      if n >= 512:
        break
  await h.send(0x04)
  end = None
  while end is None:
    t, p = await h.recv()
    if t == 0x84:
      n += (len(p) - 4) // 2
    elif t == 0x86:
      end = struct.unpack("<IB", p)
  assert end[1] == 0x02 and end[0] == n and n < DEPTH, (end, n)
  dut._log.info("abort during upload: END after %d of %d samples", n, DEPTH)
