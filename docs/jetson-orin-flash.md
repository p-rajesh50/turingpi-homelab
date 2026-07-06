# Jetson Orin NX — JetPack 7 Flashing Guide (TuringPi 2.5, Slot 2)

Referenced from `docs/day0-runbook.md` Phase 10 and `ansible/playbooks/07-jetson-orin.yml`.

## This setup

| | |
|---|---|
| Board | TuringPi 2.5 |
| Slot | 2 |
| Module | Nvidia Jetson Orin NX 16GB |
| Target hostname | `orin-nx` |
| Target static IP | `10.0.0.14` / gateway `10.0.0.1` |
| Root device | NVMe SSD, already physically installed at `/dev/nvme0n1` |
| JetPack version | 7 (latest) |

After this guide, `orin-nx` should be reachable over SSH at `10.0.0.14` with JetPack 7 booted from
the NVMe drive. From there, `make jetson-orin` configures the rest (Ollama, Open WebUI, ML stack)
— see "Hand-off" at the end.

## ⚠️ Read this before downloading anything

NVIDIA's SDK Manager **does not support flashing Orin modules on third-party carrier boards** like
TuringPi 2 — TuringPi's own documented procedure (`docs.turingpi.com/docs/orin-nxnano-flashing-os`)
instead flashes directly via the L4T (Linux for Tegra) BSP and NVIDIA's `l4t_initrd_flash.sh`
script, driven through the board's BMC-controlled USB recovery mode. That procedure is verified by
TuringPi against **L4T R35.3.1 (JetPack 5.x)**.

JetPack 7 is a new generation (Ubuntu 24.04, kernel 6.8) that introduces a "unified ISO-based"
installer NVIDIA built primarily for their own developer kits. Whether that ISO installer works
unmodified on a third-party carrier board like TuringPi 2 is **not confirmed** as of this writing.

**Before you download any BSP files:** check `docs.turingpi.com` and the TuringPi forum
(forum.turingpi.com) for a JetPack 7 or Orin-NX-16GB-specific confirmation or updated procedure.
The board-level mechanics below (BMC recovery mode, EEPROM workaround, external-device flash to
NVMe) are very likely to still apply regardless of L4T version — but the exact BSP tarball names,
download URLs, and possibly the flashing script itself may differ from the R35.3.1 example given
here. Substitute whatever NVIDIA's actual JetPack 7 downloads turn out to be.

## 1. Host machine prerequisites

