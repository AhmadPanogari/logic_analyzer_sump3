"""
Build the ARM program of the antminer_s9_la16eth bitstream with Vitis 2024.2
or 2025.x ( unified, Python scripting ). Vivado and Vitis must be the same
version: the platform step turns the XSA into a system device tree and fails
( "System DTS File does not exist" ) on an XSA from a newer Vivado.

  vitis -s sw/la16_eth/vitis_build.py [xsa] [--ip 192.168.1.10] [--ws dir]

  xsa   default vivado/build_antminer_s9_la16eth/la_top.xsa
  --ip  static board IP ( netmask 255.255.255.0, gateway x.x.x.1 ),
        default 192.168.1.10
  --ws  Vitis workspace ( deleted first ). Default on Windows: folder la16ws at the root of
        the drive of the XSA. The BSP build makes paths of ~200 characters
        below the workspace and fails past Windows' 260 ( "opening
        dependency file ... No such file or directory" ), so keep it short.

Steps: platform from the XSA ( standalone, ps7_cortexa9_0 ) with lwip220
( RAW API, static IP, 1 Gbit/s fixed link: the S9 PHY is a Broadcom part the
lwIP PHY code does not know, the fixed setting only uses IEEE registers ),
then the "lwIP Echo Server" template app with echo.c replaced by
la16_server.c. The ELF is copied next to the XSA as la16_eth.elf, where
vivado/s9_jtag_load.tcl downloads and starts it.
"""
import os
import re
import shutil
import sys

import vitis

here = os.path.dirname(os.path.abspath(__file__))
args = [a for a in sys.argv[1:] if not a.startswith("--")]
opts = {}
for opt in ("--ip", "--ws"):
    if opt in sys.argv:
        opts[opt] = sys.argv[sys.argv.index(opt) + 1]
        args = [a for a in args if a != opts[opt]]
ip = opts.get("--ip", "192.168.1.10")
xsa = os.path.abspath(args[0]) if args else os.path.normpath(
    os.path.join(here, "../../vivado/build_antminer_s9_la16eth/la_top.xsa"))
if not os.path.isfile(xsa):
    sys.exit("ERROR: %s not found. Build first: build.bat antminer_s9_la16eth" % xsa)
octets = [int(x) for x in ip.split(".")]
if len(octets) != 4:
    sys.exit("ERROR: --ip a.b.c.d")

# The device tree generator takes its board file name from the environment
# variable "board" ( any case on Windows ): an old "set BOARD=..." in this
# cmd window gives "<name>.dtsi board file is not present in DTG"
for k in [k for k in os.environ if k.lower() == "board"]:
    print("NOTE: ignoring environment variable %s=%s" % (k, os.environ[k]))
    del os.environ[k]

out_dir = os.path.dirname(xsa)
if "--ws" in opts:
    ws = os.path.abspath(opts["--ws"])
elif os.name == "nt":
    ws = os.path.splitdrive(out_dir)[0] + "\\la16ws"
else:
    ws = os.path.join(out_dir, "vitis_ws")
if os.path.exists(ws):
    shutil.rmtree(ws)
print("XSA      :", xsa)
print("Workspace:", ws)
print("Board IP :", ip)

# Which Vivado wrote the XSA ( a zip ): must not be newer than this Vitis
try:
    import zipfile
    with zipfile.ZipFile(xsa) as z:
        for name in z.namelist():
            if name.endswith((".json", ".xml")) and "/" not in name:
                found = sorted(set(re.findall(rb"20[12]\d\.\d", z.read(name))))
                if found:
                    print("XSA %-20s mentions versions %s" % (name, b" ".join(found).decode()))
                for m in re.findall(rb'"?[Bb]oard[A-Za-z_]*"?\s*[:=]\s*"([^"]*)"', z.read(name)):
                    print("XSA %-20s board = '%s'" % (name, m.decode()))
except Exception as e:
    print("NOTE: could not read the XSA: %s" % e)

# Run the system device tree generator ourselves first: when it fails inside
# create_platform_component, Vitis only says "System DTS File does not exist"
import subprocess
vitis_root = os.environ.get("XILINX_VITIS") or os.path.normpath(
    os.path.join(os.path.dirname(vitis.__file__), "..", ".."))
exe = ".bat" if os.name == "nt" else ""
sdt_dir = os.path.join(out_dir, "sdt_check")
if os.path.exists(sdt_dir):
    shutil.rmtree(sdt_dir)
tcl = "sdtgen set_dt_param -xsa {%s} -dir {%s}; sdtgen generate_sdt" % (
    xsa.replace("\\", "/"), sdt_dir.replace("\\", "/"))
# 2025.x ships a sdtgen launcher, 2024.2 has the sdtgen command inside xsct
for tool in ("sdtgen", "xsct"):
    path = os.path.join(vitis_root, "bin", tool + exe)
    if os.path.isfile(path):
        print("Running:", path, "-eval", tcl)
        res = subprocess.run([path, "-eval", tcl], capture_output=True, text=True,
                             shell=(os.name == "nt"))
        print(res.stdout[-6000:])
        print(res.stderr[-6000:])
        if not os.path.isfile(os.path.join(sdt_dir, "system-top.dts")):
            sys.exit("ERROR: %s did not produce system-top.dts, see its output above" % tool)
        print("sdtgen OK: %s" % os.path.join(sdt_dir, "system-top.dts"))
        break
else:
    print("NOTE: neither sdtgen nor xsct found in %s\\bin, skipping the check" % vitis_root)


def dump_logs(root):
    """Print the tail of every log Vitis left in the workspace."""
    for r, _, files in os.walk(root):
        for f in files:
            if f.endswith(".log"):
                path = os.path.join(r, f)
                try:
                    with open(path, errors="replace") as fh:
                        tail = fh.read()[-3000:]
                except OSError:
                    continue
                print("----- %s -----" % path)
                print(tail)


