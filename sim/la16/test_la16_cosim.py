"""
cocotb bridge: TCP socket <-> la16_engine bytes.
libsigrok connects with conn=tcp-raw/127.0.0.1/$LA16_PORT ( one connection
per scan / acquisition ). Runs until $LA16_STOP_FILE exists.
"""
import os
import socket

import cocotb
import cocotb.utils
from cocotb.triggers import RisingEdge, FallingEdge, Timer, First


@cocotb.test()
async def la16_bridge(dut):
  port = int(os.environ.get("LA16_PORT", "5555"))
  stop_file = os.environ.get("LA16_STOP_FILE", "/tmp/la16_stop")
  srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
  srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
  srv.bind(("127.0.0.1", port))
  srv.listen(4)
  srv.setblocking(False)
  print("LISTENING %d" % port, flush=True)

  conn = None
  rxq = bytearray()
  txq = bytearray()
  n_rx = n_tx = 0
  await Timer(200, unit="ns")

  while True:
    # --- socket service ---
    if conn is None:
      try:
        conn, _ = srv.accept()
        conn.setblocking(False)
        print("client connected", flush=True)
      except BlockingIOError:
        pass
    if conn is not None:
      try:
        d = conn.recv(4096)
        if d == b"":
          conn.close(); conn = None
          print("client closed ( rx %d, tx %d )" % (n_rx, n_tx), flush=True)
        else:
          rxq += d
      except BlockingIOError:
        pass
      except ConnectionResetError:
        conn = None
      if conn is not None and txq:
        try:
          sent = conn.send(bytes(txq))
          del txq[:sent]
        except BlockingIOError:
          pass
        except (BrokenPipeError, ConnectionResetError):
          conn = None
    if conn is None:
      txq.clear()
      if os.path.exists(stop_file):
        break

    # --- RTL service ---
    # Inputs change on the falling edge so the RTL samples them cleanly
    # on the rising edge ( no race with cocotb writes ).
    if rxq:
      await FallingEdge(dut.clk)
      dut.rx_byte.value = rxq[0]
      dut.rx_valid.value = 1
      del rxq[0]
      n_rx += 1
      await FallingEdge(dut.clk)
      dut.rx_valid.value = 0
      continue
    if int(dut.tx_valid.value) == 1:
      await FallingEdge(dut.clk)
      b = int(dut.tx_byte.value)
      dut.tx_ready.value = 1
      await FallingEdge(dut.clk)       # Byte accepted on the rising edge
      dut.tx_ready.value = 0
      txq.append(b)
      n_tx += 1
      if len(txq) < 4096:
        continue
    await First(RisingEdge(dut.tx_valid), Timer(100, unit="ns"))
  srv.close()
