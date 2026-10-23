"""
la16_eth_core: cocotb plays the ARM program ( sw/la16_eth ): registers over
the GP0 AXI3 slave, result read from the DDR model memory, like the ARM
reads the DDR ring.
"""
import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer

DDR_BASE = 0x0200_0000


async def wr(dut, off, val):
  """Single beat AXI3 write. Handshakes use the values just before the edge."""
  await FallingEdge(dut.clk)
  dut.s_awaddr.value = 0x43C0_0000 + off
  dut.s_awid.value = 0x123
  dut.s_awvalid.value = 1
  dut.s_wdata.value = val
  dut.s_wvalid.value = 1
  dut.s_bready.value = 1
  aw = w = b = False
  while not b:
    await RisingEdge(dut.clk)
    if not aw and int(dut.s_awready.value):
      aw = True
    if not w and int(dut.s_wready.value):
      w = True
    if int(dut.s_bvalid.value):
      assert int(dut.s_bid.value) == 0x123
      b = True
    await FallingEdge(dut.clk)
    if aw:
      dut.s_awvalid.value = 0
    if w:
      dut.s_wvalid.value = 0
  dut.s_bready.value = 0


async def rd(dut, off):
  """Single beat AXI3 read."""
  await FallingEdge(dut.clk)
  dut.s_araddr.value = 0x43C0_0000 + off
  dut.s_arid.value = 0x456
  dut.s_arvalid.value = 1
  dut.s_rready.value = 1
  ar = False
  while True:
    await RisingEdge(dut.clk)
    if not ar and int(dut.s_arready.value):
      ar = True
    elif ar and int(dut.s_rvalid.value):
      assert int(dut.s_rid.value) == 0x456 and int(dut.s_rlast.value) == 1
      v = int(dut.s_rdata.value)
      break
    await FallingEdge(dut.clk)
    if ar:
      dut.s_arvalid.value = 0
  await FallingEdge(dut.clk)
  dut.s_arvalid.value = 0
  dut.s_rready.value = 0
  return v


def ddr_sample(dut, j):
  w = int(dut.u_mem.mem[j // 4].value)
  return (w >> (16 * (j % 4))) & 0xFFFF


async def capture(dut, total, pre, div=0, tlm=0, tlv=0, trm=0, tfm=0):
  await wr(dut, 0x08, div)
  await wr(dut, 0x0C, total)
  await wr(dut, 0x10, pre)
  await wr(dut, 0x14, (tlv << 16) | tlm)
  await wr(dut, 0x18, (tfm << 16) | trm)
  await wr(dut, 0x04, 1)                     # ARM
  states = set()
  for _ in range(20000):
    st = await rd(dut, 0x1C)
    states.add(st & 7)
    if st & 0x08:
      break
    await Timer(200, unit="ns")
  assert st & 0x08, "capture not done, STATUS 0x%x" % st
  assert not st & 0x20, "overflow"
  start = await rd(dut, 0x24)
  ring = await rd(dut, 0x28)
  cap = await rd(dut, 0x20)
  assert cap == total
  data = [ddr_sample(dut, (start + i) % ring) for i in range(total)]
  return data, states, start, ring


@cocotb.test()
async def test_eth_core(dut):
  await ClockCycles(dut.clk, 20)
  assert await rd(dut, 0x00) == 0x4C413136
  assert await rd(dut, 0x30) == 65536
  assert await rd(dut, 0x2C) == DDR_BASE
  assert await rd(dut, 0x38) == 200_000_000
  await wr(dut, 0x34, 0x100)
  assert await rd(dut, 0x34) == 0x100 and int(dut.led.value) & 8
  for total, pre, div, trm, tlm, tlv, stall in ((4000, 1000, 0, 0x8000, 0, 0, 30),
                                                (1001, 0, 1, 0, 0, 0, 0),
                                                (5000, 4999, 2, 0, 0xFFFF, 0x2345, 60)):
    dut.u_mem.stall_pct.value = stall
    d, states, start, ring = await capture(dut, total, pre, div, tlm=tlm, tlv=tlv, trm=trm)
    bad = [i for i in range(1, total) if (d[i] - d[i - 1]) & 0xFFFF != div + 1]
    assert not bad, "step errors at %s" % bad[:5]
    if trm:
      assert not d[pre - 1] & 0x8000 and d[pre] & 0x8000
    if tlm:
      assert d[pre] == tlv
    dut._log.info("total %d pre %d div %d: ok ( start %d ring %d states %s )",
                  total, pre, div, start, ring, sorted(states))
  # ABORT while waiting
  await wr(dut, 0x0C, 500)
  await wr(dut, 0x10, 10)
  await wr(dut, 0x08, 0)
  await wr(dut, 0x14, (0x0001 << 16) | 0x0001)
  await wr(dut, 0x18, (0x0001 << 16))        # bit0 = 1 and falling: never
  await wr(dut, 0x04, 1)
  await Timer(5000, unit="ns")
  assert (await rd(dut, 0x1C)) & 7 == 2
  await wr(dut, 0x04, 2)
  await Timer(2000, unit="ns")
  st = await rd(dut, 0x1C)
  assert st & 7 == 0 and st & 0x10, hex(st)
  assert int(dut.u_mem.errors.value) == 0
  dut._log.info("ABORT ok, AXI model: %d write bursts, no errors", int(dut.u_mem.bursts_w.value))
