#!/usr/bin/env python3
"""
la.py : One launcher for the XC7Z010 SUMP3 logic analyzer host software.

  python host/la.py server --port COM5          # 1) start bd_server.py ( UART <-> TCP )
  python host/la.py gui                         # 2) start sump3.py ( arm / trigger / download )
  python host/la.py view capture.vcd            #    convert any SUMP3 VCD and open PulseView

Data flow:
  FPGA --UART/MesaBus--> bd_server.py --TCP 21567--> sump3.py --save_vcd-->
  sump3_vcd2sr.py --*.sr--> PulseView

Everything runs inside host/work/ ( created on first use, not in git ) so the
files sump3.py and bd_server.py generate stay out of the source tree.

In sump3.py click [Acquisition] -> [Connect], set triggers, [Acquire],
then [Save_VCD]. sump3.py calls the viewer hook configured here, which
converts the VCD into a sigrok session and opens it in PulseView.
"""

import argparse
import os
import re
import stat
import subprocess
import sys

HOST_DIR  = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR  = os.path.dirname(HOST_DIR)
WORK_DIR  = os.path.join(HOST_DIR, "work")
SUMP3_PY  = os.path.join(ROOT_DIR, "third_party", "sump3", "python", "sump3.py")
BD_SERVER = os.path.join(ROOT_DIR, "third_party", "MesaBusProtocol", "python", "bd_server.py")
VCD2SR    = os.path.join(HOST_DIR, "sump3_vcd2sr.py")

# SUMP3 capture clock in la_sump3.v ( ck_freq_mhz ). Used as PulseView samplerate.
DEFAULT_SAMPLERATE = "100M"

# Settings la.py enforces in host/work/sump3.ini every time the GUI starts.
# Everything else is left to sump3.py ( it rewrites the file on exit ).
SUMP3_INI_FORCED = {
  "bd_connection"      : "bd_server",
  "bd_server_ip"       : "127.0.0.1",
  "bd_server_socket"   : "21567",
  "aes_authentication" : "0",
  "sump_uut_addr"      : "00000098",
  "uut_name"           : "XC7Z010_LA",
  # Download every pod at [Acquire]. save_vcd does not fetch pods on demand,
  # so with "1" a pod not shown in any window would be missing from the VCD.
  "sump_download_ondemand" : "0",
  "vcd_viewer_en"      : "1",
  "vcd_viewer_gtkw_en" : "0",    # PulseView does not use GTKwave *.gtkw files
  "vcd_hierarchical"   : "1",
  "vcd_hubpod_names"   : "0",
  "vcd_hubpod_nums"    : "0",
  "vcd_group_names"    : "0",
}


def ensure_work_dir():
  if not os.path.isdir(WORK_DIR):
    os.makedirs(WORK_DIR)


def check_submodules():
  for f in (SUMP3_PY, BD_SERVER):
    if not os.path.isfile(f):
      sys.exit("ERROR: %s not found.\n"
               "       Run: python fetch_third_party.py   ( from the repo root )" % f)


def update_ini(path, forced):
  """Set key = value lines in a sump3.ini style file, keeping other lines."""
  lines = []
  if os.path.isfile(path):
    with open(path) as f:
      lines = f.read().splitlines()
  done = set()
  for i, line in enumerate(lines):
    m = re.match(r"^\s*([A-Za-z0-9_]+)\s*=", line)
    if m and m.group(1) in forced:
      lines[i] = "%s = %s" % (m.group(1), forced[m.group(1)])
      done.add(m.group(1))
  for k, v in forced.items():
    if k not in done:
      lines.append("%s = %s" % (k, v))
  with open(path, "w") as f:
    f.write("\n".join(lines) + "\n")


