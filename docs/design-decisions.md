# Design Decisions — CLOS-фабрика EVPN/VXLAN


### 1. BGP ASN план

```

| Узел | Роль | Underlay AS |
|:-----|:-----|:------------|
| spine1 | Spine, RR overlay | 65001 |
| spine2 | Spine, RR overlay | 65002 |
| leaf1 | Leaf, DH-node1 | 65100 |
| leaf2 | Leaf, DH-node2 | 65100 |
| leaf3 | Leaf | 65100 | 
| server1...6 | Серверы |
```

---

## 2. Underlay: eBGP с ECMP

### ADR-2.1: eBGP на каждом линке, per-node ASN

**Решение.** Leaf устройство — имеет ASN 65100. spine1 = 65001, spine2 = 65002, border1 = 65201. ECMP включён (`maximum-paths`).

**Почему так.**
- eBGP loop prevention «из коробки» (AS_PATH check) — не нужны доп. механизмы защиты петель;
- уникальный ASN на leaf упрощает диагностику: по AS_PATH сразу видно вход и выход пакета;
- ECMP даёт 2 активных пути leaf↔spine и хеш-балансировку (5-tuple) без Signal-механизмов.

**Отклонённые альтернативы.**
- *OSPF underlay* — сложнее управлять масштабированием и LSA-штормом;
- *iBGP underlay с единым AS* — потребовал бы RR уже для IPv4 unicast и ручного next-hop-self.

### ADR-2.2: /31 вместо /30

**Решение.** Все p2p-линки — /31.

**Почему.** Экономия адресов ×2, стандарт де-факто в фабриках, адресный план остаётся компактным (10.X.0.0/24 хватает на 128 линков). /30 оставлено как допустимая альтернатива.

---

## 3. Overlay: iBGP EVPN

### ADR-3.1: единый Overlay-AS, spines — eBGP

**Решение.** Overlay iBGP: ASN 65100 на всех leaf. Leaf — iBGP-клиенты к loopback'ам spine1 и spine2 (обе RR). Spine не является VTEP и не участвует в L2VNI.

**Почему.**
- разделение underlay/overlay по разным AS даёт чистую изоляцию: изменение overlay-политики не задевает подложку.

---

## 4. RD 

**обязан** быть уникальным на (leaf, L2VNI): уникальный Loopback:L2VNI гарантирует это автоматически. Если бы overlay был eBGP с уникальными ASN на leaf, уникальность давал бы ASN:VNI — здесь ASN один, поэтому уникальность несёт Loopback.

---

## 5. Арендаторы с пересекающимися IP-подсетями

### ADR-5.1: два VRF, изоляция через RT

**Решение.** Два арендатора: CUST-WEB и CUST-BD. Оба могут использовать **одинаковые** подсети (и одинаковые IP серверов).

**Почему так.** Пересечение IP достигается за счёт полной изоляции на L3: разные VRF → разные L3VNI → разные VRF RT. Type-5 маршруты идут в per-VRF таблицы (VRF-CUST-WEB не импортирует RT 65000:50020 и наоборот). Одинаковые VLAN-номера в разных VRF допустимы, т.к. VLAN локальны на каждом leaf.

---

## 6. RD / RT план

### ADR-6.1: RD = Loopback:VNI

| Маршрут | RD | RT |
|:--------|:---|:---|
| Type-2 (MAC/IP), L2VNI | `Loopback0 : L2VNI` (напр. `10.0.0.21:10110`) | `65100 : L2VNI` |
| Type-3 (IMET), L2VNI | `Loopback0 : L2VNI` | `65100 : L2VNI` |
| Type-1 (Ethernet AD), ESI | `Loopback0 : L2VNI` | `65100 : L2VNI` |
| Type-4 (Ethernet Segment), ESI | `Loopback0 : ESI-индекс` | `65100 : L2VNI` |
| Type-5 (IP prefix), L3VNI | `Loopback0 : L3VNI` (напр. `10.0.0.21:50010`) | `65100 : L3VNI` = VRF RT |

**Почему.**
- RD `Loopback:VNI` — уникальность без ручного учёта; для Type-5 это **критично** при symmetric IRB: `overlay index` (VTEP-NEXT-HOP) берётся из RD next-hop и маршрутизирует трафик на правильный leaf;
- RT **ручной и одинаковый на всех leaf** (`65100:VNI`): позволяет легко строить import/export-политики (Border Leaf импортирует RT нескольких VRF), не завязываясь на ASN узла;
- Политика: L2VNI экспортирует свой RT; VRF импортирует VRF RT и, при необходимости, transit RT.

**Отклонённые альтернативы.**
- *RT = ASN:VNI* — неудобно при совмещённом Border (пришлось бы матчить на ASN каждого Border-Leaf);
- *RT = ASN:0* — теряется per-VNI гранулярность.

---

## 7. Anycast Gateway

### ADR-7.1: Anycast GW на всех leaf, единый VIP/VMAC на подсеть

**Почему так.**
- VIP/VMAC объявлен на **каждом** leaf в каждом VNI этого VRF — шлюз живёт на самом ближайшем коммутаторе, трафик north-south идёт через первый hop;
- нет протокола VRRP между leaf — отсутствие выбора active/standby упрощает сбой-сценарии;
- одинаковый VMAC в обоих VRF не вызывает конфликтов: MAC уникален в пределах VNI, а VRF разделены L3VNI.

**Риски.** VIP недоступен для ping из host-пространства на «чужом» leaf — это ожидаемо (anycast, а не HA-pair).

---

## 8. EVPN Multihoming, All-Active (server2 → leaf1+leaf2)

### ADR-8.1: ESI Type-0 (ручной), DF Election Preference-based (RFC 8584)

| Параметр | Значение |
|:---------|:---------|
| ESI | `00:00:00:00:00:44:00:00:05:00:20` (Type-0, ручной, одинаковый на leaf1 и leaf2) |
| Модель | All-Active (обе «ноги» активны для unicast и BUM) |
| DF Election | **Preference-based** (RFC 8584), по нименьшему VTEP IP |
| Маршруты | Type-4 (ES, DF election), Type-1 (Ethernet AD, aliasing), Type-2 (MAC/IP), Type-3 (IMET) |

**Почему так.**
- All-Active даёт полный ECMP вверх от хоста: обе «ноги» передают и принимают unicast; BUM-трафик шлёт только DF (для каждого EVI/ESI — своя роль), что убирает дубликаты.

**Отклонённые альтернативы.**
- *Single-Active вместо All-Active* — проще, но отказоустойчивость хуже: половина полосы простаивает.

---

### ADR-9.2: маршруты, обеспечивающие All-Active

- **Type-1 (Ethernet AD per-ESI)** — объявляет aliasing: MAC хоста достижим через **обе** leaf'ы → ECMP к хосту;
- **Type-4 (Ethernet Segment)** — обмен ESI-инфой и выбор DF (с Route Target per-ESI);
- **Mass withdraw** (сброс Route Target в Type-1 при падении одной leaf) — быстрая сходимость без схода ECMP-таблиц целиком.

---

## 10. MTU

### ADR-10.1: MTU 9216 на транзитных линках, 9000 на host-интерфейсах

**Почему.** VXLAN добавляет ~50 байт (outer Ether/IP/UDP/VXLAN). Если бы host-MTU и transit были одинаковыми (9000), inner-jumbo пакеты не проходили бы. 9216 = 9000 + 50 + запас на инкапсуляцию с опциональными заголовками.


---