You need a **separate Ubuntu x86_64 machine** for flashing (not this WSL2 controller, and not the
Orin NX itself — the flash is driven by the L4T tools running on an x86_64 Ubuntu host, connected
to the Orin NX over USB via the TuringPi's USB recovery-mode pass-through).

```bash
sudo apt update && sudo apt -y upgrade && sudo apt -y dist-upgrade
sudo apt install -y qemu-user-static nano ssh
```

Download from NVIDIA's Jetson Linux developer portal (login required):
- **Jetson Linux Driver Package (BSP)** — for JetPack 7, use whatever archive NVIDIA publishes for
  Orin NX under the JetPack 7 release (verify the exact filename/version at download time)
- **Sample Root Filesystem** — matching L4T version

Extract both into a working directory:

```bash
cd ~
tar xpf Downloads/Jetson_Linux_<version>_aarch64.tbz2
sudo tar xpf Downloads/Tegra_Linux_Sample-Root-Filesystem_<version>_aarch64.tbz2 \
  -C Linux_for_Tegra/rootfs/
```

## 2. EEPROM workaround (required)

TuringPi 2 does not have the onboard EEPROM the stock flasher expects at this address. Without
this patch, flashing will fail trying to read it:

```bash
sed -i 's/cvb_eeprom_read_size = <0x100>/cvb_eeprom_read_size = <0x0>/g' \
  Linux_for_Tegra/bootloader/t186ref/BCT/tegra234-mb2-bct-misc-p3767-0000.dts
```

## 3. Prepare firmware + optional headless first boot

```bash
cd Linux_for_Tegra/
sudo ./apply_binaries.sh
sudo ./tools/l4t_flash_prerequisites.sh

# Headless setup — comes up over SSH with this hostname/user instead of
# needing an HDMI console + first-boot wizard:
sudo ./tools/l4t_create_default_user.sh -u ubuntu -p ubuntu -a -n orin-nx
```

(Password matches the same default-then-forced-change pattern used for the RK1 nodes — see
`scripts/os-flash/flash-rk1.sh`.)

## 4. Put the module into USB recovery mode via the BMC (tpi CLI)

Same `tpi` tool and BMC credentials already used for the RK1 nodes
(`scripts/os-flash/flash-rk1.sh`, `scripts/bmc/bmc-power.sh`) — this is the one part of the
procedure that's fully TuringPi-board-specific and independent of L4T/JetPack version:

```bash
source ~/.turingpi   # loads BMC_IP, BMC_USER, BMC_PASSWORD

tpi --host $BMC_IP --user $BMC_USER --password $BMC_PASSWORD power off --node 2
tpi --host $BMC_IP --user $BMC_USER --password $BMC_PASSWORD usb --node 2 device
tpi --host $BMC_IP --user $BMC_USER --password $BMC_PASSWORD power on --node 2
```

Connect a USB A-A cable (must be a plain data-capable cable, not a "smart"/charge-only one)
between the TuringPi's USB-OTG port and the flashing host. Verify the module is detected in
recovery mode:

```bash
lsusb   # should show "Nvidia Corp. APX"
```

Give it ~30 seconds after power-on before checking — the USB handoff isn't instant.

## 5. Flash to the installed NVMe

```bash
sudo ./tools/kernel_flash/l4t_initrd_flash.sh --external-device nvme0n1p1 \
  -c tools/kernel_flash/flash_l4t_external.xml \
  -p "-c bootloader/t186ref/cfg/flash_t234_qspi.xml" \
  --showlogs --network usb0 jetson-orin-nano-devkit internal
```

(`nvme0n1p1` targets the NVMe SSD already installed in slot 2, per this setup — no SD card or
external USB drive needed. The `jetson-orin-nano-devkit` board config argument is what TuringPi's
own docs use for Orin NX/Nano flashing via this script; confirm this hasn't changed for your
specific JetPack 7 BSP release notes.)

Expect this to take 15-30 minutes. The USB device will transition from "Nvidia Corp. APX" to a
Linux-for-Tegra device partway through — that's normal. The flasher exits on its own when done.
The fan may not spin up right away; passive cooling at idle is normal.

## 6. Power down, move to normal boot

```bash
tpi --host $BMC_IP --user $BMC_USER --password $BMC_PASSWORD power off --node 2
tpi --host $BMC_IP --user $BMC_USER --password $BMC_PASSWORD usb --node 2 host
tpi --host $BMC_IP --user $BMC_USER --password $BMC_PASSWORD power on --node 2
```

Wait ~60 seconds for first boot from NVMe.

## 7. Set the static IP via NetworkManager

SSH in over DHCP first (check your router/`make discover`-style lookup for the temporary address),
then find the real interface name and set the static IP permanently:

```bash
nmcli device status                 # find the ethernet interface name (e.g. eth0)

nmcli con mod <connection-name> \
  ipv4.addresses 10.0.0.14/24 \
  ipv4.gateway 10.0.0.1 \
  ipv4.dns 10.0.0.1 \
  ipv4.method manual

nmcli con up <connection-name>
```

Confirm: `ip -4 addr show <interface-name>` shows `10.0.0.14/24`.

## 8. Verify the GPU is detected

```bash
nvidia-smi
```

If `nvidia-smi` doesn't behave as expected on this JetPack release (Jetson GPU tooling has
historically lagged behind desktop/datacenter `nvidia-smi` support), fall back to:

```bash
tegrastats
```
which should show live GPU (`GR3D`) utilization.

## Hand-off to Ansible

Once `orin-nx` is reachable at `10.0.0.14` over SSH with the GPU confirmed working:

```bash
make jetson-orin
```

This runs `ansible/playbooks/07-jetson-orin.yml` → `ansible/roles/jetson-orin`, which installs
Docker + the NVIDIA container toolkit, Ollama (pulling `gemma3:12b`, `mistral`, `openchat`,
`nomic-embed-text` — from `ollama_models_orin` in `ansible/inventory/group_vars/all/vars.yml`),
Open WebUI on port 3000, and the Python ML virtualenv.

**No LiteLLM changes needed** — the gateway (`ansible/roles/litellm`) is already configured to
route to `10.0.0.14:11434`; it just needs Ollama actually listening there, which this step
provides.