def write_viewer_hook(samplerate, pulseview):
  """
  sump3.py launches the VCD viewer with os.system( "<path> <vcd> <gtkw>" ).
  Create a small script there that runs the converter with this Python.
  """
  extra = ""
  if pulseview:
    extra = ' --pulseview "%s"' % pulseview
  if os.name == "nt":
    hook = os.path.join(WORK_DIR, "pulseview_hook.bat")
    with open(hook, "w") as f:
      f.write("@echo off\r\n")
      f.write('"%s" "%s" --open -r %s%s "%%~1"\r\n' %
              (sys.executable, VCD2SR, samplerate, extra))
  else:
    hook = os.path.join(WORK_DIR, "pulseview_hook.sh")
    with open(hook, "w") as f:
      f.write("#!/bin/sh\n")
      f.write('exec "%s" "%s" --open -r %s%s "$1"\n' %
              (sys.executable, VCD2SR, samplerate, extra))
    os.chmod(hook, os.stat(hook).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
  if " " in hook:
    print("WARNING: sump3.py does not quote the viewer path. The path\n"
          "         %s\n"
          "         contains spaces, so [Save_VCD] can not launch PulseView.\n"
          "         Move the repository to a path without spaces." % hook)
  return hook


def cmd_server(args):
  check_submodules()
  ensure_work_dir()
  ini = os.path.join(WORK_DIR, "bd_server.ini")
  with open(ini, "w") as f:
    f.write("bd_connection      = usb      # usb\n")
    f.write("bd_protocol        = mesa     # mesa\n")
    f.write("usb_port           = %s\n" % args.port)
    f.write("tcp_port           = %d\n" % args.tcp_port)
    f.write("baudrate           = %d\n" % args.baud)
    f.write("mesa_slot          = 00\n")
    f.write("mesa_subslot       = 0\n")
    f.write("debug_bd_en        = %d\n" % (1 if args.debug else 0))
    f.write("debug_tcp_en       = %d\n" % (1 if args.debug else 0))
    f.write("aes_authentication = 0\n")
    f.write("aes_e2e_encryption = 0\n")
    f.write("aes_key            = 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\n")
  try:
    import serial  # noqa: F401
  except ImportError:
    sys.exit("ERROR: pyserial missing. Run: pip install pyserial")
  print("bd_server.py : %s @ %d baud <-> TCP %d   ( Ctrl+C to stop )" %
        (args.port, args.baud, args.tcp_port))
  return subprocess.call([sys.executable, BD_SERVER, ini], cwd=WORK_DIR)


def cmd_gui(args):
  check_submodules()
  ensure_work_dir()
  for mod in ("pygame", "pygame_gui"):
    try:
      __import__(mod)
    except ImportError:
      sys.exit("ERROR: %s missing. Run: pip install -r host/requirements.txt" % mod)
  hook = write_viewer_hook(args.samplerate, args.pulseview)
  forced = dict(SUMP3_INI_FORCED)
  forced["vcd_viewer_path"] = hook
  forced["bd_server_socket"] = str(args.tcp_port)
  update_ini(os.path.join(WORK_DIR, "sump3.ini"), forced)
  print("sump3.py : [Save_VCD] -> %s -> PulseView" % os.path.basename(hook))
  return subprocess.call([sys.executable, SUMP3_PY], cwd=WORK_DIR)


def cmd_view(args):
  cmd = [sys.executable, VCD2SR, "--open", "-r", args.samplerate, args.vcd]
  if args.pulseview:
    cmd += ["--pulseview", args.pulseview]
  return subprocess.call(cmd + args.extra)


def main():
  p = argparse.ArgumentParser(description="XC7Z010 SUMP3 logic analyzer launcher")
  sub = p.add_subparsers(dest="cmd")

  s = sub.add_parser("server", help="Start bd_server.py ( UART <-> TCP bridge )")
  s.add_argument("--port", required=True, help="Serial port, e.g. COM5 or /dev/ttyUSB0")
  s.add_argument("--baud", type=int, default=921600, help="Baud rate ( FPGA autobauds )")
  s.add_argument("--tcp-port", type=int, default=21567)
  s.add_argument("--debug", action="store_true", help="Log traffic to bd_server_*_log.txt")

  g = sub.add_parser("gui", help="Start sump3.py with the PulseView viewer hook")
  g.add_argument("-r", "--samplerate", default=DEFAULT_SAMPLERATE,
                 help="SUMP3 capture clock ( default 100M )")
  g.add_argument("--pulseview", help="Path to pulseview executable")
  g.add_argument("--tcp-port", type=int, default=21567)

  v = sub.add_parser("view", help="Convert a VCD to .sr and open PulseView")
  v.add_argument("vcd")
  v.add_argument("-r", "--samplerate", default=DEFAULT_SAMPLERATE)
  v.add_argument("--pulseview", help="Path to pulseview executable")
  v.add_argument("extra", nargs=argparse.REMAINDER,
                 help="Extra options for sump3_vcd2sr.py ( e.g. --start 0.001 )")

  args = p.parse_args()
  if args.cmd == "server":
    sys.exit(cmd_server(args))
  elif args.cmd == "gui":
    sys.exit(cmd_gui(args))
  elif args.cmd == "view":
    sys.exit(cmd_view(args))
  p.print_help()


if __name__ == "__main__":
  main()
