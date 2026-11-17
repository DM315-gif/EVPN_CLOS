#!/bin/sh
# Ждём, пока zebra добавит VTEP-адрес на lo
n=0
while ! ip -4 addr show dev lo | grep -q '10.0.0.21'; do
  sleep 1; n=$((n+1)); [ "$n" -ge 20 ] && break
done

# ---------- VRF ----------
# CUST-WEB -> таблица 50010 (номер L3VNI), CUST-BD -> 50020
ip link add CUST-WEB type vrf table 50010
ip link set CUST-WEB up

ip link add CUST-BD type vrf table 50020
ip link set CUST-BD up


# ---------- L3VNI 50010 (VRF CUST-WEB) ----------
ip link add vxlan50010 type vxlan id 50010 local 10.0.0.21 dstport 4789 nolearning
ip link set vxlan50010 mtu 9000
ip link set vxlan50010 address 44:00:00:05:01:10
ip link set vxlan50010 master CUST-WEB
ip link set vxlan50010 up

# ---------- L3VNI 50020 (VRF CUST-BD) ----------
ip link add vxlan50020 type vxlan id 50020 local 10.0.0.21 dstport 4789 nolearning
ip link set vxlan50020 mtu 9000
ip link set vxlan50020 address 44:00:00:05:01:20
ip link set vxlan50020 master CUST-BD
ip link set vxlan50020 up


# ============================================================
# CUST-WEB: L2VNI 10120, шлюз 10.10.20.254
# Подключение: eth3 -> server1 (10.10.20.1/24)
# ============================================================
ip link add br-cust type bridge 
ip link set br-cust mtu 9000
ip link set br-cust address 44:00:00:01:01:20
ip link add vxlan10120 type vxlan id 10120 local 10.0.0.21 dstport 4789 nolearning 
ip link set vxlan10120 mtu 9000
ip link set vxlan10120 master br-cust addrgenmode none
ip link set vxlan10120 type bridge_slave neigh_suppress on learning off 

# порт для сервера
ip link set eth3 master br-cust
ip link set vxlan10120 up
ip link set eth3 up
ip link set br-cust master CUST-WEB 
ip link set br-cust up

# SVI anycast GW
ip addr add 10.10.20.254/24 dev br-cust 


# ============================================================
# CUST-BD: L2VNI 10220, шлюз 10.20.20.254
# Подключение: eth4 -> server2 (10.20.20.2/24)
# ============================================================
ip link add br-cust-bd type bridge
ip link set br-cust-bd mtu 9000
ip link set br-cust-bd address 44:00:00:01:02:20 

ip link add vxlan10220 type vxlan id 10220 local 10.0.0.21 dstport 4789 nolearning 
ip link set vxlan10220 mtu 9000
ip link set vxlan10220 master br-cust-bd addrgenmode none
ip link set vxlan10220 type bridge_slave neigh_suppress on learning off 

# порт для сервера
#ip link set eth4 master br-cust-bd 
#ip link set eth4 up 
ip link add bond20 type bond mode 802.3ad miimon 100 xmit_hash_policy layer3+4
ip link set eth4 master bond20
ip link set bond20 master br-cust-bd
ip link set bond20 up


ip link set vxlan10220 up 
ip link set br-cust-bd master CUST-BD 
ip link set br-cust-bd up 

# SVI anycast GW 
ip addr add 10.20.20.254/24 dev br-cust-bd 


# Приоритезация TC на исходящих интерфейсах
set -e

for DEV in eth1 eth2; do
  tc qdisc del dev $DEV root 2>/dev/null || true

  tc qdisc add dev $DEV root handle 1: htb default 30
  tc class add dev $DEV parent 1: classid 1:10 htb rate 80mbit ceil 10mbit
  tc class add dev $DEV parent 1: classid 1:30 htb rate 20mbit ceil 10mbit
  tc filter add dev $DEV parent 1: protocol ip u32 \
    match ip tos 0x28 0xfc \
    flowid 1:10
done