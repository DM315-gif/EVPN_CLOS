# Запуск сети

#### Установка Docker (Ubuntu/Debian)
```bash
curl -fsSL https://get.docker.com | bash
sudo usermod -aG docker $USER
```
> ⚠️ **Важно:** после выполнения этих шагов требуется перелогиниться или выполнить `newgrp docker`, иначе ContainerLab не сможет управлять контейнерами.


#### Установка Containerlab
```bash
bash -c "$(curl -sL https://get.containerlab.dev)"
```


#### Проверка
```bash
docker --version
containerlab version
```


#### Загрузите из репозиторий
```bash
git clone https://github.com/DM315-gif/EVPN_CLOS.git
```

#### Перейдите в папку репозитория "configs"
```bash
 cd EVPN_CLOS/configs/
```


#### Создайте файл "lab1.clab.yml"
```bash
touch lab1.clab.yml
```


#### Из папки "lab1" запустите ContainerLab
```bash
sudo containerlab deploy -t lab1.clab.yml
```


#### Отключить лабу
```bash
sudo containerlab destroy -t lab1.clab.yml 
```


#### Перезапуск leaf1
```bash
sudo clab restart -t lab1.clab.yml leaf1
```


# Проверка работоспособности

#### Cтатус лабы
```bash
sudo containerlab inspect -t lab1.clab.yml   
```


#### Зайти в CLI(FRR) маршрутизатора 
```bash
docker exec -it clab-lab1-leaf1 vtysh
```


#### Вывести таблицу VNI на leaf1, убедиться что MAC'и/ARP'ы изучаются
```bash
docker exec clab-lab1-leaf1 vtysh -c "show evpn vni"
docker exec clab-lab1-leaf1 vtysh -c "show bgp l2vpn evpn summary"
```


#### Вывести глобальную таблицы маршрутизации VRF убедиться, что есть маршруты и ECMP
```bash
docker exec clab-lab1-leaf1 vtysh -c "show ip route"
docker exec clab-lab1-leaf1 vtysh -c "show ip route vrf CUST-BD"
docker exec clab-lab1-leaf1 vtysh -c "show ip route vrf CUST-WEB"
```


#### Проверить, что серверу доступен шлюз
```bash
docker exec -it clab-lab1-server1 ping 10.10.20.254
```


#### Проверка прохождения трафика от сервера к серверу в одном L2VNI
```bash
docker exec -it clab-lab1-server4 ping 10.10.10.5 
```


#### Проверка прохождения трафика от сервера к серверу в разных L2VNI
```bash
docker exec -it clab-lab1-server4 ping 10.10.20.1 
```


#### Проверка Anycast Gateway
```bash
docker exec -it clab-lab1-server5 arp | grep 10.10.10.254
docker exec -it clab-lab1-server4 arp | grep 10.10.10.254
```
Ожидается одинаковый MAC-адрес на выводе


#### Проверка TC. Запускаем пинг с DSCP 10 и смотрим статистику по классам
```bash
docker exec -it clab-lab1-server4 ping -Q 0x28 -c 10 10.10.10.5
docker exec -it clab-lab1-leaf2 tc -s filter show dev eth2 parent 1:
```
Ожидается вывод с задаными фильтрами и строка "(success Х )", где Х - кол-во пакетов 


# Graceful shutdown одного leaf 

#### Административное гашение BGP с уведомлением соседей
#### (Cease / Administrative Shutdown по RFC 8203, конфигурация сохраняется)
```bash
docker exec clab-lab1-leaf1 vtysh -c "conf t" -c "router bgp 65100" \
  -c "bgp shutdown message 'planned maintenance leaf1'"
```


#### Для случаев, когда нужно погасить одного соседа — 
```bash
docker exec clab-lab1-leaf1 vtysh -c "conf t" -c "router bgp 65100" -с "neighbor <spine> shutdown"
```


#### Отключение leaf1
```bash
docker exec clab-lab1-leaf1 frrinit.sh stop
```


#### Возврат leaf1
```bash
docker exec clab-lab1-leaf1 frrinit.sh start
```


#### Включение BGP
docker exec clab-lab1-leaf1 vtysh -c "conf t" -c "router bgp 65100" -c "no bgp shutdown"
```
