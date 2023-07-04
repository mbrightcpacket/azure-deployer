#!/bin/bash
set -ex

boot_config_file="/home/cpacket/boot_config.toml"

capture_nic_index="0"
capture_nic="eth0"

touch "$boot_config_file"
chmod a+w "$boot_config_file"

cat >"$boot_config_file" <<EOF_BOOTCFG
decap_mode = "vxlan"
vm_type = "azure"
capture_mode = "libpcap"
num_pcap_bufs = 2
eth_dev = "$capture_nic"
capture_nic_index = $capture_nic_index
capture_nic_eth = "$capture_nic"
EOF_BOOTCFG