client = vitis.create_client()
client.set_workspace(path=ws)

domain_name = "standalone_ps7_cortexa9_0"
# no_boot_bsp: no FSBL ( the board boots over JTAG, s9_jtag_load.tcl does the
# PS init ). Building the FSBL is slow and can hang the platform build.
try:
    try:
        platform = client.create_platform_component(
            name="s9_platform", hw_design=xsa, os="standalone",
            cpu="ps7_cortexa9_0", domain_name=domain_name, no_boot_bsp=True)
    except TypeError:
        print("NOTE: this Vitis has no no_boot_bsp option, the FSBL is built too")
        platform = client.create_platform_component(
            name="s9_platform", hw_design=xsa, os="standalone",
            cpu="ps7_cortexa9_0", domain_name=domain_name)
except Exception as e:
    dump_logs(ws)
    print("ERROR: platform creation failed: %s" % e)
    vitis.dispose()
    sys.exit(1)
domain = platform.get_domain(name=domain_name)
domain.set_lib(lib_name="lwip220")
LWIP = (("lwip220_api_mode", "RAW_API"),
        ("lwip220_dhcp", "false"),
        ("lwip220_temac_phy_link_speed", "CONFIG_LINKSPEED1000"),
        ("lwip220_tcp_snd_buf", "32768"),
        ("lwip220_tcp_wnd", "16384"),
        ("lwip220_mem_size", "262144"),
        ("lwip220_memp_n_tcp_seg", "1024"),
        ("lwip220_pbuf_pool_size", "2048"))


def set_lwip(dom):
    for param, value in LWIP:
        try:
            dom.set_config(option="lib", param=param, value=value, lib_name="lwip220")
            print("lwip220: %s = %s" % (param, value))
        except Exception as e:                  # keep going, report it
            print("NOTE: lwip220 %s not set: %s" % (param, e))


set_lwip(domain)
status = platform.build()
print("platform.build():", status)

# Ask Vitis where it exported the platform ( it only accepts a .xpfm it
# knows in its platform repositories )
xpfm = None
try:
    xpfm = client.find_platform_in_repos("s9_platform")
except Exception as e:
    print("NOTE: find_platform_in_repos: %s" % e)
if not xpfm:
    found = [os.path.join(r, f) for r, _, fs in os.walk(ws) for f in fs if f.endswith(".xpfm")]
    print("xpfm files in the workspace:", found or "none")
    if not found:
        dump_logs(ws)
        print("ERROR: the platform build did not export a .xpfm ( platform.build() = %s )" % status)
        vitis.dispose()
        sys.exit(1)
    xpfm = found[0]
    try:
        client.add_platform_repos(platform=[os.path.dirname(os.path.dirname(xpfm))])
    except Exception as e:
        print("NOTE: add_platform_repos: %s" % e)
print("Platform :", xpfm)
app = client.create_app_component(name="la16_eth", platform=xpfm,
                                  domain=domain_name, template="lwip_echo_server")

# The template asks for DHCP in its library settings; put ours back and
# rebuild the BSP so the app links against them
platform = client.get_component(name="s9_platform")
set_lwip(platform.get_domain(name=domain_name))
platform.build()

src = os.path.join(ws, "la16_eth", "src")
echo = os.path.join(src, "echo.c")
if os.path.exists(echo):
    os.remove(echo)
shutil.copy(os.path.join(here, "la16_server.c"), src)

# Static IP of the template's main.c
main_c = os.path.join(src, "main.c")
with open(main_c) as f:
    text = f.read()
text, n = re.subn(r"IP4_ADDR\(&ipaddr,\s*\d+,\s*\d+,\s*\d+,\s*\d+\)",
                  "IP4_ADDR(&ipaddr, %d, %d, %d, %d)" % tuple(octets), text)
text = re.sub(r"IP4_ADDR\(&gw,\s*\d+,\s*\d+,\s*\d+,\s*\d+\)",
              "IP4_ADDR(&gw, %d, %d, %d, 1)" % tuple(octets[:3]), text)
# DHCP fallback ( only used if DHCP ends up enabled anyway )
text = re.sub(r"IP4_ADDR\(&\(echo_netif->ip_addr\),\s*\d+,\s*\d+,\s*\d+,\s*\d+\)",
              "IP4_ADDR(&(echo_netif->ip_addr), %d, %d, %d, %d)" % tuple(octets), text)
text = re.sub(r"IP4_ADDR\(&\(echo_netif->gw\),\s*\d+,\s*\d+,\s*\d+,\s*\d+\)",
              "IP4_ADDR(&(echo_netif->gw), %d, %d, %d, 1)" % tuple(octets[:3]), text)
with open(main_c, "w") as f:
    f.write(text)
print("main.c: static IP set ( %d place%s )" % (n, "" if n == 1 else "s"))

app.build()

elf = None
for root, _, files in os.walk(os.path.join(ws, "la16_eth")):
    if "la16_eth.elf" in files:
        elf = os.path.join(root, "la16_eth.elf")
if not elf:
    sys.exit("ERROR: la16_eth.elf not produced, see the build output above")
shutil.copy(elf, os.path.join(out_dir, "la16_eth.elf"))
with open(os.path.join(out_dir, "la16_eth_ip.txt"), "w") as f:
    f.write(ip + "\n")
print("=" * 70)
print(" ELF : %s" % os.path.join(out_dir, "la16_eth.elf"))
print(" Next: s9_jtag_load.bat %s" % out_dir)
print(" PulseView: driver la16, Network ( Raw TCP ) %s port 5555" % ip)
print("=" * 70)
vitis.dispose()
